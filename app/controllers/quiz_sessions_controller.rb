# The spaced-review loop (plan §6, §9, §10).
#
# `create` builds the session plan ONCE via SessionBuilder and stashes the
# materialized ordered item IDs in the Rails session; every subsequent request
# walks that fixed list (we never re-run the due query mid-session, plan §6).
#
# The "cursor" into the list is derived from the append-only attempt log:
# `reviewed_count` = how many distinct items have been graded. So the current
# card is `item_ids[reviewed_count]`, grading advances it, and **undo** (which
# deletes the last attempt) rewinds it — no separate position to keep in sync.
class QuizSessionsController < ApplicationController
  before_action :set_quiz_session, only: %i[show summary finish]

  # Start a review for a scope (all due / subject / lesson).
  def create
    scope = resolve_scope
    plan  = SessionBuilder.call(user: current_user, scope: scope)

    if plan.empty?
      redirect_to root_path, notice: "Nothing due right now."
      return
    end

    quiz_session = current_user.quiz_sessions.create!(
      subject: scope.is_a?(Subject) ? scope : nil,
      started_at: Time.current,
      planned_count: plan.size
    )
    store_plan(quiz_session, plan)

    redirect_to quiz_session_path(quiz_session)
  end

  # The current card — or the summary once every planned item is done.
  def show
    @item_ids = plan_ids(@quiz_session)
    @cursor   = @quiz_session.reviewed_count

    if @cursor >= @item_ids.length
      redirect_to summary_quiz_session_path(@quiz_session)
      return
    end

    # Reviewable = personal ∪ live-assigned (plan §4.6). The card's projected
    # intervals come from the LEARNER's state home, not the item's inline columns,
    # so an assigned student sees their own schedule.
    @item            = Item.reviewable_for(current_user).find(@item_ids[@cursor])
    @home            = @item.srs_home_for(current_user)
    @origin          = origin_for(@quiz_session, @item.id)
    @position        = @cursor + 1
    @total           = @item_ids.length
    @can_undo        = @cursor.positive?
    @good_interval   = projected_days(@home, correct: true)
    @hard_interval   = projected_days(@home, correct: true)
    @missed_interval = projected_days(@home, correct: false)
  end

  # End the session early, without penalty (plan §9) → summary.
  def finish
    @quiz_session.complete!
    redirect_to summary_quiz_session_path(@quiz_session)
  end

  # "N/M complete" wrap-up.
  def summary
    @reviewed = @quiz_session.reviewed_count
    @planned  = @quiz_session.planned_count.to_i
    @quiz_session.complete! if @reviewed >= @planned
    @attempts = @quiz_session.attempts.includes(item: :lesson).order(:id)
    # Honest display stage per reviewed item (plan §3), computed in bulk to
    # avoid an N+1 over the summary list.
    items   = @attempts.map(&:item).uniq
    @stages = MasteryStage.for_items(items)
  end

  private

  # Owner-scoped (plan §8.3): another user's session 404s.
  def set_quiz_session
    @quiz_session = current_user.quiz_sessions.find(params[:id])
  end

  # Scope from params: a lesson, a subject, or nil ("all due"). Fetched through
  # the current user so a forged id for someone else's content 404s.
  def resolve_scope
    if params[:lesson_id].present?
      current_user.lessons.find(params[:lesson_id])
    elsif params[:subject_id].present?
      current_user.subjects.find(params[:subject_id])
    end
  end

  # `home` is the learner's state-bearing record (Item or ReviewState) — both
  # expose `box`, so the projected next interval reflects THIS learner's schedule.
  def projected_days(home, correct:)
    Srs::Scheduler.projected_interval_days(level: home.box, correct: correct)
  end

  # --- plan stash (materialize once, walk a fixed list) --------------------

  def store_plan(quiz_session, plan)
    session[plan_key(quiz_session)] = plan.item_ids
    # Origin tags ride along for the Designer's provenance display (plan §6):
    # personal vs. assigned. Stored separately so the existing array-shaped plan
    # key stays unchanged.
    session[origins_key(quiz_session)] = plan.origins.transform_keys(&:to_s)
  end

  def plan_ids(quiz_session)
    session[plan_key(quiz_session)] || []
  end

  # The provenance tag (:personal / :assigned) for an item in this session.
  def origin_for(quiz_session, item_id)
    (session[origins_key(quiz_session)] || {})[item_id.to_s]&.to_sym || :personal
  end

  def plan_key(quiz_session)
    "quiz_plan_#{quiz_session.id}"
  end

  def origins_key(quiz_session)
    "quiz_origins_#{quiz_session.id}"
  end
end
