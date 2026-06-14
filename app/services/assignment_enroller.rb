# frozen_string_literal: true

# Eager review_states creation (plan §4.6, §15 D-state). The hybrid model wants a
# review_states row to already exist for every (active student × assigned item)
# pair, so the assigned due-query never has to LEFT-JOIN for a missing row.
#
# Two entry points, two directions of the same matrix:
#   - on ASSIGNMENT: create rows for all current active enrollees of the cohort.
#   - on ENROLLMENT:  create rows for all live assignments of the cohort.
#
# Idempotent: uses insert_all with a unique (user_id, item_id) index, so
# re-running (re-assign, rejoin) never duplicates or clobbers existing state.
# Owner-authored items keep their state inline; only NON-owner learners get rows
# here (an enrolled student is never the teacher who owns the content).
class AssignmentEnroller
  # When a lesson is assigned to a cohort: every active student gets a row for
  # each of the lesson's items.
  def self.enroll_assignment(assignment)
    cohort   = assignment.cohort
    item_ids = assignment.lesson.items.pluck(:id)
    student_ids = cohort.active_enrollments.pluck(:user_id)
    create_rows(student_ids, item_ids)
  end

  # When a student (re)joins a cohort: they get a row for every item of every
  # live assignment in that cohort.
  def self.enroll_student(cohort:, student:)
    item_ids = Item.where(lesson_id: cohort.active_assignments.select(:lesson_id)).pluck(:id)
    create_rows([ student.id ], item_ids)
  end

  # Bulk-insert the (user, item) rows that don't yet exist. SQLite supports the
  # unique-index conflict skip via insert_all (no ON CONFLICT needed — Rails
  # filters by the unique index). DB defaults fill the SRS columns to the
  # new-item baseline (box 0, state 0/learning, due_at nil).
  def self.create_rows(user_ids, item_ids)
    return if user_ids.empty? || item_ids.empty?

    now = Time.current
    rows = user_ids.product(item_ids).map do |user_id, item_id|
      { user_id: user_id, item_id: item_id, created_at: now, updated_at: now }
    end
    # unique_by skips rows that would violate the (user_id, item_id) unique index,
    # so existing state is preserved (idempotent).
    ReviewState.insert_all(rows, unique_by: %i[user_id item_id])
  end
end
