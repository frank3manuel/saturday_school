# frozen_string_literal: true

# Role gate for account/role administration (plan §8.1, §8.2). ONLY an admin may
# list accounts, change a role, or delete another account. This is a coarse role
# gate — the fine-grained "type-to-confirm + audit" friction lives in the
# controller (plan §11). Admins act on *accounts*, never on learning content.
class UserPolicy < ApplicationPolicy
  def index?
    user&.admin?
  end

  def show?
    user&.admin?
  end

  # Change a user's role. Admin only; a user may not change their own role (so an
  # admin can't accidentally lock themselves out of the admin surface).
  def change_role?
    user&.admin? && user != record
  end

  # Delete another account. Admin only, and never your own through this surface
  # (self-delete goes through AccountsController with its own confirmation).
  def destroy?
    user&.admin? && user != record
  end

  # The accounts an admin may manage: all of them. (This is the account axis, not
  # the learning-content axis — admins still get Scope.none on subjects/items/etc.)
  class Scope < ApplicationPolicy::Scope
    def resolve
      user&.admin? ? scope.all : scope.none
    end
  end
end
