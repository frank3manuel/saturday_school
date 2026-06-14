require "test_helper"

# Admin account/role management (plan §8.1, §11, §12). Admin can change roles and
# delete accounts (both audited + type-to-confirm); non-admins are forbidden.
class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin   = users(:admin)
    @target  = users(:student)
    sign_out # default helper signs in as owner; we control sign-in per test
  end

  test "admin can list accounts" do
    sign_in_as(@admin)
    get admin_users_path
    assert_response :success
    assert_select "table.admin__users"
  end

  test "non-admin cannot reach the admin surface (403)" do
    sign_in_as(users(:owner)) # a student
    get admin_users_path
    assert_response :forbidden

    sign_out
    sign_in_as(users(:teacher))
    get admin_users_path
    assert_response :forbidden
  end

  test "admin changes a role with confirmation and it is audited" do
    sign_in_as(@admin)
    assert_difference -> { AuditEvent.where(action: AuditEvent::ROLE_CHANGED).count }, 1 do
      patch admin_user_path(@target), params: { role: "teacher", confirm: @target.email_address }
    end
    assert_redirected_to admin_user_path(@target)
    assert_equal "teacher", @target.reload.role

    event = AuditEvent.where(action: AuditEvent::ROLE_CHANGED).order(:id).last
    assert_equal @admin, event.actor
    assert_equal @target, event.target_user
    assert_equal "student", event.detail_hash["from"]
    assert_equal "teacher", event.detail_hash["to"]
  end

  test "role change without exact email confirmation is rejected and not audited" do
    sign_in_as(@admin)
    assert_no_difference -> { AuditEvent.count } do
      patch admin_user_path(@target), params: { role: "teacher", confirm: "wrong@example.com" }
    end
    assert_equal "student", @target.reload.role
  end

  test "non-admin cannot change a role (403, no change, no audit)" do
    sign_in_as(users(:owner))
    assert_no_difference -> { AuditEvent.count } do
      patch admin_user_path(@target), params: { role: "teacher", confirm: @target.email_address }
    end
    assert_response :forbidden
    assert_equal "student", @target.reload.role
  end

  test "admin deletes an account with confirmation and it is audited (audit survives)" do
    sign_in_as(@admin)
    target_email = @target.email_address
    assert_difference -> { User.count }, -1 do
      assert_difference -> { AuditEvent.where(action: AuditEvent::ACCOUNT_DELETED).count }, 1 do
        delete admin_user_path(@target), params: { confirm: target_email }
      end
    end
    assert_redirected_to admin_users_path

    event = AuditEvent.where(action: AuditEvent::ACCOUNT_DELETED).order(:id).last
    assert_nil event.target_user, "FK nullifies on delete"
    assert_equal target_email, event.target_email, "denormalized email survives the cascade"
  end

  test "delete without exact confirmation is rejected" do
    sign_in_as(@admin)
    assert_no_difference -> { User.count } do
      delete admin_user_path(@target), params: { confirm: "nope" }
    end
  end

  test "admin cannot delete their own account through this surface (403)" do
    sign_in_as(@admin)
    delete admin_user_path(@admin), params: { confirm: @admin.email_address }
    assert_response :forbidden
    assert User.exists?(@admin.id)
  end
end
