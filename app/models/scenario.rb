class Scenario < ApplicationRecord
  belongs_to :game_module
  has_many :scenario_pieces, -> { order(:z_order) }, dependent: :destroy

  enum :kind, { vsav: "vsav", module_setup: "module_setup" }, default: "vsav"
  enum :status, %w[pending ready failed].index_by(&:itself), default: "pending"

  # Boards this scenario uses on the given map (.vsav BoardPicker selection),
  # with their pixel offsets in map space.
  def board_layout(game_map)
    BoardLayout.new(game_map, (board_setup || {})[game_map.identifier])
  end

  # Map windows whose BoardPicker offers several boards and this scenario
  # doesn't pin a selection — VASSAL prompts for those at new game (the
  # BoardPicker dialog only appears when no board setup was restored).
  def maps_needing_board_choice
    game_module.game_maps.kind_map.includes(:boards).select do |map|
      map.boards.size > 1 && (board_setup || {})[map.identifier].blank?
    end
  end
end
