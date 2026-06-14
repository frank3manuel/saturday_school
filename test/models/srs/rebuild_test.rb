require "test_helper"

# The projection-invariant guard (plan §6, §12): a fixed attempt sequence
# recorded live must leave the item in the SAME state that `srs:rebuild`
# reconstructs purely from the append-only attempt log.
class Srs::RebuildTest < ActiveSupport::TestCase
  SRS_COLUMNS = %w[box interval_days streak repetitions lapses state mastered_at due_at last_reviewed_at].freeze

  setup do
    @item = lessons(:algebra).items.create!(prompt: "Q", answer: "A")
  end

  # A deterministic sequence spanning the whole ladder, a lapse, and a re-climb.
  # Each entry: [days_from_start, grade].
  SEQUENCE = [
    [ 0,   :good ],   # new -> level 1
    [ 1,   :good ],   # +1d survived -> level 2
    [ 4,   :good ],   # +3d survived -> level 3
    [ 11,  :good ],   # +7d survived -> MASTERED, level 4
    [ 32,  :missed ], # lapse -> level 1, mastered_at cleared
    [ 33,  :good ],   # +1d -> level 2
    [ 36,  :good ],   # +3d -> level 3
    [ 43,  :good ]    # +7d survived -> MASTERED again, level 4
  ].freeze

  test "live-recorded state equals srs:rebuild output for a fixed sequence" do
    start = Time.zone.local(2026, 1, 1, 9, 0, 0)

    SEQUENCE.each do |offset_days, grade|
      travel_to start + offset_days.days do
        AnswerRecorder.call(item: @item, grade: grade, user_id: users(:owner).id)
      end
    end

    live = snapshot(@item.reload)

    # Replay the attempt log from scratch and compare.
    Srs::Rebuild.call(items: Item.where(id: @item.id))
    rebuilt = snapshot(@item.reload)

    assert_equal live, rebuilt, "rebuild must reproduce the live-recorded state"

    # Sanity: the sequence actually exercised mastery + re-mastery.
    assert_equal "mastered", live["state"]
    assert_equal 4, live["box"]
  end

  test "rebuild is idempotent" do
    start = Time.zone.local(2026, 1, 1, 9)
    SEQUENCE.each do |offset_days, grade|
      travel_to start + offset_days.days do
        AnswerRecorder.call(item: @item, grade: grade, user_id: users(:owner).id)
      end
    end

    Srs::Rebuild.call(items: Item.where(id: @item.id))
    once = snapshot(@item.reload)
    Srs::Rebuild.call(items: Item.where(id: @item.id))
    twice = snapshot(@item.reload)

    assert_equal once, twice
  end

  test "rebuild resets an item with no attempts to the new baseline" do
    @item.update!(box: 4, streak: 4, state: :mastered, mastered_at: Time.current, interval_days: 21)
    Srs::Rebuild.call(items: Item.where(id: @item.id))
    @item.reload
    assert_equal 0, @item.box
    assert_equal "learning", @item.state
    assert_nil @item.mastered_at
    assert_equal 0, @item.streak
  end

  private

  def snapshot(item)
    item.attributes.slice(*SRS_COLUMNS)
  end
end
