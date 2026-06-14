require "test_helper"

class CohortTest < ActiveSupport::TestCase
  test "requires a name and a staff teacher" do
    cohort = Cohort.new(teacher: users(:teacher))
    assert_not cohort.valid?
    assert_includes cohort.errors[:name], "can't be blank"
  end

  test "teacher must be a teacher or admin, not a student" do
    cohort = Cohort.new(name: "Bad", teacher: users(:owner)) # owner is a student
    assert_not cohort.valid?
    assert_includes cohort.errors[:teacher], "must be a teacher or admin"
  end

  test "admin may also own a cohort" do
    cohort = Cohort.new(name: "Admin class", teacher: users(:admin))
    assert cohort.valid?
  end

  test "auto-generates an opaque join code on create" do
    cohort = Cohort.create!(name: "Auto", teacher: users(:teacher))
    assert_equal Cohort::JOIN_CODE_LENGTH, cohort.join_code.length
    assert_match(/\A[#{Cohort::JOIN_CODE_ALPHABET}]+\z/, cohort.join_code)
  end

  test "join codes are unique" do
    existing = cohorts(:cohort_one)
    dup = Cohort.new(name: "Dup", teacher: users(:teacher), join_code: existing.join_code)
    assert_not dup.valid?
    assert_includes dup.errors[:join_code], "has already been taken"
  end

  test "active_students excludes left/removed enrollments" do
    cohort = cohorts(:cohort_one)
    assert_includes cohort.active_students, users(:student)

    enrollments(:student_in_cohort_one).leave!
    assert_not_includes cohort.reload.active_students, users(:student)
  end

  test "deleting a teacher with live cohorts is blocked (restrict_with_error)" do
    teacher = users(:teacher)
    assert_not teacher.destroy
    assert teacher.errors.present?
    assert User.exists?(teacher.id)
  end
end
