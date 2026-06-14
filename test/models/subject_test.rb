require "test_helper"

class SubjectTest < ActiveSupport::TestCase
  test "valid with a name and an owner" do
    assert Subject.new(name: "Science", user: users(:owner)).valid?
  end

  test "requires a name" do
    subject = Subject.new(name: nil, user: users(:owner))
    assert_not subject.valid?
    assert_includes subject.errors[:name], "can't be blank"
  end

  test "requires an owner since M5" do
    subject = Subject.new(name: "Ownerless")
    assert_not subject.valid?
    assert_includes subject.errors[:user], "must exist"
  end

  test "has many lessons" do
    assert_equal [ lessons(:algebra), lessons(:geometry) ], subjects(:math).lessons.to_a
  end

  test "has many items through lessons" do
    assert_includes subjects(:math).items, items(:new_item)
    assert_includes subjects(:math).items, items(:not_due_item)
  end

  test "destroying a subject cascades to lessons and items" do
    subject = subjects(:math)
    lesson_ids = subject.lessons.pluck(:id)
    item_ids = subject.items.pluck(:id)

    assert_difference -> { Lesson.count } => -lesson_ids.size,
                      -> { Item.count } => -item_ids.size do
      subject.destroy
    end

    assert_empty Lesson.where(id: lesson_ids)
    assert_empty Item.where(id: item_ids)
  end

  test "DB-level cascade removes lessons even on delete (no callbacks)" do
    subject = subjects(:history)
    lesson_ids = subject.lessons.pluck(:id)
    subject.delete
    assert_empty Lesson.where(id: lesson_ids)
  end
end
