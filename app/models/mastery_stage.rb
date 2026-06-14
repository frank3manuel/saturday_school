# frozen_string_literal: true

# The five honest display stages (plan §3) and the single, centralized mapping
# from an item's SRS history → one stage. This is the one place that decides
# "how mature is this item?", reused by the Library stage chip, the quiz copy,
# and the Progress dashboard so they never disagree.
#
# A stage is earned by *surviving a real elapsed gap*, never by in-session
# performance (plan §1, §3). The gap an item has survived is the largest
# `interval_before` across its *correct* attempts — i.e. the longest wait it
# was nonetheless recalled after. Pass that value in as `survived_days`.
#
#   New      — never successfully recalled                (no correct attempt)
#   Learning — recalled, but only across a <1-day gap     (survived 0d)
#   Young     — survived a ≥1-day gap                      (survived ≥1d)
#   Maturing  — survived a ≥1-week gap (durable standard)  (survived ≥7d)
#   Durable   — survived a weeks-to-months gap (gold)      (survived ≥60d)
#
# Thresholds come straight from the §5 ladder (1d → Young, 7d → Maturing,
# 60d → Durable) via Srs::Scheduler's mastery constants, so there is one source
# of truth for the numbers.
module MasteryStage
  # Ordered new → durable so distributions stack consistently everywhere.
  STAGES = %i[new learning young maturing durable].freeze

  LABELS = {
    new:      "New",
    learning: "Learning",
    young:    "Young",
    maturing: "Maturing",
    durable:  "Durable"
  }.freeze

  # One-line honest meaning, used as the chip/legend description (a11y: the
  # stage is always paired with text, never color alone — plan §9).
  DESCRIPTIONS = {
    new:      "Not yet recalled",
    learning: "Recalled, not yet across a gap",
    young:    "Survived a 1-day gap",
    maturing: "Survived a 1-week gap",
    durable:  "Survived a 60-day gap"
  }.freeze

  YOUNG_DAYS    = 1
  MATURING_DAYS = Srs::Scheduler::MASTERY_INTERVAL_DAYS  # 7
  DURABLE_DAYS  = Srs::Scheduler::DURABLE_INTERVAL_DAYS  # 60

  # The stages that count as "truly learned" — the honest headline (plan §3):
  # what has stuck took real time. Deliberately NOT a single "% mastered".
  TRULY_LEARNED = %i[maturing durable].freeze

  # Map (recalled?, longest-survived gap in days) → a display stage symbol.
  #
  # recalled:: has the item ever been correctly recalled at all?
  # survived_days:: the largest gap (in days) it was recalled across; nil/0 for
  #   an item that has only ever been seen at interval 0.
  def self.from(recalled:, survived_days:)
    return :new unless recalled

    days = survived_days.to_i
    if    days >= DURABLE_DAYS  then :durable
    elsif days >= MATURING_DAYS then :maturing
    elsif days >= YOUNG_DAYS    then :young
    else  :learning
    end
  end

  # Bulk: item_id → display stage for a set of items, using ONE grouped query
  # over the correct-attempt log (no N+1 over a list/table). The append-only
  # attempts are the source of truth for the longest gap each item survived.
  def self.for_items(items)
    items = Array(items)
    return {} if items.empty?

    survived = Attempt.where(item_id: items.map(&:id), correct: true)
                      .group(:item_id)
                      .maximum(:interval_before)
                      .transform_values(&:to_i)
    items.each_with_object({}) do |item, map|
      map[item.id] = from(recalled: survived.key?(item.id), survived_days: survived[item.id])
    end
  end

  def self.label(stage)
    LABELS.fetch(stage.to_sym)
  end

  def self.description(stage)
    DESCRIPTIONS.fetch(stage.to_sym)
  end
end
