# frozen_string_literal: true

module Srs
  # Folds the append-only attempt log back into SRS state (plan §6 — the
  # projection-invariant escape hatch behind `rake srs:rebuild`).
  #
  # The attempt log is per (user, item) — each Attempt carries the LEARNER's
  # user_id — so a rebuild replays each (user, item) group through the same pure
  # `Srs::Scheduler` that `AnswerRecorder` uses and writes the result to THAT
  # learner's home: the item's inline columns when the learner owns it, else
  # their `review_states` row (the hybrid model, plan §4.6, §15 D-state). Because
  # both the live path and the rebuild share one scheduler and use each attempt's
  # own `reviewed_at`, a rebuild is deterministic and must equal the live-recorded
  # state — guarded for BOTH the personal and assigned paths (plan §12).
  class Rebuild
    # Replay every item (or a given subset), across ALL learners who have
    # attempts on each item. Returns the number of (item, learner) homes touched.
    def self.call(items: Item.all)
      new(items).call
    end

    # Re-project ONE (item, learner) home from that learner's remaining attempts.
    # Used by "undo last grade". `user` defaults to the item owner (the legacy
    # solo path) → inline columns.
    def self.replay(item, user: nil)
      new([ item ]).replay(item, user: user)
    end

    def initialize(items)
      @items = items
    end

    def call
      touched = 0
      @items.find_each do |item|
        # Always rebuild the OWNER's inline home (resets a no-attempt item to the
        # new-item baseline — the bug-recovery guarantee for the personal path).
        replay(item, user: nil)
        touched += 1

        # Plus each NON-owner learner who has attempts on this item: their own
        # review_states row rebuilt from their own attempts (the assigned path).
        owner_id = item.owner_id
        item.attempts.distinct.pluck(:user_id).each do |user_id|
          next if user_id == owner_id # owner already handled via the inline home

          replay(item, user: User.find(user_id))
          touched += 1
        end
      end
      touched
    end

    # Replay a single learner's attempts on an item into their state home.
    def replay(item, user: nil)
      home     = home_for(item, user)
      learner  = user || home_owner(item, home)
      state    = blank_state
      attempts = item.attempts.where(user_id: learner&.id).order(:reviewed_at, :id)

      attempts.each do |attempt|
        result = Srs::Scheduler.next_state(
          state,
          correct: attempt.correct,
          reviewed_on: attempt.reviewed_at.to_date,
          reviewed_at: attempt.reviewed_at
        )
        state = state_from(result)
      end

      home.transaction { write!(home, state) }
    end

    private

    # The learner's state home (centralized branch). With no user we fall back to
    # the item's inline columns (the owner's home / legacy solo path).
    def home_for(item, user)
      return item if user.nil?

      item.srs_home_for(user)
    end

    # When replay was called without a user, the home is the item itself; scope
    # its attempts to the owner so a rebuild of the inline columns uses only the
    # owner's attempts (assigned learners' attempts live in their own rows).
    def home_owner(item, home)
      return nil if home.is_a?(ReviewState) # already user-scoped via home.user

      owner_id = item.owner_id
      owner_id && User.find_by(id: owner_id)
    end

    # A never-reviewed item resets to the new-item baseline.
    def blank_state
      { level: 0, interval_days: 0, streak: 0, repetitions: 0, lapses: 0,
        state: :learning, due_at: nil, last_reviewed_at: nil, mastered_at: nil }
    end

    def state_from(result)
      {
        level: result.level,
        interval_days: result.interval_days,
        streak: result.streak,
        repetitions: result.repetitions,
        lapses: result.lapses,
        state: result.state,
        due_at: due_at_for(result.due_on),
        last_reviewed_at: result.reviewed_at,
        mastered_at: result.mastered_at
      }
    end

    def write!(home, state)
      home.update!(
        box: state[:level],
        interval_days: state[:interval_days],
        streak: state[:streak],
        repetitions: state[:repetitions],
        lapses: state[:lapses],
        state: state[:state],
        due_at: state[:due_at],
        last_reviewed_at: state[:last_reviewed_at],
        mastered_at: state[:mastered_at]
      )
    end

    def due_at_for(due_on)
      return nil if due_on.nil?

      Time.zone.local(due_on.year, due_on.month, due_on.day)
    end
  end
end
