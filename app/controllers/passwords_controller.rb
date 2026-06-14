# Forgot/reset password (plan §7, §9). Enumeration-safe: requesting a reset
# returns the identical "if an account exists, we've sent a link" confirmation
# whether or not the address is registered (plan §11). An expired or used token
# routes back to "send a new link" — never a dead end.
class PasswordsController < ApplicationController
  layout "auth"
  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[edit update]

  # The "forgot password" form.
  def new
  end

  # Send the reset email (or silently do nothing if no such account).
  def create
    if (user = User.find_by(email_address: params[:email_address]))
      PasswordsMailer.reset(user).deliver_later
    end
    redirect_to new_session_path,
                notice: "If an account exists for that email, we've sent a link to reset the password."
  end

  # The "choose a new password" form (token validated in the before_action).
  def edit
  end

  def update
    if @user.update(password_params)
      # Changing the password rotates the salt, invalidating this and any other
      # outstanding reset token automatically (plan §4.4).
      redirect_to new_session_path, notice: "Your password has been reset. Please sign in."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_user_by_token
    @user = User.find_by_token_for(:password_reset, params[:token])
    return if @user

    redirect_to new_password_path,
                alert: "That password reset link is invalid or has expired. Request a new one."
  end

  def password_params
    params.permit(:password, :password_confirmation)
  end
end
