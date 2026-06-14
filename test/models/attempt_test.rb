require "test_helper"

class AttemptTest < ActiveSupport::TestCase
  test "valid with item, user, grade, correct, and reviewed_at" do
    attempt = items(:due_item).attempts.new(
      grade: :good, correct: true, reviewed_at: Time.current, user: users(:owner)
    )
    assert attempt.valid?
  end

  test "requires a user (the learner) since M5" do
    attempt = items(:due_item).attempts.new(grade: :good, correct: true, reviewed_at: Time.current)
    assert_not attempt.valid?
    assert_includes attempt.errors[:user], "must exist"
  end

  test "requires an item" do
    attempt = Attempt.new(grade: :good, correct: true, reviewed_at: Time.current)
    assert_not attempt.valid?
    assert_includes attempt.errors[:item], "must exist"
  end

  test "requires reviewed_at" do
    attempt = items(:due_item).attempts.new(grade: :good, correct: true, reviewed_at: nil)
    assert_not attempt.valid?
    assert_includes attempt.errors[:reviewed_at], "can't be blank"
  end

  test "requires correct to be set (DB NOT NULL)" do
    attempt = items(:due_item).attempts.new(grade: :good, reviewed_at: Time.current)
    attempt.correct = nil
    assert_not attempt.valid?
  end

  test "grade enum maps to the 3-way self-grade" do
    assert_equal({ "missed" => 0, "hard" => 1, "good" => 2 }, Attempt.grades)
    assert attempts(:good_attempt).good?
    assert attempts(:missed_attempt).missed?
  end

  test "belongs to an optional quiz_session" do
    attempt = items(:due_item).attempts.new(
      grade: :good, correct: true, reviewed_at: Time.current, quiz_session: nil,
      user: users(:owner)
    )
    assert attempt.valid?
  end

  test "rejects negative interval and latency values" do
    attempt = items(:due_item).attempts.new(
      grade: :good, correct: true, reviewed_at: Time.current,
      interval_before: -1
    )
    assert_not attempt.valid?
  end

  test "is append-only: updates are refused" do
    attempt = attempts(:good_attempt)
    attempt.response_latency_ms = 9999
    assert_raises(ActiveRecord::ReadOnlyRecord) { attempt.save! }
  end

  test "DB enforces NOT NULL on correct" do
    assert_raises(ActiveRecord::NotNullViolation) do
      Attempt.new(item: items(:due_item), grade: :good, reviewed_at: Time.current)
             .save!(validate: false)
    end
  end

  test "deleting an item cascades to its attempts" do
    item = items(:due_item)
    assert_difference -> { Attempt.count }, -item.attempts.count do
      item.destroy
    end
  end
end
