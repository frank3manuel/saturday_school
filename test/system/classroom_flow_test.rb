require "application_system_test_case"

# Minimal, deterministic browser coverage of the classroom happy-path (plan §12).
# Per the development-hiccups lesson, this stays minimal and tests ONLY the UI
# wiring a browser is needed for: the student join-by-code form, and the teacher
# honest-progress page. The server-side authorization/assignment/queue flows are
# covered exhaustively (and without browser-timing flake) by the integration
# suite — ClassroomPrivacyTest, CohortsControllerTest, MembershipsControllerTest,
# SessionBuilderHybridTest, Cohorts::ProgressControllerTest. The quiz reveal loop
# itself is covered by QuizSessionLoopTest; we don't re-run it here.
class ClassroomFlowTest < ApplicationSystemTestCase
  test "student joins a class by code, and the teacher sees honest class progress" do
    teacher = users(:teacher)
    student = users(:owner) # a fresh student not yet enrolled

    # --- Teacher authors content and a cohort (set up directly) --------------
    subject = teacher.subjects.create!(name: "French")
    lesson  = subject.lessons.create!(title: "Greetings")
    lesson.items.create!(prompt: "Hello in French?", answer: "Bonjour")
    cohort = teacher.taught_cohorts.create!(name: "Period 2")
    Assignment.create!(cohort: cohort, lesson: lesson, assigner: teacher)

    # --- Student joins by code through the UI ---------------------------------
    sign_in_through_ui(student)
    visit memberships_path
    fill_in "Class code", with: cohort.join_code
    click_on "Join"
    assert_text "You've joined Period 2" # the enrollment landed (eager states too)
    assert_text "Period 2"               # now listed under "Classes you're in"

    # --- Teacher sees honest class progress (stacked distribution, no fake %) --
    using_session("teacher") do
      sign_in_through_ui(teacher)
      visit cohort_progress_path(cohort)
      assert_text "Class progress"
      assert_selector "div.dist"
      assert_no_text "% mastered"
    end
  end
end
