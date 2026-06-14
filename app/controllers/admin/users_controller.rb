# Admin account & role management (plan §8.1, §11). Admins manage *accounts* —
# they assign/change roles and deactivate/delete accounts. They get NO window
# into learning content (that is enforced structurally by the content Scopes
# returning none for admins, plan §8.2).
#
# Every action is role-gated by UserPolicy (admin only). Destructive actions
# (role change, delete) require type-to-confirm friction AND write an append-only
# AuditEvent (plan §11). `users.role` is server-authoritative — set here from an
# admin action, never mass-assignable from a form param map (plan §11).
class Admin::UsersController < ApplicationController
  # Coarse role gate FIRST (plan §8.2: role gate THEN scope, fail closed). This
  # makes the whole admin surface a clean 403 for non-admins, before any record
  # lookup. The per-record gates below add the "not yourself" rules.
  before_action :require_admin
  before_action :set_user, only: %i[show update destroy]

  ROLES = %w[student teacher admin].freeze

  def index
    # Admin's account axis — every account, ordered for a stable list.
    @users = policy_scope(User).order(:email_address)
  end

  def show
    authorize @user, :show?
    @audit_events = AuditEvent.where(target_user: @user).recent.limit(50)
  end

  # Change a single user's role (server-authoritative). Type-to-confirm friction:
  # the admin must type the target's email to confirm. Audited.
  def update
    authorize @user, :change_role?

    new_role = params[:role].to_s
    unless ROLES.include?(new_role)
      redirect_to admin_user_path(@user), alert: "Unknown role." and return
    end

    unless confirmed?
      redirect_to admin_user_path(@user),
        alert: "Type the user's email exactly to confirm the role change." and return
    end

    old_role = @user.role
    if old_role == new_role
      redirect_to admin_user_path(@user), notice: "No change — already #{new_role}." and return
    end

    ActiveRecord::Base.transaction do
      @user.update!(role: new_role)
      AuditEvent.record!(
        action: AuditEvent::ROLE_CHANGED,
        actor: current_user,
        target_user: @user,
        details: { from: old_role, to: new_role }
      )
    end
    redirect_to admin_user_path(@user), notice: "Role changed from #{old_role} to #{new_role}."
  end

  # Delete an account (type-to-confirm + audit). The audit row survives the
  # deletion (target_user FK nullifies; target_email is denormalized).
  def destroy
    authorize @user, :destroy?

    unless confirmed?
      redirect_to admin_user_path(@user),
        alert: "Type the user's email exactly to confirm deletion." and return
    end

    # Record BEFORE destroying so the audit row captures actor/target while both
    # still exist; the AuditEvent itself persists past the cascade.
    AuditEvent.record!(
      action: AuditEvent::ACCOUNT_DELETED,
      actor: current_user,
      target_user: @user,
      details: { role: @user.role }
    )

    if @user.destroy
      redirect_to admin_users_path, notice: "Account #{@user.email_address} deleted."
    else
      # A teacher with live cohorts is blocked by restrict_with_error (plan §15
      # D-leave): show the friendly reason, don't 500.
      redirect_to admin_user_path(@user),
        alert: @user.errors.full_messages.to_sentence.presence ||
               "This account can't be deleted while it still owns cohorts or assignments."
    end
  end

  private

  # The coarse admin role gate for the whole surface (UserPolicy#index?).
  def require_admin
    authorize User, :index?
  end

  def set_user
    # Admin's account scope is every account (UserPolicy::Scope), so find within it.
    @user = policy_scope(User).find(params[:id])
  end

  # Type-to-confirm: the admin must type the target's email exactly (plan §11).
  def confirmed?
    params[:confirm].to_s.strip.casecmp?(@user.email_address)
  end
end
