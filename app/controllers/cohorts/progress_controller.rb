# Honest teacher class-aggregate progress for one cohort (plan §9, §3, M6d).
# Teacher-only (own cohorts), strictly scoped to assigned content. NEVER a
# fabricated "% mastered" — a stacked stage distribution only (plan §3).
class Cohorts::ProgressController < ApplicationController
  def show
    # Teacher's own cohorts only; another teacher's cohort 404s structurally.
    @cohort = policy_scope(Cohort).find(params[:cohort_id])
    authorize @cohort, :show?
    @report = CohortProgressReport.new(cohort: @cohort)
  end
end
