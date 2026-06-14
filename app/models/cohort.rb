# frozen_string_literal: true

# A Cohort (the "Class", plan §4.6). Owned by a teacher; students join by an
# opaque high-entropy code (enumeration-resistant — plan §11). The teacher's
# reads always root at `current_user.taught_cohorts`, so another teacher's
# cohort is structurally unreachable (plan §8.2).
class Cohort < ApplicationRecord
  belongs_to :teacher, class_name: "User", inverse_of: :taught_cohorts

  has_many :enrollments, dependent: :destroy
  has_many :students, through: :enrollments, source: :user
  # Only the active roster (excludes left/removed) — the queue/roster baseline.
  has_many :active_enrollments, -> { where(status: "active") },
           class_name: "Enrollment", inverse_of: :cohort
  has_many :active_students, through: :active_enrollments, source: :user

  has_many :assignments, dependent: :destroy
  # Only live (non-withdrawn) assignments — what students actually receive.
  has_many :active_assignments, -> { where(withdrawn_at: nil) },
           class_name: "Assignment", inverse_of: :cohort
  has_many :lessons, through: :assignments

  validates :name, presence: true
  validates :join_code, presence: true, uniqueness: true
  # The teacher must actually be allowed to teach (plan §4.6).
  validate :teacher_is_staff

  before_validation :ensure_join_code, on: :create

  scope :active, -> { where(archived_at: nil) }

  JOIN_CODE_LENGTH = 10
  # Crockford-ish base32 alphabet minus ambiguous chars (no I, L, O, U) so a
  # shared code is easy to read aloud and type (plan §4.6).
  JOIN_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTVWXYZ23456789"

  def archived?
    archived_at.present?
  end

  # Generate a fresh, collision-checked opaque join code.
  def self.generate_join_code
    loop do
      code = Array.new(JOIN_CODE_LENGTH) { JOIN_CODE_ALPHABET.chars.sample(random: SecureRandom) }.join
      break code unless exists?(join_code: code)
    end
  end

  private

  def ensure_join_code
    self.join_code ||= self.class.generate_join_code
  end

  def teacher_is_staff
    return if teacher.nil?

    errors.add(:teacher, "must be a teacher or admin") unless teacher.staff?
  end
end
