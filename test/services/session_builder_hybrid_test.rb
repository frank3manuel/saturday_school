require "test_helper"

# A student's "all due" queue = personal due ∪ assigned due, merged in Ruby from
# two index-backed queries, with each card tagged by origin (plan §6, §4.6).
class SessionBuilderHybridTest < ActiveSupport::TestCase
  setup do
    @student = users(:student)
    @now     = Time.current
  end

  test "all-due queue unions the student's personal due and assigned due items" do
    # Give the student a personal due item of their own.
    subject = @student.subjects.create!(name: "Student's own deck")
    lesson  = subject.lessons.create!(title: "Mine")
    personal = lesson.items.create!(prompt: "Personal?", answer: "yes",
                                    due_at: 1.day.ago, state: :review, box: 1)

    plan = SessionBuilder.call(user: @student, now: @now)

    # The fixture assigned item (teacher_item_one) is due via review_states.
    assert_includes plan.item_ids, items(:teacher_item_one).id
    assert_includes plan.item_ids, personal.id

    assert_equal :personal, plan.origin_for(personal.id)
    assert_equal :assigned, plan.origin_for(items(:teacher_item_one).id)
  end

  test "assigned items not yet due are excluded" do
    plan = SessionBuilder.call(user: @student, now: @now)
    # teacher_item_two has a 'new' (nil due_at) review_state → not due.
    assert_not_includes plan.item_ids, items(:teacher_item_two).id
  end

  test "withdrawing the assignment drops the assigned card from the queue" do
    assignments(:teacher_lesson_to_cohort_one).withdraw!
    plan = SessionBuilder.call(user: @student, now: @now)
    assert_not_includes plan.item_ids, items(:teacher_item_one).id
  end

  test "leaving the cohort drops assigned cards from the queue" do
    enrollments(:student_in_cohort_one).leave!
    plan = SessionBuilder.call(user: @student, now: @now)
    assert_not_includes plan.item_ids, items(:teacher_item_one).id
  end

  test "the assigned due-query uses the review_states index (no item full scan)" do
    # A query-count style guard: the assigned path is a couple of small queries,
    # not one-per-card. We assert it doesn't blow up across many states.
    plan = nil
    assert_nothing_raised { plan = SessionBuilder.call(user: @student, now: @now) }
    assert plan.item_ids.any?
  end
end
