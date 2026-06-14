require "test_helper"

# Role-gate unit tests for account/role administration (plan §8.1, §12). Only an
# admin may list accounts, change roles, or delete accounts; a student/teacher
# cannot; and nobody may change/delete their own account through this surface.
class UserPolicyTest < ActiveSupport::TestCase
  setup do
    @admin   = users(:admin)
    @teacher = users(:teacher)
    @student = users(:owner)
    @target  = users(:student)
  end

  test "only admin may index/show accounts" do
    assert UserPolicy.new(@admin, User).index?
    assert UserPolicy.new(@admin, @target).show?

    refute UserPolicy.new(@teacher, User).index?
    refute UserPolicy.new(@student, User).index?
    refute UserPolicy.new(@teacher, @target).show?
  end

  test "only admin may change another user's role" do
    assert UserPolicy.new(@admin, @target).change_role?
    refute UserPolicy.new(@teacher, @target).change_role?
    refute UserPolicy.new(@student, @target).change_role?
  end

  test "admin may not change their own role" do
    refute UserPolicy.new(@admin, @admin).change_role?
  end

  test "only admin may delete another account; never their own" do
    assert UserPolicy.new(@admin, @target).destroy?
    refute UserPolicy.new(@admin, @admin).destroy?
    refute UserPolicy.new(@teacher, @target).destroy?
    refute UserPolicy.new(@student, @target).destroy?
  end

  test "admin account scope is every account; non-admin gets none" do
    assert_equal User.count, UserPolicy::Scope.new(@admin, User).resolve.count
    assert_equal 0, UserPolicy::Scope.new(@teacher, User).resolve.count
    assert_equal 0, UserPolicy::Scope.new(@student, User).resolve.count
  end
end
