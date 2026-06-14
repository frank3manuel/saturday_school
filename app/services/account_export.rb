# frozen_string_literal: true

# A self-contained JSON dump of everything a user owns (plan §9, D-data: "your
# data is yours"). Walks the user's subjects → lessons → items and their
# attempts, plus quiz sessions, in a small fixed number of queries (eager-loaded
# so the export of a large account doesn't N+1).
class AccountExport
  def initialize(user)
    @user = user
  end

  def to_json(*)
    as_hash.to_json
  end

  def as_hash
    {
      exported_at: Time.current.iso8601,
      account: {
        email_address: @user.email_address,
        role: @user.role,
        created_at: @user.created_at.iso8601
      },
      subjects: subjects_payload,
      quiz_sessions: quiz_sessions_payload
    }
  end

  private

  def subjects_payload
    @user.subjects.includes(lessons: { items: :attempts }).map do |subject|
      {
        name: subject.name,
        description: subject.description,
        lessons: subject.lessons.map { |lesson| lesson_payload(lesson) }
      }
    end
  end

  def lesson_payload(lesson)
    {
      title: lesson.title,
      body: lesson.body,
      items: lesson.items.map { |item| item_payload(item) }
    }
  end

  def item_payload(item)
    {
      prompt: item.prompt,
      answer: item.answer,
      item_type: item.item_type,
      state: item.state,
      box: item.box,
      interval_days: item.interval_days,
      streak: item.streak,
      repetitions: item.repetitions,
      lapses: item.lapses,
      due_at: item.due_at&.iso8601,
      mastered_at: item.mastered_at&.iso8601,
      attempts: item.attempts.map { |a| attempt_payload(a) }
    }
  end

  def attempt_payload(attempt)
    {
      grade: attempt.grade,
      correct: attempt.correct,
      reviewed_at: attempt.reviewed_at.iso8601,
      interval_before: attempt.interval_before,
      interval_after: attempt.interval_after,
      response_latency_ms: attempt.response_latency_ms
    }
  end

  def quiz_sessions_payload
    @user.quiz_sessions.map do |qs|
      {
        scope: qs.scope_label,
        started_at: qs.started_at&.iso8601,
        completed_at: qs.completed_at&.iso8601,
        planned_count: qs.planned_count
      }
    end
  end
end
