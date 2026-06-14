require "test_helper"

# The on-demand Progress dashboard computation (plan §9, §3). Builds a small
# controlled dataset rather than leaning on shared fixtures (other suites assert
# exact due/plan counts). Uses travel_to for elapsed-time cases.
class ProgressReportTest < ActiveSupport::TestCase
  setup do
    # Start from a clean slate: ProgressReport aggregates over the user's items,
    # so fixture items owned by the same user would otherwise leak into the
    # tallies. Each test then builds exactly the data it asserts, owned by @user.
    Attempt.delete_all
    Item.delete_all
    @user    = users(:owner)
    @subject = @user.subjects.create!(name: "Geo")
    @lesson  = @subject.lessons.create!(title: "Capitals")
  end

  test "overall distribution tallies every stage with zeros filled" do
    make_item(survived: nil)          # New
    make_item(survived: 0)            # Learning
    make_item(survived: 3)            # Young
    make_item(survived: 7)            # Maturing
    make_item(survived: 60)           # Durable

    dist = report.overall_distribution
    assert_equal MasteryStage::STAGES.to_set, dist.counts.keys.to_set
    assert_equal 1, dist.counts[:new]
    assert_equal 1, dist.counts[:learning]
    assert_equal 1, dist.counts[:young]
    assert_equal 1, dist.counts[:maturing]
    assert_equal 1, dist.counts[:durable]
    assert_equal 5, dist.total
  end

  test "truly_learned counts only Maturing + Durable" do
    make_item(survived: 3)   # young, doesn't count
    make_item(survived: 7)   # maturing
    make_item(survived: 90)  # durable
    assert_equal 2, report.overall_distribution.truly_learned
  end

  test "distributions_by_subject excludes other subjects' items and sorts by truly_learned" do
    make_item(survived: 60) # this subject: durable

    other = @user.subjects.create!(name: "Hist")
    lesson = other.lessons.create!(title: "Wars")
    make_item(survived: nil, lesson: lesson) # other subject: new only

    dists = report.distributions_by_subject
    names = dists.map(&:name)
    assert_includes names, "Geo"
    assert_includes names, "Hist"
    # Geo (1 truly-learned) sorts before Hist (0).
    assert_equal "Geo", dists.first.name
  end

  test "durability counts nest: ≥1d ⊇ ≥1wk ⊇ ≥60d" do
    make_item(survived: 1)   # day only
    make_item(survived: 7)   # day + week
    make_item(survived: 60)  # day + week + month
    d = report.durability
    assert_equal 3, d[:day]
    assert_equal 2, d[:week]
    assert_equal 1, d[:month]
  end

  test "durability ignores items recalled only across a sub-1-day gap" do
    make_item(survived: 0)
    assert_equal({ day: 0, week: 0, month: 0 }, report.durability)
  end

  test "forecast buckets future due items by day and is contiguous" do
    travel_to Time.zone.local(2026, 6, 1, 9, 0, 0) do
      due_at_item(2.days.from_now)
      due_at_item(2.days.from_now)
      due_at_item(5.days.from_now)

      forecast = report.forecast
      assert_equal 14, forecast.size, "two-week contiguous grid"
      assert_equal (0...14).map { |i| Date.new(2026, 6, 1) + i }, forecast.map(&:date)
      assert_equal 2, forecast[2].count
      assert_equal 0, forecast[3].count
      assert_equal 1, forecast[5].count
    end
  end

  test "overdue_count counts active items past due, separate from the forecast" do
    travel_to Time.zone.local(2026, 6, 1, 9, 0, 0) do
      due_at_item(2.days.ago)
      due_at_item(1.hour.from_now) # later today, not overdue by date
      assert_equal 1, report.overdue_count
    end
  end

  test "consistency_streak counts consecutive review days ending today/yesterday" do
    travel_to Time.zone.local(2026, 6, 10, 12, 0, 0) do
      item = make_item(survived: nil)
      [ 0, 1, 2, 4 ].each do |days_ago|
        item.attempts.create!(user: @user, correct: true, grade: :good,
                              reviewed_at: days_ago.days.ago,
                              interval_before: 0, interval_after: 0)
      end
      # Today, -1, -2 are unbroken (3); -4 is past the gap at -3.
      assert_equal 3, report.consistency_streak
    end
  end

  test "consistency_streak is zero when the last review was over a day ago" do
    travel_to Time.zone.local(2026, 6, 10, 12, 0, 0) do
      item = make_item(survived: nil)
      item.attempts.create!(user: @user, correct: true, grade: :good, reviewed_at: 3.days.ago,
                            interval_before: 0, interval_after: 0)
      assert_equal 0, report.consistency_streak
    end
  end

  # Regression guard (plan §8.3): ProgressReport is single-user-scoped, but a
  # teacher's item can carry assigned students' attempts (same item_id, different
  # user_id) once it's shared via a cohort (M6). The durability aggregation and
  # the consistency streak must filter by user_id so a student's recall never
  # leaks into the owner's personal numbers. Both assertions below were chosen so
  # the old item_id-only query would visibly change the result.
  test "durability and streak ignore another user's attempts on a shared item" do
    travel_to Time.zone.local(2026, 6, 10, 12, 0, 0) do
      teacher = users(:teacher)
      subject = teacher.subjects.create!(name: "Algebra")
      lesson  = subject.lessons.create!(title: "Linear")
      item    = lesson.items.create!(prompt: "2x=4", answer: "x=2")

      # Teacher's own recall: survived a 7-day gap (Maturing, counts toward week
      # but NOT month), reviewed only today (streak of 1).
      item.attempts.create!(user: teacher, correct: true, grade: :good,
                            reviewed_at: Time.current,
                            interval_before: 7, interval_after: 7)

      # Student (enrolled, lesson assigned) accumulates attempts on the SAME item.
      # Stronger recall: survived a 90-day gap (Durable) and reviewed on three
      # consecutive days. If these leaked, the teacher's month durability would
      # flip 0→1 and the streak would jump 1→3.
      student = users(:student)
      [ 0, 1, 2 ].each do |days_ago|
        item.attempts.create!(user: student, correct: true, grade: :good,
                              reviewed_at: days_ago.days.ago,
                              interval_before: 90, interval_after: 90)
      end

      teacher_report = ProgressReport.new(user: teacher)
      # active_items is rooted at the teacher's OWNED items, so the shared item is
      # in scope; only the attempt aggregations need the user_id guard.
      assert_equal({ day: 1, week: 1, month: 0 }, teacher_report.durability,
                   "student's 90-day gap on the shared item must not count for the teacher")
      assert_equal 1, teacher_report.consistency_streak,
                   "student's review days must not extend the teacher's streak"
    end
  end

  test "runs a bounded number of queries regardless of item count (no N+1)" do
    5.times { make_item(survived: 7) }
    r = report
    # Force all the work, then assert it was cheap: active items, the grouped
    # survived-gap query, and the streak query — a small constant.
    assert_queries_at_most(4) do
      r.overall_distribution
      r.distributions_by_subject
      r.durability
      r.forecast
      r.overdue_count
      r.consistency_streak
    end
  end

  private

  def report
    ProgressReport.new(user: @user)
  end

  # Create an item and (optionally) a single correct attempt that establishes
  # the longest gap it survived. `survived: nil` → never correctly recalled.
  def make_item(survived:, lesson: @lesson)
    item = lesson.items.create!(prompt: "Q#{SecureRandom.hex(4)}", answer: "A")
    unless survived.nil?
      item.attempts.create!(user: @user, correct: true, grade: :good, reviewed_at: Time.current,
                            interval_before: survived, interval_after: survived)
    end
    item
  end

  def due_at_item(due_at)
    @lesson.items.create!(prompt: "D#{SecureRandom.hex(4)}", answer: "A",
                          state: :review, due_at: due_at, interval_days: 1, box: 1)
  end

  # Minitest's assert_queries isn't available in plain ActiveSupport::TestCase
  # here, so count via a subscription.
  def assert_queries_at_most(max)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:sql] =~ /^\s*(BEGIN|COMMIT|RELEASE|SAVEPOINT|ROLLBACK)/i }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    assert count <= max, "expected ≤ #{max} queries, ran #{count}"
  end
end
