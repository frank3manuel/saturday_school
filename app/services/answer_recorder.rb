# frozen_string_literal: true

# Records one graded answer as a single, consistent unit of work (plan §6).
#
# In ONE DB transaction it:
#   1. appends an immutable `Attempt` (the source of truth, with the LEARNER's
#      user_id — server-authoritative, plan §11),
#   2. runs the pure `Srs::Scheduler` to compute the next state, and
#   3. writes that state to the LEARNER'S home for this item — the inline SRS
#      columns when the learner OWNS the item, or their `review_states` row when
#      it's assigned content (the hybrid branch, plan §4.6, §15 D-state).
#
# The owner/non-owner decision is NOT made here — it is delegated to the single
# centralized accessor `Item#srs_home_for(user)`. Both homes expose the same SRS
# columns, so the one scheduler result applies identically to either.
#
# There is no controller/HTTP here. Callers pass `correct`/`grade` (self-graded)
# and may attach a `quiz_session` and a measured `response_latency_ms`. `now` and
# `today` are injectable for tests and for honoring the learner's local date.
class AnswerRecorder
  Result = Struct.new(:item, :attempt, :home, keyword_init: true)

  # grade:: one of Attempt.grades (:missed/:hard/:good). `correct` is derived
  #   from it unless explicitly overridden.
  # user_id:: the LEARNER (server-authoritative). Required for the hybrid branch:
  #   it decides which home receives the state. Defaults to the item owner only
  #   for the legacy single-user path where it's nil.
  def self.call(item:, grade:, user_id: nil, quiz_session: nil,
                correct: nil, response_latency_ms: nil,
                now: Time.current, today: nil)
    new(
      item: item, grade: grade, user_id: user_id, quiz_session: quiz_session,
      correct: correct, response_latency_ms: response_latency_ms, now: now, today: today
    ).call
  end

  def initialize(item:, grade:, user_id:, quiz_session:, correct:, response_latency_ms:, now:, today:)
    @item                = item
    @grade               = grade.to_s
    @user_id             = user_id
    @quiz_session        = quiz_session
    @response_latency_ms = response_latency_ms
    @now                 = now
    @today               = today || @now.to_date
    @correct             = correct.nil? ? (@grade != "missed") : correct
  end

  def call
    home            = state_home
    interval_before = home.interval_days

    result = Srs::Scheduler.next_state(
      current_state(home),
      correct: @correct,
      reviewed_on: @today,
      reviewed_at: @now
    )

    attempt = nil
    home.with_lock do
      attempt = @item.attempts.create!(
        user_id: @user_id,
        quiz_session: @quiz_session,
        grade: @grade,
        correct: @correct,
        reviewed_at: @now,
        interval_before: interval_before,
        interval_after: result.interval_days,
        response_latency_ms: @response_latency_ms
      )

      apply!(home, result)
    end

    Result.new(item: @item, attempt: attempt, home: home)
  end

  private

  # The learner's state home for this item (the single centralized branch). When
  # no user_id is supplied we fall back to the item's inline columns (the legacy
  # solo path), which is also the owner's home.
  def state_home
    return @item if @user_id.nil?

    @item.srs_home_for(User.find(@user_id))
  end

  def current_state(home)
    {
      level: home.box,
      streak: home.streak,
      repetitions: home.repetitions,
      lapses: home.lapses,
      mastered_at: home.mastered_at
    }
  end

  def apply!(home, result)
    home.update!(
      box: result.level,
      interval_days: result.interval_days,
      streak: result.streak,
      repetitions: result.repetitions,
      lapses: result.lapses,
      state: result.state,
      due_at: due_at_for(result.due_on),
      last_reviewed_at: result.reviewed_at,
      mastered_at: result.mastered_at
    )
  end

  # The scheduler works in calendar days and returns a local Date. Store the
  # item as due at the start of that local day so it surfaces in the queue from
  # the user's local midnight onward (plan §5).
  def due_at_for(due_on)
    Time.zone.local(due_on.year, due_on.month, due_on.day)
  end
end
