class CreateSubjects < ActiveRecord::Migration[7.2]
  def change
    create_table :subjects do |t|
      t.string :name, null: false
      t.text :description
      # Ownership: nullable for M1 (single seeded owner; no users table yet).
      # Becomes NOT NULL with a real users FK in M5 (plan §4.5, §4.7). No DB FK
      # yet because `users` does not exist — just the readiness hook + index.
      t.integer :user_id
      t.integer :position

      t.timestamps
    end

    add_index :subjects, :user_id
  end
end
