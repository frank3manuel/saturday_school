# The append-only admin audit log (plan §11): a read-only view of role changes
# and account deletions. Admin-only — reuses UserPolicy's index gate (the audit
# log is part of the account-administration surface).
class Admin::AuditEventsController < ApplicationController
  def index
    authorize User, :index?
    @audit_events = AuditEvent.recent.limit(200)
  end
end
