require "test_helper"

# The centralized honest stage mapping (plan §3). Pure logic first, then the
# bulk DB-backed accessor used by the dashboard and lists.
class MasteryStageTest < ActiveSupport::TestCase
  # --- The pure mapping: (recalled?, survived gap) → stage -----------------

  test "never recalled is New regardless of survived days" do
    assert_equal :new, MasteryStage.from(recalled: false, survived_days: 0)
    assert_equal :new, MasteryStage.from(recalled: false, survived_days: 99)
    assert_equal :new, MasteryStage.from(recalled: false, survived_days: nil)
  end

  test "recalled but only across a sub-1-day gap is Learning" do
    assert_equal :learning, MasteryStage.from(recalled: true, survived_days: 0)
    assert_equal :learning, MasteryStage.from(recalled: true, survived_days: nil)
  end

  test "survived a 1-to-6-day gap is Young" do
    assert_equal :young, MasteryStage.from(recalled: true, survived_days: 1)
    assert_equal :young, MasteryStage.from(recalled: true, survived_days: 3)
    assert_equal :young, MasteryStage.from(recalled: true, survived_days: 6)
  end

  test "survived a 7-to-59-day gap is Maturing" do
    assert_equal :maturing, MasteryStage.from(recalled: true, survived_days: 7)
    assert_equal :maturing, MasteryStage.from(recalled: true, survived_days: 21)
    assert_equal :maturing, MasteryStage.from(recalled: true, survived_days: 59)
  end

  test "survived a 60-day-or-longer gap is Durable" do
    assert_equal :durable, MasteryStage.from(recalled: true, survived_days: 60)
    assert_equal :durable, MasteryStage.from(recalled: true, survived_days: 180)
  end

  test "thresholds derive from the scheduler's mastery constants" do
    assert_equal Srs::Scheduler::MASTERY_INTERVAL_DAYS, MasteryStage::MATURING_DAYS
    assert_equal Srs::Scheduler::DURABLE_INTERVAL_DAYS, MasteryStage::DURABLE_DAYS
  end

  test "stages are ordered new → durable for consistent stacking" do
    assert_equal %i[new learning young maturing durable], MasteryStage::STAGES
  end

  test "truly-learned set is exactly maturing and durable" do
    assert_equal %i[maturing durable], MasteryStage::TRULY_LEARNED
  end

  test "labels and descriptions exist for every stage" do
    MasteryStage::STAGES.each do |stage|
      assert MasteryStage.label(stage).present?
      assert MasteryStage.description(stage).present?
    end
  end

  # --- Item#display_stage: derives from the item's own attempt log ---------

  test "Item#display_stage is New with no correct attempts" do
    item = lessons(:algebra).items.create!(prompt: "Q", answer: "A")
    assert_equal :new, item.display_stage
  end

  test "Item#display_stage reflects the longest survived gap" do
    item = lessons(:algebra).items.create!(prompt: "Q", answer: "A")
    attempt(item, correct: true, interval_before: 1)
    attempt(item, correct: true, interval_before: 7)  # the longest survived gap
    attempt(item, correct: false, interval_before: 60) # incorrect: doesn't count
    assert_equal 7, item.longest_survived_gap_days
    assert_equal :maturing, item.display_stage
  end

  # --- Bulk MasteryStage.for_items: one query, no N+1 ----------------------

  test "for_items maps every item to its stage in one grouped query" do
    new_item  = lessons(:algebra).items.create!(prompt: "n", answer: "a")
    young     = lessons(:algebra).items.create!(prompt: "y", answer: "a")
    durable   = lessons(:algebra).items.create!(prompt: "d", answer: "a")
    attempt(young,   correct: true, interval_before: 3)
    attempt(durable, correct: true, interval_before: 60)

    stages = MasteryStage.for_items([ new_item, young, durable ])
    assert_equal :new,     stages[new_item.id]
    assert_equal :young,   stages[young.id]
    assert_equal :durable, stages[durable.id]
  end

  test "for_items returns an empty hash for no items" do
    assert_equal({}, MasteryStage.for_items([]))
  end

  private

  def attempt(item, correct:, interval_before:)
    item.attempts.create!(
      user: users(:owner),
      correct: correct,
      grade: correct ? :good : :missed,
      reviewed_at: Time.current,
      interval_before: interval_before,
      interval_after: interval_before
    )
  end
end
