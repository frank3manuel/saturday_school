# frozen_string_literal: true

# Honest class-aggregate progress for ONE cohort (plan §9, §3, M6d). For every
# assigned item × every active student, computes the honest MasteryStage and
# rolls it up into a STACKED stage distribution — NEVER a fabricated "% mastered"
# (plan §3). What has stuck took real elapsed time; the size of Maturing+Durable
# is the only honest "how much have they truly learned."
#
# Strictly scoped (plan §8.2): the data is bounded to (this teacher's cohort) ×
# (the lessons/items the teacher ASSIGNED to it) × (active enrollees). A personal
# deck has no assignment row, so it can never enter this report — privacy by the
# join graph. Students do NOT see classmates (plan §15 D-classmates); this report
# is teacher-only.
#
# N+1-free: a fixed, small number of queries regardless of cohort/student count.
#   1. the active student ids
#   2. the assigned item ids (live assignments only)
#   3. ONE grouped query: max survived gap per (user_id, item_id) from the
#      correct-attempt log (the source of truth for "survived an N-day gap").
class CohortProgressReport
  # `name` (not `label`) so this reuses the same progress/_distribution partial
  # the personal dashboard uses — the honest stacked bar, identical everywhere.
  StageRow = Struct.new(:name, :counts, :total, keyword_init: true) do
    def truly_learned
      MasteryStage::TRULY_LEARNED.sum { |stage| counts.fetch(stage, 0) }
    end
  end

  def initialize(cohort:)
    @cohort = cohort
  end

  # One stacked distribution per assigned item (across the active students).
  def by_item
    items.map do |item|
      stages = student_ids.map { |uid| stage_for(uid, item.id) }
      StageRow.new(name: "#{item.lesson.title} · #{truncate(item.prompt)}",
                   counts: tally(stages), total: student_ids.size)
    end
  end

  # One stacked distribution per active student (across the assigned items).
  def by_student
    students.map do |student|
      stages = item_ids.map { |iid| stage_for(student.id, iid) }
      StageRow.new(name: student.email_address,
                   counts: tally(stages), total: item_ids.size)
    end
  end

  # The whole-cohort roll-up across every (student × assigned item) cell.
  def overall
    stages = student_ids.product(item_ids).map { |uid, iid| stage_for(uid, iid) }
    StageRow.new(name: "All assigned items", counts: tally(stages), total: stages.size)
  end

  def students = @students ||= @cohort.active_students.order(:email_address).to_a
  def student_ids = @student_ids ||= students.map(&:id)

  def items
    @items ||= Item.where(lesson_id: @cohort.active_assignments.select(:lesson_id))
                   .includes(:lesson).order(:lesson_id, :id).to_a
  end
  def item_ids = @item_ids ||= items.map(&:id)

  private

  # (user_id, item_id) → longest survived gap (days) from ONE grouped query over
  # the correct-attempt log, bounded to this cohort's students and assigned items.
  def survived
    @survived ||=
      Attempt.where(user_id: student_ids, item_id: item_ids, correct: true)
             .group(:user_id, :item_id)
             .maximum(:interval_before)
             .transform_values(&:to_i)
  end

  def stage_for(user_id, item_id)
    days = survived[[ user_id, item_id ]]
    MasteryStage.from(recalled: !days.nil?, survived_days: days)
  end

  def tally(stages)
    base = MasteryStage::STAGES.index_with { 0 }
    stages.each { |stage| base[stage] += 1 }
    base
  end

  def truncate(text, length: 40)
    text.length > length ? "#{text[0, length]}…" : text
  end
end
