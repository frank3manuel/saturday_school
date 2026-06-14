# Teacher-facing cohort management (plan §8.1, M6b). A teacher creates and
# manages their own cohorts, views the roster, shares the join code, and
# enrolls/removes students. Authorization is role-gate THEN scope (plan §8.2):
# `policy_scope` roots every read at `current_user.taught_cohorts`, so another
# teacher's cohort 404s by being unreachable — not by an `if`.
class CohortsController < ApplicationController
  before_action :set_cohort, only: %i[show edit update destroy]

  def index
    authorize Cohort, :index?
    @cohorts = policy_scope(Cohort).active.order(:name)
  end

  def show
    # set_cohort already scoped to the teacher's own cohorts; authorize confirms
    # the role gate. The roster is the active enrollments only.
    authorize @cohort, :show?
    @enrollments = @cohort.enrollments.active.includes(:user).order(:id)
    @assignments = @cohort.assignments.live.includes(lesson: :subject).order(:id)
  end

  def new
    authorize Cohort, :create?
    @cohort = current_user.taught_cohorts.new
  end

  def create
    authorize Cohort, :create?
    @cohort = current_user.taught_cohorts.new(cohort_params)
    if @cohort.save
      redirect_to @cohort, notice: "Class created. Share the join code with your students."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @cohort, :update?
  end

  def update
    authorize @cohort, :update?
    if @cohort.update(cohort_params)
      redirect_to @cohort, notice: "Class updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @cohort, :destroy?
    @cohort.destroy
    redirect_to cohorts_path, notice: "Class deleted."
  end

  private

  # Root at the teacher's own cohorts (plan §8.2). A forged id for another
  # teacher's cohort is simply not in this relation → 404.
  def set_cohort
    @cohort = policy_scope(Cohort).find(params[:id])
  end

  def cohort_params
    params.require(:cohort).permit(:name, :description)
  end
end
