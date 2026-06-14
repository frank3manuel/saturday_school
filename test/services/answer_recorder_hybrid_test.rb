require "test_helper"

# The owner-vs-learner branch in AnswerRecorder (plan §4.6, §6, §15 D-state). The
# learner's state lands in the RIGHT home, attempts stay server-authoritative,
# and one learner's grading never touches another's (or the owner's) state.
class AnswerRecorderHybridTest < ActiveSupport::TestCase
  setup do
    @item    = items(:teacher_item_one) # owned by teacher
    @owner   = users(:teacher)
    @learner = users(:student)
    travel_to Time.zone.local(2026, 6, 14, 12, 0, 0)
  end

  teardown { travel_back }

  test "owner grading writes to the item's inline columns" do
    AnswerRecorder.call(item: @item, grade: :good, user_id: @owner.id)
    @item.reload
    assert_equal 1, @item.box, "owner state lives inline"
    # The learner's row is untouched.
    assert_equal 2, ReviewState.for(@learner, @item).box
  end

  test "assigned learner grading writes to their review_states row, not the item" do
    before_item_box = @item.box
    AnswerRecorder.call(item: @item, grade: :good, user_id: @learner.id)

    @item.reload
    assert_equal before_item_box, @item.box, "owner inline state must be untouched"

    state = ReviewState.for(@learner, @item)
    assert_equal 3, state.box, "learner advanced from fixture box 2 → 3"
  end

  test "attempt user_id is the learner (server-authoritative), and item is the master" do
    result = AnswerRecorder.call(item: @item, grade: :good, user_id: @learner.id)
    assert_equal @learner.id, result.attempt.user_id
    assert_equal @item.id, result.attempt.item_id
  end

  test "two learners grading the same assigned item keep independent state" do
    other = users(:owner)
    # @learner starts at fixture box 2; a good answer advances to box 3.
    AnswerRecorder.call(item: @item, grade: :good, user_id: @learner.id)
    # `other` starts at a fresh row (box 0); a missed answer drops to relearning.
    AnswerRecorder.call(item: @item, grade: :missed, user_id: other.id)

    learner_state = ReviewState.for(@learner, @item)
    other_state   = ReviewState.for(other, @item)
    assert_equal 3, learner_state.box
    assert other_state.lapsed?
    assert_not_equal learner_state.box, other_state.box
  end
end
