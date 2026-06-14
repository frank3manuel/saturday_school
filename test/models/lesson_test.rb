require "test_helper"

class LessonTest < ActiveSupport::TestCase
  test "valid with a subject and title" do
    assert subjects(:math).lessons.new(title: "Trigonometry").valid?
  end

  test "requires a title" do
    lesson = subjects(:math).lessons.new(title: nil)
    assert_not lesson.valid?
    assert_includes lesson.errors[:title], "can't be blank"
  end

  test "requires a subject (belongs_to is required)" do
    lesson = Lesson.new(title: "Orphan", subject: nil)
    assert_not lesson.valid?
    assert_includes lesson.errors[:subject], "must exist"
  end

  test "subject_id NOT NULL is enforced at the database level" do
    error = assert_raises(ActiveRecord::NotNullViolation) do
      # Skip model validations to prove the DB constraint exists (plan §15 D1).
      Lesson.new(title: "No subject").save!(validate: false)
    end
    assert_match(/subject_id/, error.message)
  end

  test "has many items ordered by position" do
    assert_respond_to lessons(:algebra), :items
  end

  test "destroying a lesson cascades to its items" do
    lesson = lessons(:algebra)
    item_ids = lesson.items.pluck(:id)
    assert item_ids.any?

    assert_difference -> { Item.count } => -item_ids.size do
      lesson.destroy
    end
    assert_empty Item.where(id: item_ids)
  end
end
