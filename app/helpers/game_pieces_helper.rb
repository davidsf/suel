module GamePiecesHelper
  # Traits as they must be rendered on the table: when a piece is obscured
  # (mask trait with obscured_by set), everyone sees only the back image —
  # layers and labels would leak information. Leaves pieces/_piece untouched
  # for the palette and scenario viewers.
  def displayed_traits(traits)
    mask = traits.find { |t| t["kind"] == "mask" }
    return traits unless mask && mask["obscured_by"].present? && mask["back_image"].present?

    traits.filter_map do |trait|
      case trait["kind"]
      when "basic" then trait.merge("image" => mask["back_image"])
      when "layer", "label" then nil
      else trait
      end
    end
  end

  # Capability data attributes for the piece div — viewer-neutral (the same
  # HTML is broadcast to every viewer; per-viewer behavior lives outside).
  def game_piece_data(game_piece)
    game = game_piece.game
    layers = game_piece.traits.filter_map do |trait|
      next unless trait["kind"] == "layer"
      { name: trait["name"].presence || "Capa", levels: (trait["images"] || []).size }
    end
    {
      action: "pointerdown->game-table#pieceDown",
      piece_id: game_piece.id,
      move_url: move_game_piece_path(game, game_piece),
      flip_url: flip_game_piece_path(game, game_piece),
      rotate_url: rotate_game_piece_path(game, game_piece),
      cycle_layer_url: cycle_layer_game_piece_path(game, game_piece),
      flippable: game_piece.traits.any? { |t| t["kind"] == "mask" && t["back_image"].present? },
      rotatable: game_piece.traits.any? { |t| t["kind"] == "rotate" },
      layers: layers.to_json
    }
  end
end
