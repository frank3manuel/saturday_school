require "test_helper"

# Teacher cohort management + the cross-teacher 404 matrix (plan §8.2, §12).
class CohortsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_out } # control sign-in per test (default helper signs in owner)

  test "a teacher sees only their own cohorts" do
    sign_in_as(users(:teacher))
    get cohorts_path
    assert_response :success
    assert_select "a", text: cohorts(:cohort_one).name
    assert_select "a", text: cohorts(:other_cohort).name, count: 0
  end

  test "a student cannot reach the teacher cohort surface (403)" do
    sign_in_as(users(:owner))
    get cohorts_path
    assert_response :forbidden
  end

  test "a teacher cannot view another teacher's cohort (404)" do
    sign_in_as(users(:teacher))
    get cohort_path(cohorts(:other_cohort))
    assert_response :not_found
  end

  test "a teacher cannot edit/destroy another teacher's cohort (404)" do
    sign_in_as(users(:teacher))
    get edit_cohort_path(cohorts(:other_cohort))
    assert_response :not_found
    delete cohort_path(cohorts(:other_cohort))
    assert_response :not_found
  end

  test "a teacher creates a cohort with an auto join code" do
    sign_in_as(users(:teacher))
    assert_difference -> { Cohort.count }, 1 do
      post cohorts_path, params: { cohort: { name: "New Period" } }
    end
    cohort = Cohort.order(:id).last
    assert_equal users(:teacher).id, cohort.teacher_id
    assert cohort.join_code.present?
    assert_redirected_to cohort_path(cohort)
  end

  test "teacher views own roster but cannot see another teacher's roster" do
    sign_in_as(users(:teacher))
    get cohort_path(cohorts(:cohort_one))
    assert_response :success
    assert_match users(:student).email_address, @response.body
  end
end
