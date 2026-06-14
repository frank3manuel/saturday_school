# frozen_string_literal: true

# Per-student SRS state for an assigned (non-owned) item — the HYBRID model's
# "other learner" home (plan §4.6, §15 D-state). A row mirrors the inline SRS
# columns on `items`, so the one pure Srs::Scheduler result applies identically
# whether it lands here or on the item itself.
#
# This is the privacy-critical surface, so ALL reads/writes of a non-owner's
# state route through here (and through Item#state_for / Item#srs_home_for). Rows
# are created EAGERLY (at assignment/enrollment time) so the due-query never has
# to LEFT-JOIN for a missing row.
class ReviewState < ApplicationRecord
  belongs_to :user
  belongs_to :item

  enum :state, { learning: 0, review: 1, mastered: 2, lapsed: 3 }, default: :learning

  validates :user_id, uniqueness: { scope: :item_id }
  validates :interval_days, :box, :streak, :repetitions, :lapses,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Not suspended — eligible to be scheduled/reviewed (mirrors Item.active).
  scope :active, -> { where(suspended: false) }
  # Due for review now (the hot assigned due-query, index-backed by
  # [user_id, suspended, due_at]).
  scope :due, ->(now = Time.current) { active.where(due_at: ..now) }

  # The centralized accessor (plan §4.6): fetch-or-create the (user, item) row.
  # Eager creation is the norm, but this stays idempotent so callers never crash
  # on a missing row.
  def self.for(user, item)
    find_or_create_by!(user_id: user.id, item_id: item.id)
  end
end
