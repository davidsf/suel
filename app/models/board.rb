class Board < ApplicationRecord
  belongs_to :game_map
  has_one :game_module, through: :game_map
  has_many :scenario_pieces, dependent: :nullify

  def grid_type = grid&.dig("type") || "none"
end
