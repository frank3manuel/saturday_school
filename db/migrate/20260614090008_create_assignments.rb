# Assignments — teacher content → cohort, at LESSON grain (plan §4.6, §15
# D-grain). The Assignment join is THE only window a teacher has into student
# data (plan §8.2): a personal item has no assignment row, so it can never appear
# in a teacher's result set — privacy is a property of the join graph. cohort_id
# and lesson_id cascade; `assigned_by` is on_delete: :restrict (audit/provenance,
# blocks deleting the assigning teacher while assignments live). `withdrawn_at`
# is a soft-stop that preserves per-student state/history. Unique
# [cohort_id, lesson_id] prevents duplicate assignment of the same lesson.
class CreateAssignments < ActiveRecord::Migration[7.2]
  def change
    create_table :assignments do |t|
      t.references :cohort, null: false, foreign_key: { on_delete: :cascade }
      t.references :lesson, null: false, foreign_key: { on_delete: :cascade }
      # Plan §4.6 names this column `assigned_by` (not `assigned_by_id`); declare
      # it explicitly and add the named FK rather than via t.references.
      t.integer  :assigned_by, null: false
      t.datetime :assigned_at, null: false
      t.datetime :withdrawn_at
      t.timestamps
    end

    add_index :assignments, :assigned_by
    add_index :assignments, %i[cohort_id lesson_id], unique: true
    add_foreign_key :assignments, :users, column: :assigned_by, on_delete: :restrict
  end
end
