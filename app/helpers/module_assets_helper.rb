module ModuleAssetsHelper
  def module_image_path(game_module, filename)
    game_module_asset_path(game_module, path: "images/#{filename}")
  end

  # A module-defined toolbar icon (VASSAL "icon" attribute, an image inside
  # the module); nil when the module sets none (VASSAL then falls back to an
  # engine icon we don't ship).
  def toolbar_icon(game_module, icon)
    return if icon.blank?
    return unless game_module.extracted_dir.join("images", icon).file?
    image_tag module_image_path(game_module, icon), class: "map-tab-icon", alt: ""
  end

  def map_tab_icon(game_map, game_module) = toolbar_icon(game_module, game_map.settings["icon"])

  # Downscaled board preview when the import produced one, full image otherwise.
  def board_preview_path(board, game_module = board.game_map.game_module)
    preview = "previews/#{board.image_filename}.jpg"
    if game_module.extracted_dir.join(preview).file?
      game_module_asset_path(game_module, path: preview)
    else
      module_image_path(game_module, board.image_filename)
    end
  end

  # Cover image for a module card: the module's own about-screen art when
  # present, otherwise the first board preview, otherwise nil (blank thumb).
  def module_cover_path(game_module)
    cover = game_module.cover_image
    return game_module_asset_path(game_module, path: cover) if cover && game_module.extracted_dir.join(cover).file?

    board = game_module.game_maps.flat_map(&:boards).find { |b| b.image_filename.present? }
    board_preview_path(board, game_module) if board
  end
end
