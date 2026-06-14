require "test_helper"

# Pure-function tests for the scheduler (plan §12 — the highest-value suite).
# No DB, no fixtures: just the ladder, transitions, streak math, and the
# mastery gate.
class Srs::SchedulerTest < ActiveSupport::TestCase
  Scheduler = Srs::Scheduler

  private

  def next_state(current, **kwargs)
    Scheduler.next_state(current, **kwargs)
  end

  public

  # --- interval_for / the ladder ----------------------------------------

  test "interval ladder matches the plan exactly" do
    assert_equal [ 0, 1, 3, 7, 21, 60, 180 ], Scheduler::INTERVALS
    assert_equal 0,   Scheduler.interval_for(0)
    assert_equal 1,   Scheduler.interval_for(1)
    assert_equal 3,   Scheduler.interval_for(2)
    assert_equal 7,   Scheduler.interval_for(3)
    assert_equal 21,  Scheduler.interval_for(4)
    assert_equal 60,  Scheduler.interval_for(5)
    assert_equal 180, Scheduler.interval_for(6)
  end

  test "levels above the ladder top stay at +180d" do
    assert_equal 180, Scheduler.interval_for(7)
    assert_equal 180, Scheduler.interval_for(99)
  end

  test "durable? reflects the >=60d gold standard" do
    assert_not Scheduler.durable?(4) # 21d
    assert Scheduler.durable?(5)     # 60d
    assert Scheduler.durable?(6)     # 180d
  end

  # --- Correct: advancing the ladder ------------------------------------

  test "correct advances one level and schedules the next interval" do
    r = next_state({ level: 0 }, correct: true)
    assert_equal 1, r.level
    assert_equal 1, r.interval_days
    assert_equal 1, r.streak
    assert_equal 1, r.repetitions
    assert_equal 0, r.lapses
  end

  test "each correct climbs the whole ladder" do
    expectations = [
      [ 0, 1, 1 ],   # level_before, next_level, next_interval
      [ 1, 2, 3 ],
      [ 2, 3, 7 ],
      [ 3, 4, 21 ],
      [ 4, 5, 60 ],
      [ 5, 6, 180 ],
      [ 6, 7, 180 ]
    ]
    expectations.each do |before, after, interval|
      r = next_state({ level: before, streak: before }, correct: true)
      assert_equal after, r.level, "level #{before} -> #{after}"
      assert_equal interval, r.interval_days
      assert_equal before + 1, r.streak
    end
  end

  test "correct due date is reviewed_on + the new interval" do
    on = Date.new(2026, 1, 1)
    r = next_state({ level: 2 }, correct: true, reviewed_on: on) # -> level 3, +7d
    assert_equal Date.new(2026, 1, 8), r.due_on
  end

  # --- Incorrect: gentle step-down --------------------------------------

  test "incorrect steps down to relearning level 1 (+1d), not a hard reset" do
    r = next_state({ level: 5, streak: 5, lapses: 1 }, correct: false)
    assert_equal Scheduler::RELEARNING_LEVEL, r.level
    assert_equal 1, r.interval_days
    assert_equal 0, r.streak, "streak resets on a miss"
    assert_equal 2, r.lapses, "lapses increments"
    assert_equal "lapsed", r.state.to_s
  end

  test "incorrect increments repetitions and lapses" do
    r = next_state({ level: 3, repetitions: 4, lapses: 0 }, correct: false)
    assert_equal 5, r.repetitions
    assert_equal 1, r.lapses
  end

  test "incorrect due date is reviewed_on + 1 day" do
    on = Date.new(2026, 6, 1)
    r = next_state({ level: 4 }, correct: false, reviewed_on: on)
    assert_equal Date.new(2026, 6, 2), r.due_on
  end

  # --- State transitions on correct (non-mastery) -----------------------

  test "first correct from new moves into review, not mastered" do
    r = next_state({ level: 0 }, correct: true) # waited 0d
    assert_equal "review", r.state.to_s
    assert_nil r.mastered_at
  end

  test "correct after a <7d gap stays in review and is not mastered" do
    # level 1 means the gap just survived was interval_for(1) = 1 day.
    r = next_state({ level: 1, streak: 1 }, correct: true)
    assert_equal "review", r.state.to_s
    assert_nil r.mastered_at
    # level 2: survived 3 days — still under the 7-day gate.
    r = next_state({ level: 2, streak: 2 }, correct: true)
    assert_equal "review", r.state.to_s
    assert_nil r.mastered_at
  end

  # --- The mastery gate (plan §3) ---------------------------------------

  test "mastered on first correct recall AFTER a >=7-day gap via unbroken streak" do
    travel_to Time.zone.local(2026, 3, 10, 9, 0, 0) do
      # At level 3 the item was scheduled +7d and has now been recalled: the
      # survived gap (interval_before) is 7 days -> the mastery gate fires.
      r = next_state({ level: 3, streak: 3 }, correct: true)
      assert_equal "mastered", r.state.to_s
      assert_equal Time.current, r.mastered_at
      assert_equal 4, r.level
      assert_equal 21, r.interval_days
    end
  end

  test "not mastered until the 7-day gap is actually survived" do
    # Sitting AT level 3 (scheduled +7d) but not yet recalled is not mastery;
    # mastery needs the *correct recall after* that gap, i.e. answering from
    # level 3. Answering from level 2 (survived only 3d) is not enough.
    refute_equal "mastered", next_state({ level: 2 }, correct: true).state.to_s
    assert_equal "mastered", next_state({ level: 3 }, correct: true).state.to_s
  end

  test "durable interval (>=60d) is also mastered and stamped" do
    travel_to Time.zone.local(2026, 5, 1, 12) do
      r = next_state({ level: 5, streak: 5 }, correct: true) # survived 60d
      assert_equal "mastered", r.state.to_s
      assert_equal Time.current, r.mastered_at
      assert Scheduler.durable?(r.level - 1), "the gap survived was the 60d level"
    end
  end

  test "mastered_at is preserved (not overwritten) on subsequent correct recalls" do
    first  = Time.zone.local(2026, 1, 1, 8)
    later  = Time.zone.local(2026, 4, 1, 8)
    earned = next_state({ level: 3, streak: 3 }, correct: true, reviewed_at: first).mastered_at

    r = next_state(
      { level: 4, streak: 4, mastered_at: earned },
      correct: true, reviewed_at: later
    )
    assert_equal "mastered", r.state.to_s
    assert_equal earned, r.mastered_at, "keeps the original mastery timestamp"
  end

  test "a re-checked mastered item at a short interval keeps mastered status" do
    earned = Time.zone.local(2026, 1, 1, 8)
    # Contrived: a mastered item somehow at a low level, recalled correctly.
    r = next_state({ level: 1, mastered_at: earned }, correct: true)
    assert_equal "mastered", r.state.to_s
    assert_equal earned, r.mastered_at
  end

  # --- Lapse clears mastery (plan §3) -----------------------------------

  test "a miss demotes a mastered item and clears mastered_at" do
    earned = Time.zone.local(2026, 1, 1, 8)
    r = next_state(
      { level: 5, streak: 5, mastered_at: earned },
      correct: false
    )
    assert_equal "lapsed", r.state.to_s
    assert_nil r.mastered_at, "lapse clears the mastery stamp"
    assert_equal 1, r.level
    assert_equal 0, r.streak
  end

  test "mastery is re-earnable after a lapse climbs back to a >=7-day gap" do
    travel_to Time.zone.local(2026, 7, 1, 10) do
      # After lapse: level 1. Climb 1 -> 2 -> 3, then correct from level 3.
      s = next_state({ level: 1, streak: 0 }, correct: true) # -> level 2
      assert_nil s.mastered_at
      s2 = next_state({ level: s.level, streak: s.streak }, correct: true) # -> level 3
      assert_nil s2.mastered_at
      s3 = next_state({ level: s2.level, streak: s2.streak }, correct: true) # from 3 -> mastered
      assert_equal "mastered", s3.state.to_s
      assert_equal Time.current, s3.mastered_at
    end
  end
end
