# frozen_string_literal: true

# A student's membership in a cohort (plan §4.6, §15 D-leave). Leaving flips
# `status`, never deletes — the attempt log is retained while the student drops
# from the active roster/queue. The student is always a `student`-role user
# joining by code; the teacher enrolls/removes from the roster.
class Enrollment < ApplicationRecord
  belongs_to :cohort, inverse_of: :enrollments
  belongs_to :user, inverse_of: :enrollments

  enum :status, { active: "active", left: "left", removed: "removed" }, default: "active"

  validates :user_id, uniqueness: { scope: :cohort_id }
  validates :joined_at, presence: true

  before_validation :stamp_joined_at, on: :create

  scope :for_roster, -> { active.order(:id) }

  # Leave (student-initiated) / remove (teacher-initiated): flip status + stamp
  # ended_at. Idempotent — re-leaving doesn't re-stamp.
  def leave!(now: Time.current)
    end_membership!(:left, now: now)
  end

  def remove!(now: Time.current)
    end_membership!(:removed, now: now)
  end

  # Rejoin (plan §12: rejoin works) — reactivate a left/removed enrollment rather
  # than creating a duplicate (the unique index forbids a second row).
  def rejoin!(now: Time.current)
    update!(status: :active, ended_at: nil, joined_at: now)
  end

  private

  def end_membership!(new_status, now:)
    return if left? || removed?

    update!(status: new_status, ended_at: now)
  end

  def stamp_joined_at
    self.joined_at ||= Time.current
  end
end
