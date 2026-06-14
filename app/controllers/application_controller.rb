class ApplicationController < ActionController::Base
  # Secure-by-default authentication (plan §7): every action requires a signed-in
  # user unless its controller opts out with `allow_unauthenticated_access`.
  include Authentication

  # Authorization (the classroom layer, plan §8.2): Pundit is adopted thinly — it
  # backs the new cross-user role gates (cohort/assignment/admin actions) and the
  # doubly-scoped teacher/admin Scope classes. Personal-content CRUD stays on the
  # existing `current_user.subjects.find(...)` association scoping; it does NOT go
  # through Pundit.
  include Pundit::Authorization

  # Pundit needs the acting user; in this app that is the authenticated user.
  def pundit_user
    current_user
  end

  # A forbidden authorization (role gate fails) renders a friendly 403. Note the
  # privacy model is mostly *structural* (a teacher simply can't reach another
  # teacher's rows), so 404 dominates; 403 is for "your role can't do this verb."
  rescue_from Pundit::NotAuthorizedError, with: :authorization_denied

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  private

  def authorization_denied
    respond_to do |format|
      format.html { render file: Rails.public_path.join("403.html"), status: :forbidden, layout: false }
      format.any  { head :forbidden }
    end
  end
end
