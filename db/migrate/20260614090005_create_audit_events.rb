# Append-only audit trail for admin destructive actions (plan §11): role
# changes and account deletes. The trail must OUTLIVE the records it describes,
# so `target_user_id` is nullable + `on_delete: :nullify` — deleting a user
# nullifies the FK but keeps the audit row (and its denormalized
# `target_email`). `actor_id` (the admin) is also nullify for the same reason.
class CreateAuditEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :audit_events do |t|
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :target_user, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string  :action, null: false
      t.string  :target_email
      t.text    :details
      t.timestamps
    end

    add_index :audit_events, :action
  end
end
