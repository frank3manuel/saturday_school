# Tighten ownership (plan §4.7): flip `user_id` to NOT NULL and add the FKs on
# subjects, quiz_sessions, and attempts — kept SEPARATE from the backfill so a
# data bug can't wedge this schema change. Idempotent and reversible.
#
# The `user_id` indexes already exist from M1/M2 (the readiness pattern), except
# attempts, which has a composite `[:user_id, :item_id]` index that already
# covers user_id lookups — so no new indexes are needed here.
class TightenUserOwnership < ActiveRecord::Migration[7.2]
  TABLES = %w[subjects quiz_sessions attempts].freeze

  def up
    TABLES.each do |table|
      change_column_null table, :user_id, false
      add_foreign_key table, :users, on_delete: :cascade unless foreign_key_exists?(table, :users)
    end
  end

  def down
    TABLES.each do |table|
      remove_foreign_key table, :users if foreign_key_exists?(table, :users)
      change_column_null table, :user_id, true
    end
  end
end
