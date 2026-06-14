# Sign up (plan §7, §9). On success the new account is auto-logged-in and sent
# into the app. Enumeration-safe: a duplicate email never reports "already
# taken" (the existing owner is notified out-of-band — deferred); instead we
# render a generic success and don't create a second account (plan §11).
class RegistrationsController < ApplicationController
  layout "auth"
  allow_unauthenticated_access only: %i[new create]

  def new
    @user = User.new
  end

  def create
    @user = User.new(registration_params)

    if @user.save
      start_new_session_for(@user)
      redirect_to after_authentication_url, notice: "Welcome to Saturday School."
    elsif duplicate_email_only?
      # Don't leak that the address is registered. Behave as if signup succeeded
      # without creating anything or signing anyone in; the real owner keeps
      # control of the account (out-of-band notification deferred).
      redirect_to new_session_path, notice: "Check your email to finish setting up your account."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  # Strong params: only email + password are ever mass-assignable. role,
  # verified_at, password_digest are server-authoritative (plan §11).
  def registration_params
    params.permit(:email_address, :password)
  end

  # True when the ONLY thing wrong is that the email is taken (so we can respond
  # enumeration-safely rather than re-rendering a leaky "already taken" error).
  def duplicate_email_only?
    errors = @user.errors
    errors.of_kind?(:email_address, :taken) &&
      errors.all? { |e| e.attribute == :email_address && e.type == :taken }
  end
end
