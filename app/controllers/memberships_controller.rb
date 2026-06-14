# Student self-service classroom membership (plan §8.1, M6b): "my classes",
# join-by-code, and leave. This is the student side — every action operates only
# on the current user's own enrollments (association-scoped, like personal CRUD;
# no Pundit ceremony needed since there's no cross-user read here).
#
# Join-by-code is enumeration-safe (plan §11, §12): an invalid or already-handled
# code returns the SAME generic message as success-adjacent failures, so a
# guesser learns nothing about which codes exist.
class MembershipsController < ApplicationController
  # "My classes" — the student's active enrollments.
  def index
    @enrollments = current_user.enrollments.active
                               .includes(cohort: :teacher).order(:id)
  end

  # Join by code. Generic failure message regardless of why it failed (unknown
  # code, archived class) — enumeration-safe.
  def create
    code = params[:join_code].to_s.strip.upcase
    cohort = Cohort.active.find_by(join_code: code)

    if cohort.nil?
      redirect_to memberships_path, alert: generic_join_failure and return
    end

    enrollment = Enrollment.find_or_initialize_by(cohort: cohort, user: current_user)
    if enrollment.new_record?
      enrollment.save!
    else
      enrollment.rejoin!
    end
    # Eagerly create this student's review_states for the cohort's live
    # assignments (plan §4.6).
    AssignmentEnroller.enroll_student(cohort: cohort, student: current_user)

    redirect_to memberships_path, notice: "You've joined #{cohort.name}."
  end

  # Leave a class (flip status, never delete — attempts retained, plan §15
  # D-leave). Scoped to the student's own enrollments.
  def destroy
    enrollment = current_user.enrollments.find(params[:id])
    enrollment.leave!
    redirect_to memberships_path, notice: "You've left #{enrollment.cohort.name}."
  end

  private

  def generic_join_failure
    "That code didn't match an open class. Check it with your teacher and try again."
  end
end
