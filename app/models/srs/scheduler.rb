# frozen_string_literal: true

module Srs
  # Pure, side-effect-free, DB-free spaced-repetition scheduler (plan §5, §6).
  #
  # Implements the fixed Leitner-style day-interval ladder. There is no I/O and
  # no ActiveRecord here on purpose: every transition is exhaustively unit
  # testable, and `AnswerRecorder` / `srs:rebuild` are the only things that turn
  # a computed `Result` into persisted state.
  #
  # Intervals are calendar days. Callers pass `reviewed_on` as the learner's
  # *local* date so that "due tomorrow" flips at the user's midnight, not UTC
  # (plan §5). The scheduler returns `due_on` (a Date); the persistence layer
  # decides how to store it (we store an end-of-local-day `due_at`).
  class Scheduler
    # The one constant ladder (plan §5). Index == level.
    #   Level 0 (new/lapsed): 0d   — Learning, not yet spaced
    #   Level 1: +1d   → Young     (≥1-day survival)
    #   Level 2: +3d
    #   Level 3: +7d   → Maturing  (≥1-week; the mastery gate)
    #   Level 4: +21d
    #   Level 5: +60d  → Durable
    #   Level 6+: +180d            (continuous re-verification)
    INTERVALS = [ 0, 1, 3, 7, 21, 60, 180 ].freeze

    # The level a lapse steps an item back down to (plan §5: relearning at +1d).
    RELEARNING_LEVEL = 1

    # Mastery gates (plan §3). An item becomes `mastered` on its first correct
    # recall *after* having waited an interval ≥ this many days (reached via an
    # unbroken spaced streak — guaranteed because any lapse resets the climb).
    MASTERY_INTERVAL_DAYS = 7
    DURABLE_INTERVAL_DAYS = 60

    # Interval (in days) earned at a given level. Levels at/above the top of the
    # ladder all earn the final (long re-verification) interval.
    def self.interval_for(level)
      INTERVALS[level] || INTERVALS.last
    end

    # Presentation helper (plan §3): "durable" = a mastered item that has
    # survived a ≥60-day gap. The stored `state` enum stays `mastered`; this is
    # the gold-standard distinction the Progress dashboard (M4) draws.
    def self.durable?(level)
      interval_for(level) >= DURABLE_INTERVAL_DAYS
    end

    # The immutable outcome of grading one attempt. Mirrors the inline SRS
    # columns so callers can apply it directly.
    Result = Struct.new(
      :level, :interval_days, :streak, :repetitions, :lapses,
      :state, :due_on, :mastered_at, :reviewed_at,
      keyword_init: true
    )

    # The interval (in days) an item would earn for a given grade *without*
    # mutating anything — used to show the consequence on the grade buttons
    # ("Good → next in 12 days", plan §9) so honest grading is nudged. `correct`
    # advances one level; an incorrect grade drops to relearning.
    def self.projected_interval_days(level:, correct:)
      if correct
        interval_for(level.to_i + 1)
      else
        interval_for(RELEARNING_LEVEL)
      end
    end

    # Compute the next SRS state for one graded attempt.
    #
    # current:: a Hash/struct-like with the item's *current* (pre-attempt) state:
    #   :level, :streak, :repetitions, :lapses, :mastered_at.
    # correct:: whether the learner recalled it.
    # reviewed_on:: the learner's local Date of the review (default: today, UTC-
    #   based — real callers pass the user's local date).
    # reviewed_at:: the precise Time of the review (for last_reviewed_at /
    #   mastered_at stamps); default Time.current.
    def self.next_state(current, correct:, reviewed_on: Date.current, reviewed_at: Time.current)
      level_before    = (current[:level] || 0).to_i
      interval_before = interval_for(level_before)
      repetitions     = (current[:repetitions] || 0).to_i + 1
      lapses          = (current[:lapses] || 0).to_i
      mastered_at     = current[:mastered_at]

      if correct
        next_level    = level_before + 1
        streak        = (current[:streak] || 0).to_i + 1
        interval_days = interval_for(next_level)

        # Mastery gate (plan §3): the *delay just survived* (interval_before)
        # must be ≥ 7 days. Because a lapse resets the climb to Level 1, having
        # waited a 7-day gap implies an unbroken +1d → +3d → +7d streak.
        # `durable` (≥60d) is a presentation distinction; the stored enum is
        # still `mastered`, with mastered_at marking when it was first earned.
        if interval_before >= MASTERY_INTERVAL_DAYS
          state       = :mastered
          mastered_at ||= reviewed_at
        elsif mastered_at.present?
          # An already-mastered item re-checked at a short interval keeps its
          # mastered status and stamp.
          state       = :mastered
        else
          # Correct but the survived gap is still < 7 days: it's in the review
          # cycle, not yet durable. `learning` is reserved for never-recalled
          # items; one correct answer moves it into `review`.
          state       = :review
        end
      else
        # Lapse: gentle step-down to relearning, not a hard reset (plan §5).
        next_level    = RELEARNING_LEVEL
        streak        = 0
        lapses       += 1
        interval_days = interval_for(next_level)
        state         = :lapsed
        mastered_at   = nil
      end

      Result.new(
        level: next_level,
        interval_days: interval_days,
        streak: streak,
        repetitions: repetitions,
        lapses: lapses,
        state: state,
        due_on: reviewed_on + interval_days,
        mastered_at: mastered_at,
        reviewed_at: reviewed_at
      )
    end
  end
end
