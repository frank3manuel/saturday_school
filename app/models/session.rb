class Session < ApplicationRecord
  belongs_to :user

  # An opaque, high-entropy token generated server-side. The browser holds only
  # this value (in a signed permanent cookie); the row is the revocable
  # server-side record of the session (plan §4.4, D-sessions).
  has_secure_token :token
end
