require "application_system_test_case"

# Browser coverage of the review loop's JavaScript (plan §3, §9, §10): the part
# that can ONLY be verified in a real browser — the Stimulus-driven reveal of a
# hidden answer inside the Turbo-Framed quiz card.
#
# The server-rendered flow that follows — grade → one Attempt + state update →
# auto-advance (Turbo Stream) → queue exhausted → summary — is covered
# deterministically, without browser-timing flake, by the integration suite in
# test/controllers/attempts_controller_test.rb ("one grade POST…", "grading
# auto-advances…", "the last grade exhausts the queue and offers the summary").
#
# Content authoring is set up directly as the signed-in owner; the inline
# Turbo-Stream authoring forms are covered by the *_controller tests.
class QuizSessionLoopTest < ApplicationSystemTestCase
  test "sign in, start a review, and reveal the answer" do
    owner = users(:owner)

    # --- Author content directly, owned by the user who will review it -------
    subject = owner.subjects.create!(name: "Capitals")
    lesson  = subject.lessons.create!(title: "Europe")
    item    = lesson.items.create!(prompt: "Capital of France?", answer: "Paris")

    # M3 has no scheduling UI, so make this item due now and push every other
    # item out of the due window, so the queue is a deterministic single card.
    Item.where.not(id: item.id).update_all(due_at: 30.days.from_now)
    item.update!(state: :review, box: 1, interval_days: 1, due_at: 1.day.ago)

    # Auth is secure-by-default (M5) — sign in before visiting any page.
    sign_in_through_ui(owner)

    # --- Start the review from Today -----------------------------------------
    visit root_path
    assert_text "Start review"
    click_on "Start review — 1 due"

    # The first card shows the prompt; the answer is hidden until revealed.
    assert_selector "turbo-frame#quiz_card"
    assert_text "Capital of France?"
    assert_text "Card 1 of 1"
    assert_no_text "Paris"

    # --- Reveal the answer (Stimulus) ----------------------------------------
    # Wait until the quiz controller has connected (it publishes data-quiz-ready
    # on connect), then reveal via Space through its document-level keydown
    # listener. On reveal, the hidden answer and the grade bar become visible.
    assert_selector ".quiz[data-quiz-ready='true']"
    find("body").send_keys(:space)

    assert_text "Paris"
    assert_selector ".quiz__answer", visible: true
    assert_selector ".grade-bar .grade--good", visible: true
  end
end
