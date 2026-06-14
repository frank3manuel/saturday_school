class Attempt < ApplicationRecord
  # Append-only event log; the source of truth for SRS state (plan §4.1, §4.2).
  # Deliberately NO scheduling logic in callbacks — `AnswerRecorder` orchestrates
  # writing an Attempt and applying the resulting state in one transaction, and
  # `srs:rebuild` folds the log back into item state (plan §6).
  belongs_to :item
  belongs_to :quiz_session, optional: true
  # The learner who attempted (plan §4.5) — NOT NULL, FK-backed since M5's
  # tighten migration. The one sanctioned denormalization (§4.5).
  belongs_to :user

  # The 3-way self-grade (plan §9). `missed` is the only incorrect grade; `hard`
  # and `good` are both correct recalls. The boolean `correct` is the canonical
  # input to the scheduler and is set authoritatively by `AnswerRecorder`.
  enum :grade, { missed: 0, hard: 1, good: 2 }, default: :good

  # user_id is NOT NULL per plan §4.5 (the one sanctioned denormalization) but
  # has no `users` table until M5; presence/FK/null:false are deferred to M5's
  # backfill (mirrors subjects.user_id from M1).

  validates :correct, inclusion: { in: [ true, false ] }
  validates :reviewed_at, presence: true
  validates :interval_before, :interval_after,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :response_latency_ms,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  # Append-only: an attempt is a historical fact and must never be mutated.
  before_update do
    raise ActiveRecord::ReadOnlyRecord, "Attempt is append-only"
  end
end
