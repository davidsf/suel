class Prototype < ApplicationRecord
  belongs_to :game_module

  validates :name, presence: true
end
