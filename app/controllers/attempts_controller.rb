# Grading actions inside a quiz session (plan §6, §9, §10).
#
# `create` records exactly one graded answer through AnswerRecorder (one
# Attempt + one consistent state update, in one transaction) and then
# auto-advances: a Turbo Stream swaps only the card frame to the next card (or
# the summary when the queue is exhausted).
#
# `destroy` is **undo last grade** — it removes the most recent attempt in this
# session, which rewinds the cursor (derived from the attempt log) and brings
# the previous card back. The SRS state for that item is rebuilt from its
# remaining attempts so the inline columns stay a faithful projection (plan §4.2).
class AttemptsController < ApplicationController
  before_action :set_quiz_session

  GRADES = %w[missed hard good].freeze

  def create
    item_ids = plan_ids
    cursor   = @quiz_session.reviewed_count

    # Guard against double-submits / a stale card: only grade the item the
    # learner is actually looking at.
    if cursor >= item_ids.length || item_ids[cursor] != params[:item_id].to_i
      return redirect_to quiz_session_path(@quiz_session)
    end

    # Reviewable = personal ∪ live-assigned (plan §4.6). A forged id for content
    # the learner can't review (someone else's personal deck) is not in this
    # relation → 404, never graded.
    item  = Item.reviewable_for(current_user).find(item_ids[cursor])
    grade = params[:grade].to_s
    return head :unprocessable_entity unless GRADES.include?(grade)

    AnswerRecorder.call(
      item: item,
      grade: grade.to_sym,
      # Server-authoritative: the learner is the signed-in user, never a param
      # (plan §11) — a student can't grade into another's state.
      user_id: current_user.id,
      quiz_session: @quiz_session,
      response_latency_ms: latency
    )

    advance
  end

  # Undo the last grade in this session.
  def destroy
    last = @quiz_session.attempts.order(:id).last
    if last
      item    = last.item
      learner = last.user # the learner whose state must be re-projected
      last.destroy
      # Re-project from the remaining attempts into THAT learner's home (inline
      # columns if they own the item, else their review_states row, plan §4.6).
      Srs::Rebuild.replay(item, user: learner)
    end
    advance
  end

  private

  # Render the next card (or the summary) by re-rendering the session frame.
  def advance
    @quiz_session.reload
    @item_ids = plan_ids
    @cursor   = @quiz_session.reviewed_count

    if @cursor >= @item_ids.length
      respond_to do |format|
        format.turbo_stream { render "quiz_sessions/finish" }
        format.html { redirect_to summary_quiz_session_path(@quiz_session) }
      end
      return
    end

    @item            = Item.reviewable_for(current_user).find(@item_ids[@cursor])
    @home            = @item.srs_home_for(current_user)
    @origin          = origin_for(@item.id)
    @position        = @cursor + 1
    @total           = @item_ids.length
    @can_undo        = @cursor.positive?
    @good_interval   = projected_days(@home, correct: true)
    @hard_interval   = projected_days(@home, correct: true)
    @missed_interval = projected_days(@home, correct: false)

    respond_to do |format|
      # Both `create` (grade) and `destroy` (undo) advance the queue, so render
      # the shared `advance` template explicitly rather than the action default.
      format.turbo_stream { render "quiz_sessions/advance" }
      format.html { redirect_to quiz_session_path(@quiz_session) }
    end
  end

  # Owner-scoped (plan §8.3): grading into another user's session 404s.
  def set_quiz_session
    @quiz_session = current_user.quiz_sessions.find(params[:quiz_session_id])
  end

  # `home` is the learner's state record (Item or ReviewState) — both expose box.
  def projected_days(home, correct:)
    Srs::Scheduler.projected_interval_days(level: home.box, correct: correct)
  end

  def latency
    ms = params[:response_latency_ms]
    ms.present? ? ms.to_i : nil
  end

  def plan_ids
    session["quiz_plan_#{@quiz_session.id}"] || []
  end

  # Provenance tag (:personal / :assigned) for the current card (plan §6).
  def origin_for(item_id)
    (session["quiz_origins_#{@quiz_session.id}"] || {})[item_id.to_s]&.to_sym || :personal
  end
end
