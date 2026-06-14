# ReviewStates — per-student SRS state for NON-OWNER learners (the hybrid model,
# plan §4.6, §15 D-state). An item's inline SRS columns hold the OWNER's state;
# every other learner of that (assigned) item reads/writes a review_states row
# keyed (user_id, item_id). This is a MIRROR of the inline SRS columns so the one
# pure Srs::Scheduler result applies identically to either home.
#
# Rows are created EAGERLY at assignment time (for active enrollees) and at
# enrollment time (for existing assignments) so the due-query never LEFT-JOINs
# for missing state. Unique [user_id, item_id]; the composite
# [user_id, suspended, due_at] is the hot due-query index for assigned content.
class CreateReviewStates < ActiveRecord::Migration[7.2]
  def change
    create_table :review_states do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :item, null: false, foreign_key: { on_delete: :cascade }
      t.boolean  :suspended, null: false, default: false
      t.datetime :due_at
      t.integer  :interval_days, null: false, default: 0
      t.integer  :box, null: false, default: 0
      t.integer  :streak, null: false, default: 0
      t.integer  :repetitions, null: false, default: 0
      t.integer  :lapses, null: false, default: 0
      t.datetime :last_reviewed_at
      t.datetime :mastered_at
      t.integer  :state, null: false, default: 0
      t.timestamps
    end

    add_index :review_states, %i[user_id item_id], unique: true
    add_index :review_states, %i[user_id suspended due_at]
  end
end
