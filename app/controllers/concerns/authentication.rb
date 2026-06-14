# Hand-rolled authentication (plan §7), modeled on the Rails 8 auth generator so
# the code converges when this 7.2 app upgrades. DB-backed sessions (the
# `sessions` table) + a single permanent signed cookie holding the session
# token. Secure-by-default: every action requires authentication unless the
# controller opts out with `allow_unauthenticated_access`.
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?, :current_user
  end

  class_methods do
    # Opt a controller (or specific actions) out of the secure-by-default gate —
    # used only by the auth pages themselves (sign in/up, password reset).
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private

  def authenticated?
    resume_session
  end

  def require_authentication
    resume_session || request_authentication
  end

  # Resolve the current session from the signed cookie (at most one lookup per
  # request — the resolved Session is memoized on Current). Refreshes the cookie
  # so the ~90-day window slides forward on each authenticated visit (plan §4.4).
  def resume_session
    Current.session ||= find_session_by_cookie
    refresh_session_cookie if Current.session
    Current.session
  end

  def find_session_by_cookie
    token = cookies.signed[:session_id]
    Session.find_by(token: token) if token
  end

  def request_authentication
    session[:return_to_after_authenticating] = request.url if request.get?
    redirect_to new_session_path
  end

  def after_authentication_url
    session.delete(:return_to_after_authenticating) || root_url
  end

  # Establish a brand-new session row + token on login (session fixation defense,
  # plan §11) and set the permanent signed cookie.
  def start_new_session_for(user)
    user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
      Current.session = session
      set_session_cookie(session)
    end
  end

  def terminate_session
    Current.session&.destroy
    cookies.delete(:session_id)
    Current.session = nil
  end

  def set_session_cookie(session)
    cookies.signed.permanent[:session_id] = {
      value: session.token,
      httponly: true,
      same_site: :lax,
      secure: Rails.env.production?
    }
  end

  # Re-stamp the permanent cookie so its expiry slides forward each visit.
  def refresh_session_cookie
    set_session_cookie(Current.session)
  end

  def current_user
    Current.user
  end
end
