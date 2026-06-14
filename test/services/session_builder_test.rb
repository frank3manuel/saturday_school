require "test_helper"

class SessionBuilderTest < ActiveSupport::TestCase
  setup do
    @user = users(:owner)
    @subject = @user.subjects.create!(name: "Spanish")
    @l1 = @subject.lessons.create!(title: "Verbs")
    @l2 = @subject.lessons.create!(title: "Nouns")
  end

  def due(lesson, days_overdue)
    lesson.items.create!(
      prompt: "p#{rand(10_000)}", answer: "a",
      state: :review, box: 1, interval_days: 1,
      due_at: days_overdue.days.ago
    )
  end

  test "orders most-overdue first" do
    older  = due(@l1, 5)
    newer  = due(@l1, 1)
    middle = due(@l1, 3)

    plan = SessionBuilder.call(user: @user, scope: @l1)

    assert_equal [ older.id, middle.id, newer.id ], plan.item_ids
  end

  test "interleaves across lessons" do
    l1a = due(@l1, 6)
    l1b = due(@l1, 4)
    l2a = due(@l2, 5)
    l2b = due(@l2, 3)

    plan = SessionBuilder.call(user: @user, scope: @subject)

    # Most-overdue (l1a, 6d) leads; then we alternate lessons rather than
    # draining one lesson before the other.
    walk = plan.item_ids.map { |id| Item.find(id).lesson_id }
    assert_equal @l1.id, Item.find(plan.item_ids.first).lesson_id
    assert_equal [ @l1.id, @l2.id, @l1.id, @l2.id ], walk
    assert_equal [ l1a.id, l2a.id, l1b.id, l2b.id ], plan.item_ids
  end

  test "caps the session size" do
    7.times { |i| due(@l1, i + 1) }

    plan = SessionBuilder.call(user: @user, scope: @l1, cap: 3)

    assert_equal 3, plan.size
  end

  test "only includes due, active items in scope" do
    in_scope = due(@l1, 2)
    @l1.items.create!(prompt: "future", answer: "a", state: :review,
                      due_at: 3.days.from_now, interval_days: 7, box: 3)
    @l1.items.create!(prompt: "suspended", answer: "a", suspended: true,
                      state: :review, due_at: 1.day.ago)
    other_subject = @user.subjects.create!(name: "Other")
    due(other_subject.lessons.create!(title: "X"), 9)

    plan = SessionBuilder.call(user: @user, scope: @subject)

    assert_equal [ in_scope.id ], plan.item_ids
  end

  test "all-due scope spans every subject" do
    a = due(@l1, 2)
    other = @user.subjects.create!(name: "Other")
    b = due(other.lessons.create!(title: "X"), 4)

    plan = SessionBuilder.call(user: @user, scope: nil)
    # Both due items appear (most-overdue b leads). Fixtures may add their own
    # due items, so assert membership rather than exact equality.
    assert_includes plan.item_ids, a.id
    assert_includes plan.item_ids, b.id
    assert_equal "All due", plan.scope_label
  end

  test "materializes a plain frozen-style list of ids computed once" do
    a = due(@l1, 2)
    plan = SessionBuilder.call(user: @user, scope: @l1)

    # Grading the item moves its due_at into the future. A re-walk of the SAME
    # plan must NOT drop it — the list was materialized once.
    AnswerRecorder.call(item: a, grade: :good, user_id: @user.id)
    assert_includes plan.item_ids, a.id, "plan list is fixed, not a live query"
    assert_kind_of Array, plan.item_ids
    assert plan.item_ids.all?(Integer)
  end
end
