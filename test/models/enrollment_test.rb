require "test_helper"

class EnrollmentTest < ActiveSupport::TestCase
  test "a student can't be enrolled twice in the same cohort" do
    dup = Enrollment.new(cohort: cohorts(:cohort_one), user: users(:student))
    assert_not dup.valid?
    assert_includes dup.errors[:user_id], "has already been taken"
  end

  test "leaving flips status and stamps ended_at, never deletes" do
    enrollment = enrollments(:student_in_cohort_one)
    assert_no_difference -> { Enrollment.count } do
      enrollment.leave!
    end
    assert enrollment.left?
    assert enrollment.ended_at.present?
  end

  test "removing flips status to removed" do
    enrollment = enrollments(:student_in_cohort_one)
    enrollment.remove!
    assert enrollment.removed?
  end

  test "leaving is idempotent and preserves the original ended_at" do
    enrollment = enrollments(:student_in_cohort_one)
    enrollment.leave!
    first_ended = enrollment.ended_at
    enrollment.leave!
    assert_equal first_ended, enrollment.reload.ended_at
  end

  test "rejoin reactivates an existing enrollment rather than duplicating" do
    enrollment = enrollments(:student_in_cohort_one)
    enrollment.leave!
    assert_no_difference -> { Enrollment.count } do
      enrollment.rejoin!
    end
    assert enrollment.active?
    assert_nil enrollment.ended_at
  end

  test "joined_at is stamped on create" do
    e = Enrollment.create!(cohort: cohorts(:other_cohort), user: users(:owner))
    assert e.joined_at.present?
  end
end
