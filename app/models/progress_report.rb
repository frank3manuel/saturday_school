# frozen_string_literal: true

# Computes the honest Progress dashboard data (plan §9, §3) on demand — no jobs,
# index-backed, and N+1-free across subjects → items.
#
# It runs a small fixed number of queries regardless of how many subjects/items
# exist:
#   1. the active items (id, lesson_id, subject name, due_at)
#   2. one grouped query: max survived gap per item from the correct-attempt log
#   3. durability counts derived from the same attempt aggregation
#
# Everything else is folded in Ruby. The stage mapping is delegated to
# MasteryStage so the dashboard agrees with the Library chip and quiz copy.
#
# Scoped to a single user (plan §8.3): `active_items` is rooted at the user's
# own items chain, and the attempt aggregations are filtered to that same item
# set, so one learner's dashboard never reflects another's records.
class ProgressReport
  # A single stacked-bar row: a name plus a stage → count map (zeros filled in).
  Distribution = Struct.new(:name, :counts, :total, keyword_init: true) do
    # The honest headline (plan §3): items that have truly stuck (Maturing +
    # Durable), which by construction took real elapsed time. Never a "% only"
    # vanity figure — we expose the count and let the view frame the share.
    def truly_learned
      MasteryStage::TRULY_LEARNED.sum { |stage| counts.fetch(stage, 0) }
    end
  end

  # One day in the due-forecast calendar.
  ForecastDay = Struct.new(:date, :count, keyword_init: true)

  def initialize(user:, now: Time.current, forecast_days: 14)
    @user = user
    @now = now
    @forecast_days = forecast_days
  end

  # Stage distribution across ALL active items.
  def overall_distribution
    Distribution.new(name: "All items", counts: tally_stages(stage_by_item.values),
                     total: stage_by_item.size)
  end

  # One Distribution per subject (only subjects that have active items), so the
  # view can render a stacked bar per subject. Built from already-loaded data —
  # no extra query per subject.
  def distributions_by_subject
    grouped = active_items.group_by { |row| row.subject_name }
    grouped.map do |subject_name, rows|
      stages = rows.map { |row| stage_by_item.fetch(row.id) }
      Distribution.new(name: subject_name, counts: tally_stages(stages), total: rows.size)
    end.sort_by { |dist| -dist.truly_learned }
  end

  # Upcoming reviews per day for the next `forecast_days` days, computed from
  # due_at (index-backed). Days with no due items are included (count 0) so the
  # calendar grid is contiguous. Anything already overdue is surfaced separately.
  def forecast
    today = @now.to_date
    counts = Hash.new(0)
    active_items.each do |row|
      next if row.due_at.nil?

      date = row.due_at.to_date
      counts[date] += 1 if date >= today
    end
    (0...@forecast_days).map do |offset|
      date = today + offset
      ForecastDay.new(date: date, count: counts[date])
    end
  end

  # Active items already past due (the calendar's "today" bucket would otherwise
  # hide the backlog). Honest: shows the real outstanding count.
  def overdue_count
    today = @now.to_date
    active_items.count { |row| row.due_at.present? && row.due_at.to_date < today }
  end

  # Honest durability counts (plan §3): how many *distinct items* have been
  # recalled across a gap of at least N days. Derived from the append-only
  # attempt log (the source of truth for "survived an N-day gap"). These nest
  # (every ≥60d item is also ≥7d and ≥1d).
  def durability
    survived = survived_gap_by_item
    {
      day:   survived.count { |_id, days| days >= MasteryStage::YOUNG_DAYS },
      week:  survived.count { |_id, days| days >= MasteryStage::MATURING_DAYS },
      month: survived.count { |_id, days| days >= MasteryStage::DURABLE_DAYS }
    }
  end

  # Total active items, for honest framing of the truly-learned share.
  def total_items
    active_items.size
  end

  # Consistency streak: the number of consecutive days (ending today or
  # yesterday) on which at least one review happened. This is "showing up",
  # NOT mastery — the view presents it in its own clearly-labelled area so it's
  # never confused for learning progress (plan §3). Derived from attempt dates.
  def consistency_streak
    days = Attempt.where(user_id: @user.id, item_id: active_items.map(&:id))
                  .distinct
                  .pluck(:reviewed_at)
                  .map { |time| time.to_date }
                  .uniq
                  .to_set
    today = @now.to_date
    # A streak is "alive" if reviewed today or yesterday (don't break it before
    # the day is over).
    return 0 unless days.include?(today) || days.include?(today - 1)

    cursor = days.include?(today) ? today : today - 1
    streak = 0
    while days.include?(cursor)
      streak += 1
      cursor -= 1
    end
    streak
  end

  private

  ItemRow = Struct.new(:id, :due_at, :subject_name, keyword_init: true)

  # Active items with just the columns the dashboard needs, plus their subject
  # name joined in (one query, no per-item subject load).
  def active_items
    @active_items ||=
      @user.items.active
          .joins(lesson: :subject)
          .pluck(:"items.id", :"items.due_at", :"subjects.name")
          .map { |id, due_at, subject_name| ItemRow.new(id: id, due_at: due_at, subject_name: subject_name) }
  end

  # item_id → longest survived gap (days), from ONE grouped query over the
  # correct-attempt log. Items with no correct attempt are absent (→ stage New).
  # Scoped to THIS user's attempts (plan §8.3): an owner's items can also carry
  # assigned students' attempts (same item_id, different user_id), so without the
  # user_id filter a student's recall would leak into the owner's personal stage.
  def survived_gap_by_item
    @survived_gap_by_item ||=
      Attempt.where(user_id: @user.id, item_id: active_items.map(&:id), correct: true)
             .group(:item_id)
             .maximum(:interval_before)
             .transform_values(&:to_i)
  end

  # item_id → display stage symbol, for every active item.
  def stage_by_item
    @stage_by_item ||= begin
      survived = survived_gap_by_item
      active_items.index_with do |row|
        MasteryStage.from(recalled: survived.key?(row.id), survived_days: survived[row.id])
      end.transform_keys(&:id)
    end
  end

  # Count a list of stage symbols into a {stage => count} map with every stage
  # present (zeros included) so bars render all five segments/labels.
  def tally_stages(stages)
    base = MasteryStage::STAGES.index_with { 0 }
    stages.each { |stage| base[stage] += 1 }
    base
  end
end
