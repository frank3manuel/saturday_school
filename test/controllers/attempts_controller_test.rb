require "test_helper"

class AttemptsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @subject = users(:owner).subjects.create!(name: "Geo")
    @lesson  = @subject.lessons.create!(title: "Capitals")
    @a = @lesson.items.create!(prompt: "France?", answer: "Paris",
                               state: :review, box: 1, interval_days: 1, due_at: 3.days.ago)
    @b = @lesson.items.create!(prompt: "Spain?", answer: "Madrid",
                               state: :review, box: 1, interval_days: 1, due_at: 1.day.ago)
    post quiz_sessions_path, params: { subject_id: @subject.id }
    @qs = QuizSession.last
  end

  test "one grade POST writes exactly one Attempt and one consistent state update" do
    box_before = @a.box

    assert_difference -> { Attempt.count }, 1 do
      post quiz_session_attempt_path(@qs),
           params: { item_id: @a.id, grade: "good", response_latency_ms: 1500 },
           as: :turbo_stream
    end
    assert_response :success

    attempt = Attempt.order(:id).last
    assert_equal @a.id, attempt.item_id
    assert_equal "good", attempt.grade
    assert attempt.correct
    assert_equal @qs.id, attempt.quiz_session_id
    assert_equal 1500, attempt.response_latency_ms

    @a.reload
    assert_equal box_before + 1, @a.box, "item state advanced exactly once"
    assert_operator @a.due_at, :>, Time.current, "next due moved into the future"
  end

  test "grading auto-advances by swapping only the card frame to the next item" do
    post quiz_session_attempt_path(@qs),
         params: { item_id: @a.id, grade: "good" }, as: :turbo_stream
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", @response.media_type
    assert_select "turbo-stream[action=replace][target=quiz_card]"
    # Next card is the second-most-overdue item (@b).
    assert_select ".quiz__prompt", text: /Spain/
  end

  test "the last grade exhausts the queue and offers the summary" do
    post quiz_session_attempt_path(@qs), params: { item_id: @a.id, grade: "good" }, as: :turbo_stream
    post quiz_session_attempt_path(@qs), params: { item_id: @b.id, grade: "good" }, as: :turbo_stream
    assert_response :success
    assert_select ".quiz__done-headline"
    assert_select "a[href=?]", summary_quiz_session_path(@qs)
  end

  test "stale or mismatched item_id does not double-grade" do
    # Two POSTs for the SAME (already-graded) item: the second is ignored.
    post quiz_session_attempt_path(@qs), params: { item_id: @a.id, grade: "good" }, as: :turbo_stream
    assert_no_difference -> { Attempt.count } do
      post quiz_session_attempt_path(@qs), params: { item_id: @a.id, grade: "good" }, as: :turbo_stream
    end
  end

  test "undo removes the last attempt and re-projects the item state" do
    post quiz_session_attempt_path(@qs), params: { item_id: @a.id, grade: "good" }, as: :turbo_stream
    @a.reload
    assert_equal 2, @a.box

    assert_difference -> { Attempt.count }, -1 do
      delete quiz_session_attempt_path(@qs), as: :turbo_stream
    end
    assert_response :success

    @a.reload
    assert_equal 0, @a.box, "state rolled back to the new-item baseline"
    assert_equal 0, @a.repetitions
    # The card frame now shows @a again (the cursor rewound).
    assert_select ".quiz__prompt", text: /France/
  end

  test "rejects an unknown grade" do
    post quiz_session_attempt_path(@qs), params: { item_id: @a.id, grade: "bogus" }, as: :turbo_stream
    assert_response :unprocessable_entity
  end

  # N+1 protection lock (plan §12): rendering a card must not scale queries with
  # the number of items/lessons in the queue.
  test "rendering a session card stays within a small, flat query budget" do
    5.times do |i|
      @lesson.items.create!(prompt: "extra#{i}", answer: "x", state: :review,
                            box: 1, interval_days: 1, due_at: (i + 4).days.ago)
    end
    post quiz_sessions_path, params: { subject_id: @subject.id }
    qs = QuizSession.last

    queries = count_queries { get quiz_session_path(qs) }
    assert_response :success
    assert_operator queries, :<=, 6,
      "session card render should be a small flat number of queries, got #{queries}"
  end

  private

  def count_queries(&block)
    count = 0
    counter = ->(*, payload) do
      count += 1 unless payload[:name] == "SCHEMA" || payload[:sql] =~ /^\s*(BEGIN|COMMIT|TRANSACTION|SAVEPOINT|RELEASE)/i
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
