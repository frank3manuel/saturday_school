require "test_helper"

class LessonsControllerTest < ActionDispatch::IntegrationTest
  test "show lists a lesson's items" do
    get lesson_path(lessons(:algebra))
    assert_response :success
    assert_select "h1", "Algebra basics"
  end

  test "lesson card title link breaks out of the turbo frame (data-turbo-frame=_top)" do
    # Regression mirror of the subject fix: the lesson title (shown on the
    # subject page) was trapped in its card frame. It must carry _top.
    get subject_path(subjects(:math))
    assert_select "##{ActionView::RecordIdentifier.dom_id(lessons(:algebra))} " \
                  "a.card__title[data-turbo-frame=?]", "_top"
  end

  test "create nests the lesson under its subject" do
    assert_difference -> { subjects(:math).lessons.count }, 1 do
      post subject_lessons_path(subjects(:math)), params: { lesson: { title: "Calculus" } }
    end
    assert_response :redirect
  end

  test "create with invalid params re-renders" do
    assert_no_difference -> { Lesson.count } do
      post subject_lessons_path(subjects(:math)),
           params: { lesson: { title: "" } },
           as: :turbo_stream
    end
    assert_response :unprocessable_entity
  end

  test "update changes the lesson" do
    patch lesson_path(lessons(:algebra)), params: { lesson: { title: "Algebra I" } }
    assert_equal "Algebra I", lessons(:algebra).reload.title
  end

  test "destroy removes the lesson" do
    assert_difference -> { Lesson.count }, -1 do
      delete lesson_path(lessons(:revolutions))
    end
  end
end
