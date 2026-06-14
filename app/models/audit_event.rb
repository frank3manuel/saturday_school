# frozen_string_literal: true

# Append-only audit trail for admin destructive actions (plan §11): role changes
# and account deletes. Like Attempt, an audit row is a historical fact and must
# never be mutated or deleted. `actor`/`target_user` are nullable so the trail
# survives a user deletion; `target_email` denormalizes the affected address so
# the record stays meaningful after the user row is gone.
class AuditEvent < ApplicationRecord
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :target_user, class_name: "User", optional: true

  ROLE_CHANGED   = "role_changed"
  ACCOUNT_DELETED = "account_deleted"

  validates :action, presence: true

  scope :recent, -> { order(created_at: :desc) }

  # Record an audit event. `details` is a Hash serialized to JSON for an
  # at-a-glance "what changed" (e.g. {from: "student", to: "teacher"}).
  def self.record!(action:, actor:, target_user:, details: {})
    create!(
      action: action,
      actor: actor,
      target_user: target_user,
      target_email: target_user&.email_address,
      details: details.to_json
    )
  end

  def detail_hash
    details.present? ? JSON.parse(details) : {}
  end

  # Append-only: an audit event is immutable.
  before_update do
    raise ActiveRecord::ReadOnlyRecord, "AuditEvent is append-only"
  end
end
