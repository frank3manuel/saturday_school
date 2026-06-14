require "test_helper"

class AnswerRecorderTest < ActiveSupport::TestCase
  setup do
    @user = users(:owner)
    @item = lessons(:algebra).items.create!(prompt: "Q", answer: "A")
  end

  test "writes exactly one attempt and one consistent state update" do
    assert_difference -> { Attempt.count }, 1 do
      AnswerRecorder.call(item: @item, grade: :good, user_id: @user.id)
    end

    @item.reload
    attempt = @item.attempts.last
    assert_equal "good", attempt.grade
    assert attempt.correct
    assert_equal @user.id, attempt.user_id
    assert_equal 0, attempt.interval_before, "captured the pre-attempt interval"
    assert_equal 1, attempt.interval_after,  "captured the new interval"
  end

  test "applies the scheduler result to the item inline columns" do
    travel_to Time.zone.local(2026, 2, 1, 9, 0, 0) do
      AnswerRecorder.call(item: @item, grade: :good, user_id: @user.id) # 0 -> level 1, +1d
    end
    @item.reload
    assert_equal 1, @item.box
    assert_equal 1, @item.interval_days
    assert_equal 1, @item.streak
    assert_equal 1, @item.repetitions
    assert_equal "review", @item.state
    assert_equal Time.zone.local(2026, 2, 2).to_date, @item.due_at.to_date
  end

  test "derives correctness from grade (missed = incorrect)" do
    @item.update!(box: 3, streak: 3, interval_days: 7, state: :review)
    AnswerRecorder.call(item: @item, grade: :missed, user_id: @user.id)
    @item.reload
    assert_equal "lapsed", @item.state
    assert_equal 1, @item.box
    assert_equal 0, @item.streak
    assert_equal 1, @item.lapses
    assert_nil @item.mastered_at
  end

  test "hard counts as a correct recall" do
    AnswerRecorder.call(item: @item, grade: :hard, user_id: @user.id)
    @item.reload
    assert @item.attempts.last.correct
    assert_equal 1, @item.box
  end

  test "marks an item mastered when a >=7-day gap is survived" do
    @item.update!(box: 3, streak: 3, interval_days: 7, state: :review)
    travel_to Time.zone.local(2026, 6, 1, 8) do
      AnswerRecorder.call(item: @item, grade: :good, user_id: @user.id)
    end
    @item.reload
    assert_equal "mastered", @item.state
    assert_equal Time.zone.local(2026, 6, 1, 8), @item.mastered_at
  end

  test "links the attempt to a quiz session and records latency" do
    session = quiz_sessions(:math_session)
    result = AnswerRecorder.call(
      item: @item, grade: :good, user_id: @user.id,
      quiz_session: session, response_latency_ms: 1234
    )
    assert_equal session, result.attempt.quiz_session
    assert_equal 1234, result.attempt.response_latency_ms
  end

  test "rolls back the attempt if persisting item state fails (one transaction)" do
    # Make the item state write blow up *after* the attempt would be inserted,
    # proving the Attempt insert and the state update share one transaction.
    boom = Class.new(StandardError)
    @item.define_singleton_method(:update!) { |*| raise boom }

    assert_no_difference -> { Attempt.count } do
      assert_raises(boom) do
        AnswerRecorder.call(item: @item, grade: :good, user_id: @user.id)
      end
    end
  end
end
