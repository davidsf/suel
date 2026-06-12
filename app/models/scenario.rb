class Scenario < ApplicationRecord
  belongs_to :game_module
  has_many :scenario_pieces, -> { order(:z_order) }, dependent: :destroy

  enum :kind, { vsav: "vsav", module_setup: "module_setup" }, default: "vsav"
  enum :status, %w[pending ready failed].index_by(&:itself), default: "pending"

  # Boards this scenario uses on the given map (.vsav BoardPicker selection),
  # with their pixel offsets in map space.
  def board_layout(game_map)
    identifier = game_map.settings&.dig("identifier") || game_map.name
    BoardLayout.new(game_map, (board_setup || {})[identifier])
  end
end
