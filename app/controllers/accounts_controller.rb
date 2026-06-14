# Account / settings (plan §9, A6). The "your data is yours" surface: change
# email (re-verify required), change password (rotate sessions), export all
# personal data, and delete the account (type-to-confirm, full cascade).
#
# Email and password changes both require the CURRENT password (plan §11). A
# password change destroys every OTHER session (session fixation defense) while
# keeping the current one alive. Changing the email clears `verified_at` so the
# new address re-verifies (plan §4.4, D-verify).
class AccountsController < ApplicationController
  def show
    @user = current_user
  end

  def update
    @user = current_user

    unless @user.authenticate(params[:current_password].to_s)
      @user.errors.add(:current_password, "is incorrect")
      return render :show, status: :unprocessable_entity
    end

    if params[:commit_password].present?
      update_password
    else
      update_email
    end
  end

  # Export everything the user owns as a single JSON document (plan §9, D-data).
  def export
    send_data AccountExport.new(current_user).to_json,
              filename: "saturday-school-#{current_user.id}-#{Date.current.iso8601}.json",
              type: "application/json",
              disposition: "attachment"
  end

  # Type-to-confirm delete (plan §9, §11). Cascades via dependent: :destroy + DB
  # foreign-key cascade, so all of the user's content goes with the account.
  def destroy
    @user = current_user

    unless params[:confirm].to_s.strip.casecmp?(current_user.email_address)
      @user.errors.add(:base, "Type your email address exactly to confirm deletion.")
      return render :show, status: :unprocessable_entity
    end

    user = current_user
    terminate_session
    user.destroy!
    redirect_to new_session_path, notice: "Your account and all its data have been deleted."
  end

  private

  def update_email
    if @user.update(email_address: params[:email_address])
      # A new address is unverified until re-confirmed (plan §4.4).
      @user.update_column(:verified_at, nil)
      redirect_to account_path, notice: "Email updated. Please verify your new address."
    else
      render :show, status: :unprocessable_entity
    end
  end

  def update_password
    if @user.update(password_params)
      # Rotate: keep this session, drop every other one (plan §11).
      current_user.sessions.where.not(id: Current.session.id).destroy_all
      redirect_to account_path, notice: "Password updated. You've been signed out on other devices."
    else
      render :show, status: :unprocessable_entity
    end
  end

  def password_params
    params.permit(:password, :password_confirmation)
  end
end
