class CreateItems < ActiveRecord::Migration[7.2]
  def change
    create_table :items do |t|
      t.references :lesson, null: false, foreign_key: { on_delete: :cascade }, index: true

      # Content
      t.text :prompt, null: false
      t.text :answer, null: false
      t.integer :item_type, null: false, default: 0 # enum: free_recall
      t.boolean :suspended, null: false, default: false

      # Inline SRS state (plan §4.2) — the owner's per-item scheduling state.
      # Columns only for M1; scheduling logic lands in M2.
      t.datetime :due_at
      t.integer :interval_days, null: false, default: 0
      t.integer :box, null: false, default: 0
      t.integer :streak, null: false, default: 0
      t.integer :repetitions, null: false, default: 0
      t.integer :lapses, null: false, default: 0
      t.datetime :last_reviewed_at
      t.datetime :mastered_at
      t.integer :state, null: false, default: 0 # enum: learning

      t.timestamps
    end

    # Hot due-query index (plan §4.3): active items ordered by when they're due.
    add_index :items, [ :suspended, :due_at ]
    # Dashboard / mastery rollups (plan §4.3).
    add_index :items, :mastered_at
  end
end
