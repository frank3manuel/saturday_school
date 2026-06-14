class CreateAttempts < ActiveRecord::Migration[7.2]
  def change
    create_table :attempts do |t|
      # The quizzed item (plan §4.1). Append-only event log; the source of truth.
      t.references :item, null: false, foreign_key: { on_delete: :cascade }

      # The learner who attempted (plan §4.5 — the one sanctioned denormalization).
      # NOT NULL per plan, but `users` doesn't exist until M5; mirror M1's pattern:
      # indexed integer, NO foreign key, NOT-NULL deferred to M5's backfill.
      t.integer :user_id

      # Nullable: an attempt may exist outside a grouped session.
      t.references :quiz_session, null: true, foreign_key: { on_delete: :nullify }

      t.integer :grade, null: false, default: 0 # enum: missed/hard/good
      t.boolean :correct, null: false
      t.datetime :reviewed_at, null: false
      t.integer :interval_before
      t.integer :interval_after
      t.integer :response_latency_ms

      t.timestamps
    end

    # Per-learner item history (plan §4.1); also the rebuild grouping key.
    add_index :attempts, [ :user_id, :item_id ]
    # Per-item history (plan §4.1) — index added by t.references :item above,
    # so this composite plus that single-column index cover the planned shapes.
  end
end
