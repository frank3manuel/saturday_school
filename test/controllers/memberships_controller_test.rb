require "test_helper"

# Student join-by-code / my classes / leave (plan §8.1, §12). Join-by-code is
# enumeration-safe: the failure message is identical regardless of why it failed.
class MembershipsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_out }

  test "a valid code enrolls the student and creates review_states eagerly" do
    sign_in_as(users(:owner)) # a student not yet in cohort_one
    assert_difference -> { Enrollment.active.count }, 1 do
      post memberships_path, params: { join_code: cohorts(:cohort_one).join_code }
    end
    # Eager review_states: one per item in the cohort's live assignments.
    assigned_item_ids = Item.where(lesson: lessons(:teacher_lesson)).pluck(:id)
    created = ReviewState.where(user: users(:owner), item_id: assigned_item_ids).count
    assert_equal assigned_item_ids.size, created
    assert_redirected_to memberships_path
  end

  test "an invalid code shows a generic enumeration-safe failure" do
    sign_in_as(users(:owner))
    assert_no_difference -> { Enrollment.count } do
      post memberships_path, params: { join_code: "ZZZZZZZZZZ" }
    end
    follow_redirect!
    assert_match(/match an open class/, @response.body)
  end

  test "an archived class fails with the SAME generic message (enumeration-safe)" do
    cohorts(:cohort_one).update!(archived_at: Time.current)
    sign_in_as(users(:owner))
    post memberships_path, params: { join_code: cohorts(:cohort_one).join_code }
    follow_redirect!
    assert_match(/match an open class/, @response.body)
  end

  test "rejoining after leaving reactivates the same enrollment" do
    enrollment = enrollments(:student_in_cohort_one)
    enrollment.leave!
    sign_in_as(users(:student))
    assert_no_difference -> { Enrollment.count } do
      post memberships_path, params: { join_code: cohorts(:cohort_one).join_code }
    end
    assert enrollment.reload.active?
  end

  test "leaving flips status and retains the enrollment row (and attempts)" do
    sign_in_as(users(:student))
    enrollment = enrollments(:student_in_cohort_one)
    assert_no_difference -> { Enrollment.count } do
      delete membership_path(enrollment)
    end
    assert enrollment.reload.left?
  end

  test "a student cannot leave someone else's enrollment (404)" do
    sign_in_as(users(:owner)) # not the student in cohort_one
    delete membership_path(enrollments(:student_in_cohort_one))
    assert_response :not_found
  end
end
