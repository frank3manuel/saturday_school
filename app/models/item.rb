class Item < ApplicationRecord
  belongs_to :lesson
  # The append-only source of truth for this item's SRS state (plan §4.1).
  has_many :attempts, dependent: :destroy
  # Per-student SRS state for assigned (non-owner) learners (the hybrid model,
  # plan §4.6). The owner's state stays inline on this row.
  has_many :review_states, dependent: :destroy
  has_one :subject, through: :lesson

  enum :item_type, { free_recall: 0 }, default: :free_recall
  enum :state, { learning: 0, review: 1, mastered: 2, lapsed: 3 }, default: :learning

  validates :prompt, presence: true
  validates :answer, presence: true
  validates :interval_days, :box, :streak, :repetitions, :lapses,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Not suspended — eligible to be scheduled/reviewed.
  scope :active, -> { where(suspended: false) }

  # Items a given user is entitled to REVIEW (plan §8.3, §4.6): their own
  # personal items UNION the items of lessons currently LIVE-assigned to a cohort
  # they are ACTIVELY enrolled in. This is the authorization boundary for the
  # quiz loop — a student can only grade an item reachable here (their own, or
  # one genuinely assigned to them); a forged id for anything else is excluded.
  # Personal decks of OTHER users are never reachable (no assignment row).
  scope :reviewable_for, ->(user) do
    personal = user.items.select(:id)
    assigned_lessons = Assignment.live
      .where(cohort_id: Enrollment.active.where(user_id: user.id).select(:cohort_id))
      .select(:lesson_id)
    where("items.id IN (#{personal.to_sql}) OR items.lesson_id IN (#{assigned_lessons.to_sql})")
  end
  # Due for review now. Real scheduling logic lands in M2; for M1 "due" just
  # means an active item whose due_at has passed.
  scope :due, ->(now = Time.current) { active.where(due_at: ..now) }
  # `mastered` and `learning` scopes are provided automatically by the `state`
  # enum (Item.mastered, Item.learning), so they are not redefined here.

  # The longest real gap (in days) this item has been *correctly* recalled
  # across — the survival that earns a display stage (plan §3). The append-only
  # Attempt log is the source of truth: it's the max `interval_before` over the
  # item's correct attempts. Returns 0 when never correctly recalled.
  #
  # NOTE: this issues a query per item. For lists/dashboards use the bulk
  # MasteryStage aggregation (Progress) rather than calling this in a loop.
  def longest_survived_gap_days
    attempts.where(correct: true).maximum(:interval_before).to_i
  end

  # This item's honest display stage (one of MasteryStage::STAGES). The single
  # mapping reused by the Library chip, quiz copy, and the dashboard.
  def display_stage
    correct = attempts.where(correct: true).exists?
    MasteryStage.from(recalled: correct, survived_days: longest_survived_gap_days)
  end

  # --- The centralized owner-vs-learner state branch (plan §4.6, §15 D-state) --
  #
  # THE single, tested place that decides where a given user's SRS state for this
  # item lives. This is the privacy-critical surface, so AnswerRecorder,
  # SessionBuilder, and Srs::Rebuild all route reads/writes through it rather
  # than re-deciding owner-vs-learner anywhere else.
  #
  #   - OWNER (the user who owns this item's subject)  → the inline columns on the
  #     Item itself (self). The solo/personal path, unchanged.
  #   - ANY OTHER learner (assigned student)           → their review_states row.
  #
  # `srs_home_for` returns the *record* whose SRS columns to read/write (an Item or
  # a ReviewState — both expose box/streak/state/due_at/... identically).
  def owner_id
    subject&.user_id
  end

  def owned_by?(user)
    owner_id == user.id
  end

  # The state-bearing record for `user`. Owner → self; assigned learner → their
  # (eagerly-created, idempotent) ReviewState row.
  def srs_home_for(user)
    owned_by?(user) ? self : ReviewState.for(user, self)
  end

  # The user's persisted SRS state for this item as a plain hash, regardless of
  # where it's stored — the single read path used by SessionBuilder/progress.
  def state_for(user)
    home = srs_home_for(user)
    {
      box: home.box, interval_days: home.interval_days, streak: home.streak,
      repetitions: home.repetitions, lapses: home.lapses, state: home.state,
      due_at: home.due_at, last_reviewed_at: home.last_reviewed_at,
      mastered_at: home.mastered_at, suspended: home.suspended
    }
  end
end
