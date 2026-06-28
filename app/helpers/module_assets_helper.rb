module ModuleAssetsHelper
  def module_image_path(game_module, filename)
    game_module_asset_path(game_module, path: "images/#{filename}")
  end

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
