class Lesson < ApplicationRecord
  belongs_to :subject
  has_many :items, -> { order(:id) }, dependent: :destroy

  validates :title, presence: true

  default_scope { order(:position, :id) }
end
