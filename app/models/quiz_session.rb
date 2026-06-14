class QuizSession < ApplicationRecord
  # Nullable scope: a null subject means an "all due" session (plan §4.1).
  belongs_to :subject, optional: true
  # The owner (plan §4.5) — NOT NULL, FK-backed since M5's tighten migration.
  belongs_to :user
  has_many :attempts, dependent: :nullify

  # user_id is NOT NULL per plan §4.1 but has no `users` table to validate
  # against until M5; the presence guard is deferred to M5 alongside the FK and
  # the null: false flip (mirrors subjects.user_id from M1).

  validates :planned_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  scope :in_progress, -> { where(completed_at: nil) }

  def completed?
    completed_at.present?
  end

  # How many distinct items have been graded in this session (the numerator of
  # the "N/M complete" summary). The append-only attempt log is the source of
  # truth, so an undo (which deletes the last attempt) is reflected here for
  # free.
  def reviewed_count
    attempts.distinct.count(:item_id)
  end

  def complete!(now: Time.current)
    update!(completed_at: now) unless completed?
  end

  def scope_label
    subject&.name || "All due"
  end
end
