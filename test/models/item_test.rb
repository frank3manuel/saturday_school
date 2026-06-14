require "test_helper"

class ItemTest < ActiveSupport::TestCase
  test "valid with lesson, prompt, and answer" do
    item = lessons(:algebra).items.new(prompt: "Q", answer: "A")
    assert item.valid?
  end

  test "requires a prompt" do
    item = lessons(:algebra).items.new(prompt: nil, answer: "A")
    assert_not item.valid?
    assert_includes item.errors[:prompt], "can't be blank"
  end

  test "requires an answer" do
    item = lessons(:algebra).items.new(prompt: "Q", answer: nil)
    assert_not item.valid?
    assert_includes item.errors[:answer], "can't be blank"
  end

  test "requires a lesson" do
    item = Item.new(prompt: "Q", answer: "A", lesson: nil)
    assert_not item.valid?
    assert_includes item.errors[:lesson], "must exist"
  end

  test "DB enforces NOT NULL on prompt and answer" do
    assert_raises(ActiveRecord::NotNullViolation) do
      Item.new(lesson: lessons(:algebra), prompt: nil, answer: "A").save!(validate: false)
    end
    assert_raises(ActiveRecord::NotNullViolation) do
      Item.new(lesson: lessons(:algebra), prompt: "Q", answer: nil).save!(validate: false)
    end
  end

  test "rejects negative SRS counters" do
    item = lessons(:algebra).items.new(prompt: "Q", answer: "A", streak: -1)
    assert_not item.valid?
    assert_includes item.errors[:streak], "must be greater than or equal to 0"
  end

  # --- Defaults -----------------------------------------------------------

  test "defaults for a new item" do
    item = lessons(:algebra).items.create!(prompt: "Q", answer: "A")
    assert_equal "free_recall", item.item_type
    assert_equal "learning", item.state
    assert_equal false, item.suspended
    assert_equal 0, item.interval_days
    assert_equal 0, item.box
    assert_equal 0, item.streak
    assert_equal 0, item.repetitions
    assert_equal 0, item.lapses
    assert_nil item.due_at
    assert_nil item.mastered_at
  end

  # --- Enums --------------------------------------------------------------

  test "item_type enum" do
    assert_equal 0, Item.item_types[:free_recall]
    assert items(:new_item).free_recall?
  end

  test "state enum values" do
    assert_equal({ "learning" => 0, "review" => 1, "mastered" => 2, "lapsed" => 3 }, Item.states)
    assert items(:new_item).learning?
    assert items(:mastered_item).mastered?
  end

  # --- Scopes -------------------------------------------------------------

  test "active scope excludes suspended items" do
    assert_includes Item.active, items(:due_item)
    assert_not_includes Item.active, items(:suspended_item)
  end

  test "due scope returns active items past their due_at" do
    due = Item.due
    assert_includes due, items(:due_item)
    assert_not_includes due, items(:not_due_item),  "future due_at is not due"
    assert_not_includes due, items(:suspended_item), "suspended is never due"
    assert_not_includes due, items(:new_item),       "nil due_at is not due"
  end

  test "due scope honors the passed-in time" do
    future = 1.year.from_now
    assert_includes Item.due(future), items(:not_due_item)
  end

  test "mastered scope (provided by the state enum)" do
    assert_includes Item.mastered, items(:mastered_item)
    assert_not_includes Item.mastered, items(:due_item)
  end

  test "learning scope (provided by the state enum)" do
    assert_includes Item.learning, items(:new_item)
    assert_not_includes Item.learning, items(:mastered_item)
  end
end
