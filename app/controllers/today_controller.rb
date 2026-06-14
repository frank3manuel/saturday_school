# Today / Home — the front door to the spaced-review loop (plan §9).
#
# Shows a single honest CTA ("Start review — N due") when items are due, and a
# calm empty state ("Nothing due") otherwise — never a nag, because studying
# ahead degrades the schedule (plan §3). Learning new items is kept as a
# separate, deliberate action.
class TodayController < ApplicationController
  def show
    # The honest "N due" must include BOTH the user's personal due items AND
    # their assigned due items (the hybrid model, plan §4.6) — otherwise an
    # assigned-only learner would see "Nothing due" while assigned cards wait.
    @due_count = personal_due_count + assigned_due_count
    @new_count = current_user.items.active.where(due_at: nil).count
    # Subjects that actually have due items, so the user can start a scoped
    # review without digging through the Library. One grouped query, no N+1.
    @due_by_subject = due_counts_by_subject
  end

  private

  def personal_due_count
    current_user.items.due(Time.current).count
  end

  # Assigned due: the learner's review_states that are due AND still live-assigned
  # to a cohort they're actively enrolled in (mirrors SessionBuilder's filter, so
  # the count matches the queue the student would actually get).
  def assigned_due_count
    due_item_ids = current_user.review_states.due(Time.current).pluck(:item_id)
    return 0 if due_item_ids.empty?

    live_lesson_ids = Assignment.live
      .where(cohort_id: current_user.enrollments.active.select(:cohort_id))
      .select(:lesson_id)
    Item.where(id: due_item_ids, lesson_id: live_lesson_ids).count
  end

  # Scoped to the signed-in user's subjects (plan §8.3).
  def due_counts_by_subject
    current_user.subjects
      .joins(lessons: :items)
      .merge(Item.due(Time.current))
      .group("subjects.id", "subjects.name")
      .count
      .map { |(id, name), count| { id: id, name: name, count: count } }
      .sort_by { |row| -row[:count] }
  end
end
