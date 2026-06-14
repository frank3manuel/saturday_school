require "test_helper"

# Replay/determinism extended to the ASSIGNED path (plan §12): a student's
# attempts on an assigned item rebuild THEIR review_states row, and a rebuild
# equals the live-recorded state. The owner's inline state stays independent.
class Srs::RebuildHybridTest < ActiveSupport::TestCase
  SRS_COLUMNS = %w[box interval_days streak repetitions lapses state due_at mastered_at].freeze

  setup do
    @item    = items(:teacher_item_two) # owned by teacher; learner state is 'new'
    @owner   = users(:teacher)
    @learner = users(:student)
  end

  test "a learner's assigned attempts rebuild their review_states row deterministically" do
    travel_to Time.zone.local(2026, 1, 1, 9, 0, 0)
    AnswerRecorder.call(item: @item, grade: :good, user_id: @learner.id)
    travel_to Time.zone.local(2026, 1, 2, 9, 0, 0)
    AnswerRecorder.call(item: @item, grade: :good, user_id: @learner.id)
    travel_to Time.zone.local(2026, 1, 5, 9, 0, 0)
    AnswerRecorder.call(item: @item, grade: :good, user_id: @learner.id)
    travel_back

    live = snapshot(ReviewState.for(@learner, @item))

    Srs::Rebuild.call(items: Item.where(id: @item.id))
    rebuilt = snapshot(ReviewState.for(@learner, @item).reload)

    assert_equal live, rebuilt, "rebuilt assigned state must equal live-recorded state"
  end

  test "rebuilding does not bleed a learner's attempts into the owner's inline state" do
    travel_to Time.zone.local(2026, 1, 1, 9, 0, 0)
    AnswerRecorder.call(item: @item, grade: :good, user_id: @learner.id)
    travel_back

    Srs::Rebuild.call(items: Item.where(id: @item.id))
    @item.reload
    assert_equal 0, @item.box, "owner inline state untouched by the learner's attempts"
    assert ReviewState.for(@learner, @item).box.positive?
  end

  private

  def snapshot(record)
    record.attributes.slice(*SRS_COLUMNS)
  end
end
