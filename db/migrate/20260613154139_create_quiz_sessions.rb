class CreateQuizSessions < ActiveRecord::Migration[7.2]
  def change
    create_table :quiz_sessions do |t|
      # Nullable scope: a null subject_id means an "all due" session (plan §4.1, §6).
      t.references :subject, null: true, foreign_key: { on_delete: :cascade }, index: true

      # The learner. NOT NULL per plan §4.1/§4.5, but there is no `users` table
      # until M5 — so we follow M1's readiness pattern for subjects.user_id:
      # an indexed integer with NO foreign key, NOT-NULL deferred. M5's backfill
      # seeds the user, adds the FK, and flips this to null: false.
      t.integer :user_id, index: true

      t.datetime :started_at
      t.datetime :completed_at
      t.integer :planned_count

      t.timestamps
    end
  end
end
