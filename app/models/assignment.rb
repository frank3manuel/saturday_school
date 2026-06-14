# frozen_string_literal: true

# A teacher's lesson assigned to a cohort (plan §4.6, §15 D-grain — LESSON
# grain). This join is the ONLY window a teacher has into a student's data: a
# personal item has no assignment row, so personal content can never surface in
# a teacher's result set (plan §8.2 — privacy as a property of the join graph).
#
# Authorization is DOUBLE-CHECKED (plan §11): the model validates that
# `assigned_by` owns BOTH the lesson (via subject) AND the cohort, and AssignmentPolicy#create?
# re-checks the same — a forged lesson_id/cohort_id can't link another teacher's
# content. `withdrawn_at` soft-stops without destroying per-student state.
class Assignment < ApplicationRecord
  belongs_to :cohort, inverse_of: :assignments
  belongs_to :lesson
  belongs_to :assigner, class_name: "User", foreign_key: :assigned_by,
                        inverse_of: :authored_assignments

  has_one :subject, through: :lesson
  has_many :items, through: :lesson

  validates :lesson_id, uniqueness: { scope: :cohort_id }
  validates :assigned_at, presence: true
  validate :assigner_owns_lesson_and_cohort

  before_validation :stamp_assigned_at, on: :create

  scope :live, -> { where(withdrawn_at: nil) }

  def withdrawn?
    withdrawn_at.present?
  end

  def withdraw!(now: Time.current)
    update!(withdrawn_at: now) unless withdrawn?
  end

  private

  # The model half of the double-checked assignment authorization (plan §11). An
  # assignment is only valid if the assigning teacher owns BOTH ends.
  def assigner_owns_lesson_and_cohort
    return if assigner.nil?

    unless lesson && lesson.subject&.user_id == assigned_by
      errors.add(:lesson, "must be one you own")
    end
    unless cohort && cohort.teacher_id == assigned_by
      errors.add(:cohort, "must be one you teach")
    end
  end

  def stamp_assigned_at
    self.assigned_at ||= Time.current
  end
end
