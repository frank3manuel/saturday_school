# Sign in / sign out (plan §7). `create` authenticates enumeration-safely via
# `User.authenticate_by` (constant-time, dummy-hashes the not-found path); a
# wrong password and an unknown email return the identical generic failure
# (plan §11). Sign-out is DELETE, never a GET link.
class SessionsController < ApplicationController
  layout "auth"
  allow_unauthenticated_access only: %i[new create]

  def new
  end

  def create
    if (user = User.authenticate_by(session_params))
      start_new_session_for(user)
      redirect_to after_authentication_url
    else
      # Identical for wrong password AND unknown email — never leak which.
      redirect_to new_session_path, alert: "That email or password didn't match.", status: :see_other
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, notice: "Signed out.", status: :see_other
  end

  private

  def session_params
    params.permit(:email_address, :password)
  end
end
