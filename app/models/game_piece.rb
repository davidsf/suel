class GamePiece < ApplicationRecord
  belongs_to :game
  belongs_to :game_map, optional: true
  belongs_to :board, optional: true

  after_update_commit :broadcast_replace

  # Last write wins; a dropped piece comes to the top of its map.
  def move_to!(x, y)
    top = game.game_pieces.where(game_map_id:).maximum(:z_order).to_i
    update!(x:, y:, z_order: top + 1)
  end

  # Toggles the mask trait: obscured shows only the back image to everyone.
  def flip!(by:)
    update_trait("mask") do |trait|
      trait["obscured_by"] = trait["obscured_by"].present? ? nil : by
    end
  end

  # Steps the rotate trait one facing (or 15° for free rotators). The stored
  # angle uses VASSAL's convention (PiecesHelper#piece_rotation negates it).
  def rotate!(direction)
    update_trait("rotate") do |trait|
      step = trait["free"] ? 15.0 : 360.0 / trait["facings"].to_i.clamp(1, 360)
      trait["angle"] = (trait["angle"].to_f - step * direction) % 360
    end
  end

  # Cycles a layer trait through its levels (1-based; inactive becomes level 1).
  def cycle_layer!(index, delta)
    update_trait("layer", index) do |trait|
      size = (trait["images"] || []).size
      return false if size.zero?
      level = trait["value"].to_i
      level = 1 unless level.positive?
      trait["value"] = ((level - 1 + delta) % size) + 1
    end
  end

  private

  # JSON columns aren't dirty-tracked on in-place mutation: always deep_dup,
  # modify the copy, reassign.
  def update_trait(kind, index = 0)
    updated = traits.deep_dup
    trait = updated.select { |t| t["kind"] == kind }[index]
    return false unless trait
    yield trait
    update!(traits: updated)
    true
  end

  def broadcast_replace
    broadcast_replace_to game,
      partial: "game_pieces/game_piece",
      locals: { game_piece: self, game_module: game.game_module }
  end
end
