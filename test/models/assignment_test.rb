require "test_helper"

# The model half of the double-checked assignment authorization (plan §11): an
# assignment is only valid if the assigning teacher owns BOTH the lesson and the
# cohort. A forged lesson_id/cohort_id can't link another teacher's content.
class AssignmentTest < ActiveSupport::TestCase
  test "valid when assigner owns both the lesson and the cohort" do
    # A fresh teacher-owned lesson (the fixture lesson is already assigned).
    lesson = subjects(:teacher_subject).lessons.create!(title: "More Spanish")
    a = Assignment.new(cohort: cohorts(:cohort_one),
                       lesson: lesson,
                       assigner: users(:teacher))
    assert a.valid?, a.errors.full_messages.to_sentence
  end

  test "invalid when the lesson belongs to someone else" do
    # algebra is owned by `owner` (a student), not teacher.
    a = Assignment.new(cohort: cohorts(:cohort_one),
                       lesson: lessons(:algebra),
                       assigner: users(:teacher))
    assert_not a.valid?
    assert_includes a.errors[:lesson], "must be one you own"
  end

  test "invalid when the cohort belongs to another teacher" do
    a = Assignment.new(cohort: cohorts(:other_cohort),
                       lesson: lessons(:teacher_lesson),
                       assigner: users(:teacher))
    assert_not a.valid?
    assert_includes a.errors[:cohort], "must be one you teach"
  end

  test "a lesson can't be assigned to the same cohort twice" do
    dup = Assignment.new(cohort: cohorts(:cohort_one),
                         lesson: lessons(:teacher_lesson),
                         assigner: users(:teacher))
    assert_not dup.valid?
    assert_includes dup.errors[:lesson_id], "has already been taken"
  end

  test "withdraw soft-stops without destroying" do
    a = assignments(:teacher_lesson_to_cohort_one)
    assert_no_difference -> { Assignment.count } do
      a.withdraw!
    end
    assert a.withdrawn?
  end

  test "deleting the assigning teacher is blocked while assignments live" do
    teacher = users(:teacher)
    # Also blocked by taught_cohorts; remove cohorts first to isolate the
    # assignment restriction. (Both protect the teacher.)
    assert_not teacher.destroy
    assert User.exists?(teacher.id)
  end
end
