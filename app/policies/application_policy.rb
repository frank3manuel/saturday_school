# frozen_string_literal: true

# Base Pundit policy (plan §8.2). Pundit is used **thinly**: only for the new
# cross-user role gates (cohort/assignment/admin actions) and for the doubly-
# scoped teacher/admin Scope classes. Personal-content CRUD is NOT routed through
# Pundit — it stays on `current_user.subjects.find(...)` association scoping.
#
# Fail closed: every action defaults to false and the base Scope returns nothing.
# A concrete policy must explicitly grant a verb or widen the scope.
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user   = user
    @record = record
  end

  def index?   = false
  def show?    = false
  def create?  = false
  def new?     = create?
  def update?  = false
  def edit?    = update?
  def destroy? = false

  # The base Scope returns nothing (fail closed). This is what enforces "admin
  # sees no learning content" structurally (plan §8.2, D-privacy): unless a
  # content policy's Scope explicitly grants rows for a role, that role gets the
  # empty set by the *absence* of a grant, not by remembering a WHERE.
  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user  = user
      @scope = scope
    end

    def resolve
      scope.none
    end

    private

    attr_reader :scope_relation
  end
end
