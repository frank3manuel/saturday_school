require "test_helper"

class QuizSessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:owner)
    @subject = @user.subjects.create!(name: "Geo")
    @lesson  = @subject.lessons.create!(title: "Capitals")
    @a = @lesson.items.create!(prompt: "France?", answer: "Paris",
                               state: :review, box: 1, interval_days: 1, due_at: 3.days.ago)
    @b = @lesson.items.create!(prompt: "Spain?", answer: "Madrid",
                               state: :review, box: 1, interval_days: 1, due_at: 1.day.ago)
  end

  test "starting a review builds a session and lands on the first card" do
    assert_difference -> { QuizSession.count }, 1 do
      post quiz_sessions_path, params: { subject_id: @subject.id }
    end
    qs = QuizSession.last
    assert_equal @subject, qs.subject
    assert_redirected_to quiz_session_path(qs)

    follow_redirect!
    assert_response :success
    assert_select "turbo-frame#quiz_card"
    # Most-overdue first: @a (3d) before @b (1d).
    assert_select ".quiz__prompt", text: /France/
  end

  test "nothing due redirects home with a calm notice" do
    Item.update_all(due_at: 5.days.from_now)
    post quiz_sessions_path, params: { subject_id: @subject.id }
    assert_redirected_to root_path
    assert_equal "Nothing due right now.", flash[:notice]
  end

  test "show redirects to summary when every planned item is done" do
    post quiz_sessions_path, params: { subject_id: @subject.id }
    qs = QuizSession.last
    # Grade both planned items.
    AnswerRecorder.call(item: @a, grade: :good, user_id: @user.id, quiz_session: qs)
    AnswerRecorder.call(item: @b, grade: :good, user_id: @user.id, quiz_session: qs)

    get quiz_session_path(qs)
    assert_redirected_to summary_quiz_session_path(qs)
  end

  test "finishing early lands on the summary without grading remaining items" do
    post quiz_sessions_path, params: { subject_id: @subject.id }
    qs = QuizSession.last

    assert_no_difference -> { Attempt.count } do
      post finish_quiz_session_path(qs)
    end
    assert_redirected_to summary_quiz_session_path(qs)
    assert qs.reload.completed?
  end

  test "summary reports N of M complete" do
    post quiz_sessions_path, params: { subject_id: @subject.id }
    qs = QuizSession.last
    AnswerRecorder.call(item: @a, grade: :good, user_id: @user.id, quiz_session: qs)

    get summary_quiz_session_path(qs)
    assert_response :success
    assert_select ".summary__count", text: "1/2 complete"
  end
end
