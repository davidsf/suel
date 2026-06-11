class ScenarioPiece < ApplicationRecord
  belongs_to :scenario
  belongs_to :game_map, optional: true
  belongs_to :board, optional: true

  scope :resolved, -> { where.not(board_id: nil) }
  scope :unresolved, -> { where(board_id: nil) }
end
