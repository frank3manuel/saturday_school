require "test_helper"

# The cross-user 404 ownership matrix (plan §8.3, §12). User A (the signed-in
# owner) must NOT be able to reach user B's records by guessing their ids: every
# controller scopes through `current_user`, so B's content is simply not found.
class OwnershipTest < ActionDispatch::IntegrationTest
  setup do
    # Signed in as the owner (global setup). Build a separate user "other" with a
    # full content chain that the owner must never reach.
    @other      = users(:other)
    @subject    = @other.subjects.create!(name: "Other's deck")
    @lesson     = @subject.lessons.create!(title: "Other's lesson")
    @item       = @lesson.items.create!(prompt: "secret?", answer: "shh")
    @quiz       = @other.quiz_sessions.create!(started_at: Time.current, planned_count: 1)
  end

  test "fetching another user's subject 404s" do
    get subject_path(@subject)
    assert_response :not_found
  end

  test "editing another user's subject 404s" do
    get edit_subject_path(@subject)
    assert_response :not_found
    patch subject_path(@subject), params: { subject: { name: "hijacked" } }
    assert_response :not_found
    assert_equal "Other's deck", @subject.reload.name
  end

  test "deleting another user's subject 404s and leaves it intact" do
    assert_no_difference -> { Subject.count } do
      delete subject_path(@subject)
    end
    assert_response :not_found
  end

  test "fetching another user's lesson 404s" do
    get lesson_path(@lesson)
    assert_response :not_found
  end

  test "adding a lesson to another user's subject 404s" do
    assert_no_difference -> { Lesson.count } do
      post subject_lessons_path(@subject), params: { lesson: { title: "intruder" } }
    end
    assert_response :not_found
  end

  test "editing another user's item 404s and leaves it intact" do
    patch item_path(@item), params: { item: { answer: "hijacked" } }
    assert_response :not_found
    assert_equal "shh", @item.reload.answer
  end

  test "adding an item to another user's lesson 404s" do
    assert_no_difference -> { Item.count } do
      post lesson_items_path(@lesson), params: { item: { prompt: "x", answer: "y" } }
    end
    assert_response :not_found
  end

  test "fetching another user's quiz session 404s" do
    get quiz_session_path(@quiz)
    assert_response :not_found
  end

  test "grading into another user's quiz session 404s — no attempt is written" do
    assert_no_difference -> { Attempt.count } do
      post quiz_session_attempt_path(@quiz), params: { item_id: @item.id, grade: "good" }
    end
    assert_response :not_found
  end

  test "starting a review scoped to another user's subject 404s" do
    assert_no_difference -> { QuizSession.count } do
      post quiz_sessions_path, params: { subject_id: @subject.id }
    end
    assert_response :not_found
  end

  test "the Library lists only the signed-in user's subjects" do
    owner_subject = users(:owner).subjects.create!(name: "Mine to see")
    get subjects_path
    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(owner_subject)}"
    assert_select "##{ActionView::RecordIdentifier.dom_id(@subject)}", count: 0
  end
end
