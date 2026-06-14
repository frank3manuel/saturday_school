require "test_helper"

# Honest teacher class-aggregate progress (plan §3, §9, M6d). Stacked stage
# distribution only — NEVER a fabricated "% mastered". Strictly scoped, no N+1.
class Cohorts::ProgressControllerTest < ActionDispatch::IntegrationTest
  setup { sign_out }

  test "renders the honest stage distribution with no '% mastered' headline" do
    sign_in_as(users(:teacher))
    get cohort_progress_path(cohorts(:cohort_one))
    assert_response :success
    # No fabricated mastery percentage anywhere (plan §3). The prose explains the
    # ABSENCE of a "percent mastered" figure, so we only forbid an actual N%
    # mastered claim (a digit immediately followed by "% mastered").
    refute_match(/\d+\s*% mastered/i, @response.body)
    # The honest stacked-distribution scaffolding is present.
    assert_select "div.dist"
  end

  test "a non-teacher cannot view class progress (403/404)" do
    sign_in_as(users(:owner)) # student
    get cohort_progress_path(cohorts(:cohort_one))
    assert_includes [ 403, 404 ], @response.status
  end

  test "a teacher cannot view another teacher's class progress (404)" do
    sign_in_as(users(:teacher))
    get cohort_progress_path(cohorts(:other_cohort))
    assert_response :not_found
  end

  test "the report is scoped to assigned items × active students only" do
    report = CohortProgressReport.new(cohort: cohorts(:cohort_one))
    assert_equal [ users(:student).id ], report.student_ids
    assert_includes report.item_ids, items(:teacher_item_one).id
    refute_includes report.item_ids, items(:due_item).id # a personal deck item
  end

  test "no N+1: the report uses a bounded number of queries across students/items" do
    report = CohortProgressReport.new(cohort: cohorts(:cohort_one))
    # Force the survived-gap aggregation, then assert building all three views
    # issues NO further attempt queries (the grouped query is memoized).
    report.overall
    assert_no_queries_for_attempts do
      report.by_item
      report.by_student
      report.overall
    end
  end

  private

  # Assert the block runs without firing any `attempts` SELECTs (the grouped
  # survived-gap query is computed once and reused — no per-cell query).
  def assert_no_queries_for_attempts
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if payload[:sql] =~ /FROM\s+"attempts"/i }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    assert_empty queries, "expected no per-cell attempts queries, got #{queries.size}"
  end
end
