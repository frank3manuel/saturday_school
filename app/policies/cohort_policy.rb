# frozen_string_literal: true

# Role gate + scope for cohorts (plan §8.1, §8.2). Only staff (teacher/admin)
# may create/manage cohorts; a cohort is managed ONLY by the teacher who owns it.
# The Scope roots a teacher at their own `taught_cohorts`, so another teacher's
# cohort is structurally unreachable (plan §8.2 — privacy by the join graph, not
# a remembered WHERE). Admins get no cohorts here (they manage accounts, not the
# teaching surface) — Scope.none.
class CohortPolicy < ApplicationPolicy
  def index?
    user&.staff?
  end

  def create?
    user&.staff?
  end

  def show?
    owner?
  end

  def update?
    owner?
  end

  def destroy?
    owner?
  end

  # Roster/enroll/remove all require ownership of the cohort.
  def manage_roster?
    owner?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      # A teacher (or admin acting as a teacher) sees only the cohorts they own.
      # Anyone else gets nothing.
      if user&.staff?
        scope.where(teacher_id: user.id)
      else
        scope.none
      end
    end
  end

  private

  def owner?
    user&.staff? && record.teacher_id == user.id
  end
end
