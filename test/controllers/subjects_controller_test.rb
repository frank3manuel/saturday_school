require "test_helper"

class SubjectsControllerTest < ActionDispatch::IntegrationTest
  test "index renders the Library and lists subjects" do
    get subjects_path
    assert_response :success
    assert_select "h1", "Library"
    assert_select "##{ActionView::RecordIdentifier.dom_id(subjects(:math))}"
  end

  test "subject card title link breaks out of the turbo frame (data-turbo-frame=_top)" do
    # Regression: the title was trapped in turbo_frame_tag dom_id(subject) and
    # rendered "Content missing" instead of navigating. It must carry _top.
    get subjects_path
    assert_select "##{ActionView::RecordIdentifier.dom_id(subjects(:math))} " \
                  "a.card__title[data-turbo-frame=?]", "_top"
  end

  test "show lists a subject's lessons" do
    get subject_path(subjects(:math))
    assert_response :success
    assert_select "h1", "Mathematics"
  end

  test "create with valid params adds a subject" do
    assert_difference -> { Subject.count }, 1 do
      post subjects_path, params: { subject: { name: "Biology" } }
    end
    assert_response :redirect
  end

  test "create responds with turbo_stream when requested" do
    assert_difference -> { Subject.count }, 1 do
      post subjects_path,
           params: { subject: { name: "Chemistry" } },
           as: :turbo_stream
    end
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
  end

  test "create with invalid params re-renders the form" do
    assert_no_difference -> { Subject.count } do
      post subjects_path, params: { subject: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "update changes the subject" do
    patch subject_path(subjects(:math)), params: { subject: { name: "Maths" } }
    assert_redirected_to subject_path(subjects(:math))
    assert_equal "Maths", subjects(:math).reload.name
  end

  test "destroy removes the subject and cascades" do
    subject = subjects(:history)
    assert_difference -> { Subject.count }, -1 do
      delete subject_path(subject)
    end
    assert_redirected_to subjects_path
  end
end
