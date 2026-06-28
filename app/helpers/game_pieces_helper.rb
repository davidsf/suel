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
      images = trait["images"] || []
      # A layer with at most one meaningful (non-blank) image is an on/off
      # marker (e.g. Moved, Recover): show it as a single toggle, not ± steps.
      meaningful = images.count { |img| img.to_s.strip.present? }
      toggle = meaningful <= 1
      value = trait["value"].to_i
      shown = value.positive? && images[value - 1].to_s.strip.present?
      level_names = trait["level_names"] || []
      { name: trait["name"].presence || "Capa",
        toggle:,
        active: toggle ? shown : value.positive?,
        level: value.positive? ? value : 0,
        level_name: (value.positive? ? level_names[value - 1].presence : nil) }
    end
    # Numeric dynamic properties (e.g. hit counters) become ± stepper rows;
    # index is their position among dynamic_property traits (for adjust_property!).
    properties = game_piece.traits.select { |t| t["kind"] == "dynamic_property" }
      .each_with_index.filter_map do |trait, index|
        next unless trait["numeric"]
        { index:, label: trait["label"].presence || trait["name"],
          value: trait["value"].to_i, min: trait["min"].to_i, max: trait["max"].to_i }
      end
    {
      action: "pointerdown->game-table#pieceDown contextmenu->game-table#pieceContext",
      piece_id: game_piece.id,
      move_url: move_game_piece_path(game, game_piece),
      flip_url: flip_game_piece_path(game, game_piece),
      rotate_url: rotate_game_piece_path(game, game_piece),
      cycle_layer_url: cycle_layer_game_piece_path(game, game_piece),
      adjust_property_url: adjust_property_game_piece_path(game, game_piece),
      discard_url: discard_game_piece_path(game, game_piece),
      flippable: game_piece.traits.any? { |t| t["kind"] == "mask" && t["back_image"].present? },
      rotatable: game_piece.traits.any? { |t| t["kind"] == "rotate" },
      layers: layers.to_json,
      properties: properties.to_json
    }
  end
end
