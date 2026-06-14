require "test_helper"

# The privacy-critical owner-vs-learner state branch (plan §4.6, §15 D-state).
# Tested exhaustively for BOTH arms: an item's inline columns are the OWNER's
# state; every other learner reads/writes their own review_states row. No state
# ever leaks across users.
class ItemStateForTest < ActiveSupport::TestCase
  setup do
    @item     = items(:teacher_item_one)   # owned by teacher (teacher_subject)
    @owner    = users(:teacher)
    @learner  = users(:student)
    @stranger = users(:other)
  end

  test "owner's state home is the item itself (inline columns)" do
    assert @item.owned_by?(@owner)
    assert_same @item, @item.srs_home_for(@owner)
  end

  test "a non-owner learner's state home is their own review_states row" do
    refute @item.owned_by?(@learner)
    home = @item.srs_home_for(@learner)
    assert_instance_of ReviewState, home
    assert_equal @learner.id, home.user_id
    assert_equal @item.id, home.item_id
  end

  test "srs_home_for eagerly finds-or-creates the review_states row idempotently" do
    # The fixture row already exists for student+teacher_item_one.
    assert_no_difference -> { ReviewState.count } do
      @item.srs_home_for(@learner)
    end
    # A learner with no row yet gets exactly one created.
    assert_difference -> { ReviewState.count }, 1 do
      @item.srs_home_for(@stranger)
    end
  end

  test "state_for reads the owner's inline state, not any learner's" do
    @item.update!(box: 4, streak: 9, state: :review)
    owner_state = @item.state_for(@owner)
    assert_equal 4, owner_state[:box]
    assert_equal 9, owner_state[:streak]
  end

  test "state_for reads the learner's own row, isolated from the owner" do
    @item.update!(box: 4, streak: 9) # owner state
    learner_state = @item.state_for(@learner) # fixture: box 2, streak 2
    assert_equal 2, learner_state[:box]
    assert_equal 2, learner_state[:streak]
    refute_equal @item.box, learner_state[:box], "learner state must not equal owner state"
  end

  test "two different learners never share a state row" do
    a = @item.srs_home_for(@learner)
    b = @item.srs_home_for(@stranger)
    refute_equal a.id, b.id
  end
end
