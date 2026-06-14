require "test_helper"

class QuizSessionTest < ActiveSupport::TestCase
  test "valid with a subject scope" do
    assert quiz_sessions(:math_session).valid?
  end

  test "valid as an all-due session with no subject" do
    session = QuizSession.new(user: users(:owner), started_at: Time.current)
    assert session.valid?
    assert_nil session.subject
  end

  test "has many attempts, nullified on destroy" do
    session = quiz_sessions(:math_session)
    attempt = attempts(:good_attempt)
    assert_includes session.attempts, attempt

    session.destroy
    assert_nil attempt.reload.quiz_session_id, "attempt survives, link is nullified"
  end

  test "rejects a negative planned_count" do
    session = QuizSession.new(user: users(:owner), planned_count: -1)
    assert_not session.valid?
    assert_includes session.errors[:planned_count], "must be greater than or equal to 0"
  end
end
