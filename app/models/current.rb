# Per-request global state (plan §6). Holds the resolved Session for the request
# and delegates `user` to it, so application code reads `Current.user` without
# threading the user through every call. Reset automatically between requests.
class Current < ActiveSupport::CurrentAttributes
  attribute :session
  delegate :user, to: :session, allow_nil: true
end
