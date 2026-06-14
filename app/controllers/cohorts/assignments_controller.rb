# Teacher assigns / withdraws their own lessons to/from a cohort they own
# (plan §8.1, M6c). Double-checked authorization (plan §11): AssignmentPolicy#create?
# requires the teacher own BOTH the cohort and the lesson, and the Assignment
# model re-validates the same — a forged lesson_id/cohort_id can't link another
# teacher's content.
#
# On assignment we EAGERLY create a review_states row for every active enrollee ×
# each lesson item (plan §4.6), so the assigned due-query never LEFT-JOINs for a
# missing row.
#
# "Assign whole subject" is sugar: a subject_id expands server-side into one
# assignment per lesson (plan §4.6, §15 D-grain).
class Cohorts::AssignmentsController < ApplicationController
  before_action :set_cohort

  def create
    lessons = resolve_lessons
    if lessons.empty?
      redirect_to @cohort, alert: "Select a lesson you own to assign." and return
    end

    created = 0
    ActiveRecord::Base.transaction do
      lessons.each do |lesson|
        assignment = @cohort.assignments.find_or_initialize_by(lesson: lesson)
        # Re-assign a previously-withdrawn lesson by clearing the soft-stop.
        if assignment.persisted?
          assignment.update!(withdrawn_at: nil) if assignment.withdrawn?
        else
          assignment.assigner = current_user
          authorize assignment, :create? # double-check (Pundit half)
          assignment.save! # model half re-validates ownership of both ends
          created += 1
        end
        AssignmentEnroller.enroll_assignment(assignment)
      end
    end

    redirect_to @cohort, notice: assign_notice(created, lessons.size)
  end

  # Withdraw (soft-stop) — preserves per-student state/history (plan §4.6).
  def destroy
    assignment = @cohort.assignments.find(params[:id])
    authorize assignment, :destroy?
    assignment.withdraw!
    redirect_to @cohort, notice: "Lesson withdrawn. Students keep their progress."
  end

  private

  def set_cohort
    # Teacher's own cohorts only — another teacher's cohort 404s structurally.
    @cohort = policy_scope(Cohort).find(params[:cohort_id])
  end

  # A single lesson, or every lesson of a subject ("assign whole subject" sugar).
  # Both are filtered to the teacher's OWN content, so a forged id yields nothing
  # (and the model/policy would reject it anyway).
  def resolve_lessons
    if params[:subject_id].present?
      subject = current_user.subjects.find_by(id: params[:subject_id])
      subject ? subject.lessons.to_a : []
    elsif params.dig(:assignment, :lesson_id).present? || params[:lesson_id].present?
      lesson_id = params.dig(:assignment, :lesson_id).presence || params[:lesson_id]
      lesson = Lesson.where(subject_id: current_user.subjects.select(:id)).find_by(id: lesson_id)
      lesson ? [ lesson ] : []
    else
      []
    end
  end

  def assign_notice(created, total)
    if created.zero?
      "Already assigned."
    elsif total == 1
      "Lesson assigned."
    else
      "Assigned #{created} #{'lesson'.pluralize(created)}."
    end
  end
end
