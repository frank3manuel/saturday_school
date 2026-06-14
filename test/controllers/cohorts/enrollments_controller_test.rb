require "test_helper"

# Teacher roster management + cross-teacher 404 (plan §8.2, §12).
class Cohorts::EnrollmentsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_out }

  test "teacher enrolls a student by email and eagerly creates review_states" do
    sign_in_as(users(:teacher))
    assert_difference -> { Enrollment.active.count }, 1 do
      post cohort_enrollments_path(cohorts(:cohort_one)),
        params: { email_address: users(:owner).email_address }
    end
    assigned_item_ids = Item.where(lesson: lessons(:teacher_lesson)).pluck(:id)
    assert_equal assigned_item_ids.size,
      ReviewState.where(user: users(:owner), item_id: assigned_item_ids).count
  end

  test "enrolling an unknown / non-student email is rejected" do
    sign_in_as(users(:teacher))
    assert_no_difference -> { Enrollment.count } do
      post cohort_enrollments_path(cohorts(:cohort_one)),
        params: { email_address: "nobody@example.com" }
    end
  end

  test "a teacher cannot enroll into another teacher's cohort (404)" do
    sign_in_as(users(:teacher))
    post cohort_enrollments_path(cohorts(:other_cohort)),
      params: { email_address: users(:owner).email_address }
    assert_response :not_found
  end

  test "teacher removes a student (flips status, retains the row)" do
    sign_in_as(users(:teacher))
    enrollment = enrollments(:student_in_cohort_one)
    assert_no_difference -> { Enrollment.count } do
      delete cohort_enrollment_path(cohorts(:cohort_one), enrollment)
    end
    assert enrollment.reload.removed?
  end

  test "a student cannot manage a roster (403)" do
    sign_in_as(users(:owner))
    post cohort_enrollments_path(cohorts(:cohort_one)),
      params: { email_address: users(:student).email_address }
    assert_includes [ 403, 404 ], @response.status
  end
end
