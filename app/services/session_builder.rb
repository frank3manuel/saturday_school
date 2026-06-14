# frozen_string_literal: true

# Assembles a spaced-review session (plan §6).
#
# Given a scope (all due / a subject / a lesson) it:
#   1. selects the *due* items for that scope (index-backed `Item.due`),
#   2. orders them **most-overdue first** (the longest-waiting items lead),
#   3. **interleaves across lessons** (a desirable difficulty — plan §1, §6), and
#   4. caps the count (default ~20).
#
# For a student the "all due" queue is the **union of personal due ∪ assigned
# due** (plan §6, §4.6). These are gathered by TWO index-backed queries merged in
# Ruby — never a cross-table SQL UNION (which would defeat each source's index):
#   - personal due  → `Item.due` over the user's own items (suspended, due_at)
#   - assigned due   → `ReviewState.due` for the user (user_id, suspended, due_at)
# Each card carries an `origin` (personal vs. assigned + cohort) for the
# Designer's provenance display. A Subject/Lesson scope is the personal path only
# (you review *your* deck), so the assigned union applies to "all due" alone.
#
# The result is a **materialized, ordered list of item IDs computed once** (plus
# an origin map). The quiz loop walks that fixed list per card and never re-runs
# the due query mid-session (plan §6) — so grading an item can't reshuffle the
# queue underneath the learner.
#
# Pure-ish and DB-light: a couple of small queries, then ordering/interleaving in
# Ruby. No HTTP, no session state — the controller persists the materialized list.
class SessionBuilder
  DEFAULT_CAP = 20

  # A due card before ordering: its id, the lesson it belongs to (for
  # interleaving), its due_at (for most-overdue-first), and its origin tag.
  Card = Struct.new(:id, :lesson_id, :due_at, :origin, :cohort_id, keyword_init: true)

  Plan = Struct.new(:item_ids, :scope_label, :origins, keyword_init: true) do
    def size = item_ids.size
    def empty? = item_ids.empty?

    # origin (:personal / :assigned) for a given item id, for provenance display.
    def origin_for(item_id) = (origins || {})[item_id] || :personal
  end

  # user::  the learner whose due items make up the queue (plan §6, §8.3).
  #         Required — the queue is always the signed-in user's, never global.
  # scope:: a Subject, a Lesson, or nil (= "all due": personal ∪ assigned).
  def self.call(user:, scope: nil, now: Time.current, cap: DEFAULT_CAP)
    new(user: user, scope: scope, now: now, cap: cap).call
  end

  def initialize(user:, scope:, now:, cap:)
    @user  = user
    @scope = scope
    @now   = now
    @cap   = cap
  end

  def call
    cards = ordered_cards
    Plan.new(
      item_ids: cards.map(&:id),
      scope_label: scope_label,
      origins: cards.to_h { |c| [ c.id, c.origin ] }
    )
  end

  private

  # The due cards for this scope. A Subject/Lesson scope is the personal path
  # only; "all due" unions personal ∪ assigned (two index-backed queries).
  def due_cards
    case @scope
    when Lesson, Subject then personal_cards
    else                      personal_cards + assigned_cards
    end
  end

  # Personal due: the user's OWN due items (the unchanged solo path), via the
  # (suspended, due_at) index. Rooted at the user's items, so only their content.
  def personal_cards
    base_relation.due(@now).select(:id, :lesson_id, :due_at).map do |item|
      Card.new(id: item.id, lesson_id: item.lesson_id, due_at: item.due_at, origin: :personal)
    end
  end

  # Assigned due: the user's `review_states` that are due, via the
  # (user_id, suspended, due_at) index. Each row's item belongs to a teacher; we
  # carry the item's lesson_id (for interleaving) and tag origin :assigned. Only
  # items still LIVE-assigned to a cohort the learner is ACTIVELY enrolled in are
  # included (a withdrawn lesson / left cohort drops from the queue, plan §15).
  def assigned_cards
    states = @user.review_states.due(@now).pluck(:item_id, :due_at).to_h
    return [] if states.empty?

    # The lessons currently live-assigned to the learner's active cohorts.
    live_lesson_ids = Assignment.live
      .where(cohort_id: @user.enrollments.active.select(:cohort_id))
      .pluck(:lesson_id)
    return [] if live_lesson_ids.empty?

    Item.where(id: states.keys, lesson_id: live_lesson_ids)
        .pluck(:id, :lesson_id)
        .map do |item_id, lesson_id|
          Card.new(id: item_id, lesson_id: lesson_id, due_at: states[item_id], origin: :assigned)
        end
  end

  # Always rooted at the user's own items (plan §8.3). A Subject/Lesson scope is
  # already owner-fetched by the controller, but we still derive its items
  # through the relation; the "all due" branch spans only the user's lessons.
  def base_relation
    case @scope
    when Lesson  then @scope.items
    when Subject then Item.where(lesson_id: @scope.lesson_ids)
    else              @user.items
    end
  end

  # Most-overdue-first, then interleaved across lessons, then capped — and
  # frozen into a plain Array of Cards computed exactly once.
  def ordered_cards
    interleave(by_lesson_most_overdue_first).first(@cap)
  end

  # Group due cards by lesson, each group ordered most-overdue first (oldest
  # due_at leads; `id` breaks ties deterministically). Returns the groups
  # themselves ordered so the lesson holding the single most-overdue card is
  # dealt from first.
  def by_lesson_most_overdue_first
    groups = due_cards.group_by(&:lesson_id).values
    groups.each { |g| g.sort_by! { |c| [ c.due_at, c.id ] } }
    groups.sort_by { |g| [ g.first.due_at, g.first.id ] }
  end

  # Round-robin across the per-lesson queues: take the leading (most-overdue)
  # card from each lesson in turn, so consecutive cards come from different
  # lessons whenever possible (interleaving), while overall the most-overdue
  # cards still surface earliest.
  def interleave(groups)
    queues = groups.map(&:dup)
    woven  = []
    until queues.all?(&:empty?)
      queues.each { |q| woven << q.shift unless q.empty? }
    end
    woven
  end

  def scope_label
    case @scope
    when Lesson  then @scope.title
    when Subject then @scope.name
    else              "All due"
    end
  end
end
