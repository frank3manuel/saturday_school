class User < ApplicationRecord
  has_secure_password

  # Exactly one role per account (plan §4.6, D-roles). Default student; every
  # role keeps the full personal-learning baseline. Stored as a string with a DB
  # CHECK constraint. Roles aren't enforced until M6, but the column is live now.
  enum :role, { student: "student", teacher: "teacher", admin: "admin" }, default: "student"

  # Account-owned content. All dependent: :destroy + DB cascade so deleting an
  # account fully cleans up the user's data (plan §4.5, the "your data is yours"
  # promise). Lessons/items derive ownership through the subject chain — no
  # denormalized user_id on them.
  has_many :sessions, dependent: :destroy
  has_many :subjects, dependent: :destroy
  has_many :quiz_sessions, dependent: :destroy
  has_many :attempts, dependent: :destroy
  has_many :lessons, through: :subjects
  has_many :items, through: :lessons

  # --- Classroom (M6) ------------------------------------------------------
  # Cohorts this user teaches (the teacher's root for all class-scoped reads —
  # plan §8.2: a teacher's visibility starts at `taught_cohorts`, so another
  # teacher's cohort is simply unreachable). FK on cohorts is on_delete: :restrict,
  # so a teacher with live cohorts can't be deleted (handled with a friendly
  # message, not a 500). dependent: :restrict_with_error enforces the same in AR.
  has_many :taught_cohorts, class_name: "Cohort", foreign_key: :teacher_id,
                            dependent: :restrict_with_error, inverse_of: :teacher
  # Enrollments where this user is the student; leaving flips status, never deletes.
  has_many :enrollments, dependent: :destroy
  has_many :enrolled_cohorts, through: :enrollments, source: :cohort
  # Per-student SRS state for assigned (non-owned) content (the hybrid model,
  # plan §4.6). Cascades on account deletion.
  has_many :review_states, dependent: :destroy

  # Lessons this user has assigned (as a teacher) — the audit `assigned_by` side.
  has_many :authored_assignments, class_name: "Assignment", foreign_key: :assigned_by,
                                  dependent: :restrict_with_error, inverse_of: :assigner

  # Case-insensitive email (plan §4.4): normalize before validation/save so the
  # unique index does the rest. Applies to lookups via find_by too.
  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true,
            uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }
  # NIST-style: favor length over composition (plan §11). allow_nil so an account
  # update that doesn't touch the password isn't forced to re-supply it.
  validates :password, length: { minimum: 8 }, allow_nil: true

  # Self-verifying, expiring password-reset token (plan §4.4). It is bound to the
  # password salt, so changing the password auto-invalidates any outstanding
  # token — no reset-token columns to manage.
  generates_token_for :password_reset, expires_in: 15.minutes do
    password_salt&.last(10)
  end

  def verified?
    verified_at.present?
  end

  # Roles that may teach/own cohorts and assign content (plan §8.1: teacher and
  # admin both carry the teaching powers; every role keeps the personal baseline).
  def staff?
    teacher? || admin?
  end
end
