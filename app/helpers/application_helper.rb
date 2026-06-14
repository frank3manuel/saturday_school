module ApplicationHelper
  # The Today CTA copy (plan §9): "Start review — N due".
  def start_review_label(due_count)
    "Start review — #{pluralize(due_count, 'due')}"
  end

  # Honest, human stage label for a display stage (plan §3): never "Mastered!"
  # as a celebration; the five stages describe survival across real time. The
  # single source of truth is MasteryStage, reused by the Library chip, quiz
  # copy, and the Progress dashboard so they never disagree.
  def stage_label(stage)
    MasteryStage.label(stage)
  end

  def stage_description(stage)
    MasteryStage.description(stage)
  end

  # The stage chip — text + color (never color alone, plan §9 a11y). `title`
  # carries the honest one-line meaning for hover/screen-reader context.
  def stage_chip(stage)
    tag.span(stage_label(stage),
             class: "stage stage--#{stage}",
             title: stage_description(stage))
  end

  # "in N days" / "tomorrow" / "today" — for grade-button consequences and the
  # post-answer honest message.
  def interval_phrase(days)
    case days
    when 0 then "today"
    when 1 then "tomorrow"
    else        "in #{days} days"
    end
  end

  # Active state for the responsive shell's nav (sidebar on desktop, tabbar on
  # mobile). A view declares its primary destination once with
  # `content_for :nav_active, "today"` (etc.); both nav surfaces read it so they
  # never disagree. Falls back to a path check so untagged pages still highlight.
  NAV_DESTINATIONS = %w[today library progress].freeze

  def nav_active?(destination)
    declared = content_for(:nav_active).to_s.strip
    return declared == destination.to_s if declared.present?

    case destination.to_s
    when "today"    then current_page?(root_path)
    when "library"  then current_page?(library_path)
    when "progress" then current_page?(progress_path)
    else false
    end
  end

  # The lessons a teacher may assign — only their OWN (plan §8.1). Rooted at the
  # teacher's subjects → lessons, so another teacher's content is never offered.
  def assignable_lessons(user)
    Lesson.where(subject_id: user.subjects.select(:id)).includes(:subject).order(:id)
  end
end
