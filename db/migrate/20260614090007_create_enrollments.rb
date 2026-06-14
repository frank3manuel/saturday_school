# Enrollments — Student ↔ Cohort (plan §4.6, §15 D-leave). Leaving flips
# `status` (active → left/removed), never deletes, so the attempt log is
# retained while the student drops from the active roster/queue. Unique
# [cohort_id, user_id] prevents double-enrollment; indexes back the roster query
# ([cohort_id, status]) and "my classes" (user_id). Both FKs cascade so a deleted
# cohort or student cleanly removes its enrollments.
class CreateEnrollments < ActiveRecord::Migration[7.2]
  def change
    create_table :enrollments do |t|
      t.references :cohort, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string   :status, null: false, default: "active"
      t.datetime :joined_at, null: false
      t.datetime :ended_at
      t.timestamps
    end

    add_index :enrollments, %i[cohort_id user_id], unique: true
    add_index :enrollments, %i[cohort_id status]
    add_check_constraint :enrollments,
      "status IN ('active', 'left', 'removed')", name: "enrollments_status_check"
  end
end
