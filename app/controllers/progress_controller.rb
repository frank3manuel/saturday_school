# Progress — the 4th destination (plan §9). Read-only, honest progress:
# stage-distribution bars (overall + per subject), an upcoming-review forecast
# calendar, durability stats, and a separately-labelled consistency streak.
#
# All data is computed on demand by ProgressReport (no jobs, index-backed,
# N+1-free across subjects → items), scoped to the signed-in user (plan §8.3).
class ProgressController < ApplicationController
  def show
    report = ProgressReport.new(user: current_user)

    @overall            = report.overall_distribution
    @by_subject         = report.distributions_by_subject
    @forecast           = report.forecast
    @overdue_count      = report.overdue_count
    @durability         = report.durability
    @total_items        = report.total_items
    @consistency_streak = report.consistency_streak
  end
end
