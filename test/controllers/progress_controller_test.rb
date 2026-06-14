require "test_helper"

class ProgressControllerTest < ActionDispatch::IntegrationTest
  test "renders the Progress destination" do
    get progress_path
    assert_response :success
    assert_select "h1", "Progress"
  end

  test "shows the five honest stages and never a '% mastered' headline" do
    # Build one item per stage so all five labels appear.
    owner = users(:owner)
    subject = owner.subjects.create!(name: "Geo")
    lesson  = subject.lessons.create!(title: "Capitals")
    { nil => nil, 0 => 0, 3 => 3, 7 => 7, 60 => 60 }.each_value do |survived|
      item = lesson.items.create!(prompt: "Q#{SecureRandom.hex(4)}", answer: "A")
      unless survived.nil?
        item.attempts.create!(user: owner, correct: true, grade: :good, reviewed_at: Time.current,
                              interval_before: survived, interval_after: survived)
      end
    end

    get progress_path
    assert_response :success

    MasteryStage::STAGES.each do |stage|
      assert_select ".legend__label", text: MasteryStage.label(stage)
    end

    # Honest presentation rule (plan §3): no single "% mastered" headline, and
    # no "Mastered" stage label dressed up as a vanity metric. (The word may
    # appear once in the honest framing copy — "there's no single 'mastered'
    # score" — which is the opposite of a vanity headline.)
    assert_no_match(/%\s*mastered/i, response.body, "no '% mastered' headline")
    assert_select ".dist__seg", text: /Mastered/i, count: 0
    assert_select ".legend__label", text: "Mastered", count: 0
  end

  test "surfaces durability stats and the forecast" do
    get progress_path
    assert_response :success
    assert_select "h2", text: "Durability"
    assert_select "h2", text: "Coming up"
    assert_select ".forecast .forecast__day"
  end

  test "keeps the consistency streak separate and clearly labelled, not mastery" do
    get progress_path
    assert_response :success
    assert_select "section[aria-labelledby=?]", "streak-heading"
    assert_select "#streak-heading", text: "Consistency"
  end

  test "renders the 4-destination tab nav with Progress current" do
    get progress_path
    assert_select "nav.tabbar a[aria-current=page]", text: "Progress"
    %w[Today Library Progress].each do |label|
      assert_select "nav.tabbar", text: /#{label}/
    end
    assert_select "nav.tabbar button", text: "Quiz"
  end

  test "stays N+1-free across subjects → items" do
    owner = users(:owner)
    3.times do |i|
      subject = owner.subjects.create!(name: "S#{i}")
      lesson  = subject.lessons.create!(title: "L#{i}")
      3.times do
        item = lesson.items.create!(prompt: "Q#{SecureRandom.hex(4)}", answer: "A")
        item.attempts.create!(user: owner, correct: true, grade: :good, reviewed_at: Time.current,
                              interval_before: 7, interval_after: 7)
      end
    end

    # The whole page must render in a small, constant number of queries — it
    # must not scale with the number of subjects or items.
    assert_queries_at_most(8) { get progress_path }
    assert_response :success
  end

  private

  def assert_queries_at_most(max)
    count = 0
    counter = lambda do |*, payload|
      next if payload[:name] == "SCHEMA"
      next if payload[:sql] =~ /^\s*(BEGIN|COMMIT|RELEASE|SAVEPOINT|ROLLBACK)/i

      count += 1
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    assert count <= max, "expected ≤ #{max} queries, ran #{count}"
  end
end
