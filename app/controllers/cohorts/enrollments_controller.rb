# Teacher-side roster management (plan §8.1, M6b): enroll a student into / remove
# a student from a cohort the teacher OWNS. Rooted at `taught_cohorts` so a
# teacher can never touch another teacher's roster (404, structurally).
#
# Removal flips status (never deletes) — the attempt log is retained while the
# student drops from the active queue (plan §15 D-leave).
class Cohorts::EnrollmentsController < ApplicationController
  before_action :set_cohort

  # Enroll a student by email (teacher-initiated). Idempotent: re-enrolling a
  # student who left reactivates their row rather than duplicating it.
  def create
    student = User.find_by(email_address: params[:email_address].to_s.strip.downcase)
    if student.nil? || !student.student?
      redirect_to @cohort, alert: "No student account with that email." and return
    end

    enrollment = Enrollment.find_or_initialize_by(cohort: @cohort, user: student)
    if enrollment.new_record?
      enrollment.save!
      enroll_existing_assignments(student)
    else
      enrollment.rejoin!
      enroll_existing_assignments(student)
    end
    redirect_to @cohort, notice: "#{student.email_address} enrolled."
  end

  # Remove a student from the active roster (flip status).
  def destroy
    enrollment = @cohort.enrollments.find(params[:id])
    enrollment.remove!
    redirect_to @cohort, notice: "Student removed from the roster."
  end

  private

  def set_cohort
    # Teacher's own cohorts only (plan §8.2). Authorize the roster role gate.
    @cohort = policy_scope(Cohort).find(params[:cohort_id])
    authorize @cohort, :manage_roster?
  end

  # Eagerly create this student's review_states for every live assignment in the
  # cohort (plan §4.6 — rows created at enrollment time so the due-query never
  # LEFT-JOINs for missing state).
  def enroll_existing_assignments(student)
    AssignmentEnroller.enroll_student(cohort: @cohort, student: student)
  end
end
