class Subject < ApplicationRecord
  # The owner (plan §4.5) — NOT NULL, FK-backed since M5's tighten migration.
  belongs_to :user
  has_many :lessons, -> { order(:position, :id) }, dependent: :destroy
  has_many :items, through: :lessons

  validates :name, presence: true

  default_scope { order(:position, :id) }
end
