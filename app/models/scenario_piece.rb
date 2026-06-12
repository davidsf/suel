class ScenarioPiece < ApplicationRecord
  belongs_to :scenario
  belongs_to :game_map, optional: true
  belongs_to :board, optional: true

  scope :resolved, -> { where.not(board_id: nil) }
  scope :unresolved, -> { where(board_id: nil) }

  def location_name
    return nil unless game_map
    scenario.board_layout(game_map).entry_at(x.to_i, y.to_i)&.location_name(x.to_i, y.to_i)
  end
end
