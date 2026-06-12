class GamePiece < ApplicationRecord
  belongs_to :game
  belongs_to :game_map, optional: true
  belongs_to :board, optional: true

  after_update_commit :broadcast_replace

  # Last write wins; a dropped piece snaps to the grid of the layout board
  # under it (coordinates are map space; the grid is board-local) and comes to
  # the top of its map.
  def move_to!(x, y)
    if (entry = layout_entry_at(x, y))
      local_x, local_y = entry.board.snap_point(x - entry.x, y - entry.y)
      x = local_x + entry.x
      y = local_y + entry.y
    end
    top = game.game_pieces.where(game_map_id:).maximum(:z_order).to_i
    update!(x:, y:, z_order: top + 1)
  end

  def layout_entry_at(x, y)
    game_map && game.board_layout(game_map).entry_at(x, y)
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

  # Steps a layer trait following VASSAL's value semantics: positive = active
  # at that 1-based level, negative = inactive. Single-image layers are on/off
  # markers; multi-level always-active layers wrap; the rest deactivate below
  # level 1 and clamp at the top.
  def cycle_layer!(index, delta)
    update_trait("layer", index) do |trait|
      size = (trait["images"] || []).size
      return false if size.zero?

      value = trait["value"].to_i
      trait["value"] =
        if size == 1
          value.positive? ? -1 : 1
        elsif trait["always_active"]
          level = value.positive? ? value : 1
          ((level - 1 + delta) % size) + 1
        else
          level = (value.positive? ? value : 0) + delta
          level < 1 ? -1 : level.clamp(1, size)
        end
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
