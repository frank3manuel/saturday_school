# frozen_string_literal: true

# Role gate for assigning content (plan §8.1, §8.2, §11). The Pundit half of the
# DOUBLE-CHECKED assignment authorization (the Assignment model is the other
# half): `create?` requires that the acting teacher owns BOTH the cohort and the
# lesson. A forged lesson_id/cohort_id can't link another teacher's content
# because the gate fails before the row is built, and the model re-validates.
class AssignmentPolicy < ApplicationPolicy
  # record is the Assignment being created (with cohort + lesson set).
  def create?
    owns_cohort? && owns_lesson?
  end

  def destroy?
    # Withdraw/destroy: must own the cohort the assignment lives in.
    user&.staff? && record.cohort.teacher_id == user.id
  end

  private

  def owns_cohort?
    user&.staff? && record.cohort&.teacher_id == user.id
  end

  def owns_lesson?
    record.lesson&.subject&.user_id == user&.id
  end
end
