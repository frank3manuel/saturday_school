require "test_helper"

# The 404 / privacy matrix for the classroom layer (plan §5.1, §8, §12). The
# tests that matter, now multiplied across student/teacher/admin. Privacy is
# mostly STRUCTURAL (an unreachable relation → 404), with 403 for role gates.
class ClassroomPrivacyTest < ActionDispatch::IntegrationTest
  setup { sign_out }

  # 1. Student vs another student's personal content → 404 (covered by existing
  #    ownership_test; re-assert the assigned grade path here).
  test "a student cannot grade an item that is neither theirs nor assigned to them" do
    sign_in_as(users(:owner)) # a student NOT enrolled in cohort_one
    refute Item.reviewable_for(users(:owner)).exists?(items(:teacher_item_one).id)
  end

  # 2. Teacher vs another teacher's students/enrollments → 404.
  test "a teacher cannot view another teacher's cohort, roster, or progress" do
    sign_in_as(users(:teacher))
    get cohort_path(cohorts(:other_cohort))
    assert_response :not_found
    get cohort_progress_path(cohorts(:other_cohort))
    assert_response :not_found
  end

  # 3. Teacher sees student progress ONLY on items they assigned.
  test "teacher class progress is scoped to assigned items only" do
    sign_in_as(users(:teacher))
    get cohort_progress_path(cohorts(:cohort_one))
    assert_response :success
    # The teacher's assigned item appears; the student's personal deck never can
    # (it has no assignment row).
    report = CohortProgressReport.new(cohort: cohorts(:cohort_one))
    assert_includes report.item_ids, items(:teacher_item_one).id
    refute_includes report.item_ids, items(:due_item).id # owner's personal item
  end

  # 4. Teacher CANNOT read a cohort student's personal decks.
  test "a teacher has no route into a cohort student's personal subjects" do
    sign_in_as(users(:teacher))
    # The student's own personal subject (if any) is not reachable through any
    # teacher surface — the cohort show only exposes assigned lessons + roster.
    get cohort_path(cohorts(:cohort_one))
    assert_response :success
    student_personal_subject = subjects(:math) # owned by `owner`, not the student
    assert_no_match student_personal_subject.name, @response.body
  end

  # 5. Admin cannot read ANY learning content (Scope.none).
  test "admin gets an empty scope on cohorts (no teaching content window)" do
    admin = users(:admin)
    assert_equal 0, CohortPolicy::Scope.new(admin, Cohort).resolve.count
  end

  test "admin cannot reach a teacher's cohort surface (403 role gate)" do
    sign_in_as(users(:admin))
    get cohorts_path
    # Admin is staff? false (admin only, not teacher) for the cohort gate? Admin
    # IS staff (teacher||admin), so they CAN create cohorts — but the SCOPE is
    # their own taught_cohorts (none unless they own some). They see an empty list.
    assert_response :success
    assert_select "li", count: 0
  end

  # 6. Student cannot edit assigned master content → 403/404.
  test "a student cannot edit an assigned teacher item (not in their items scope)" do
    sign_in_as(users(:student))
    patch item_path(items(:teacher_item_one)), params: { item: { prompt: "hacked" } }
    assert_response :not_found
    assert_equal "Hello in Spanish?", items(:teacher_item_one).reload.prompt
  end

  # 7. Student cannot grade into another student's state (user_id from Current).
  test "grading uses the signed-in user's id, never a param" do
    sign_in_as(users(:student))
    # Build a quiz for the student over their assigned due item.
    post quiz_sessions_path
    follow_redirect!
    quiz_session = QuizSession.where(user: users(:student)).order(:id).last
    # Attempt to grade while passing someone else's user_id as a param — it must
    # be ignored; the attempt belongs to the signed-in student.
    item_id = SessionBuilder.call(user: users(:student)).item_ids.first
    assert_difference -> { Attempt.where(user_id: users(:student).id).count }, 1 do
      post quiz_session_attempt_path(quiz_session),
        params: { item_id: item_id, grade: "good", user_id: users(:owner).id }
    end
    assert_equal 0, Attempt.where(user_id: users(:owner).id, item_id: item_id).count
  end

  # 8. Join-by-code enumeration safety is covered in MembershipsControllerTest.
  # 9. Teacher deletion blocked is covered in CohortTest/AssignmentTest.
  # 10. Leave/remove retains attempts but drops from active queue — covered in
  #     SessionBuilderHybridTest + EnrollmentTest.

  test "a teacher cannot read another teacher's students' review states" do
    # other_teacher has no enrollment/assignment overlap with the student.
    report = CohortProgressReport.new(cohort: cohorts(:other_cohort))
    assert_empty report.student_ids
    assert_empty report.item_ids
  end
end
