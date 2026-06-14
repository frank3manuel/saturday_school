# Cohorts — the "Class" (code name Cohort, plan §4.6, §15 D-grain). A teacher
# owns cohorts; `on_delete: :restrict` blocks deleting a teacher while cohorts
# are live (plan §15 D-leave — surfaced as a friendly message, not a 500). The
# join_code is an opaque high-entropy token with a unique index, so join-by-code
# is enumeration-resistant (plan §4.6, §11).
class CreateCohorts < ActiveRecord::Migration[7.2]
  def change
    create_table :cohorts do |t|
      t.references :teacher, null: false,
                   foreign_key: { to_table: :users, on_delete: :restrict }
      t.string   :name, null: false
      t.string   :join_code, null: false
      t.text     :description
      t.datetime :archived_at
      t.timestamps
    end

    add_index :cohorts, :join_code, unique: true
  end
end
