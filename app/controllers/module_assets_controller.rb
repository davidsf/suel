class ModuleAssetsController < ApplicationController
  allow_unauthenticated_access

  # Serves files extracted from the .vmod (images, docs). Extracted content is
  # immutable per module id, so clients may cache it forever.
  def show
    game_module = GameModule.find_by!(slug: params[:game_module_slug])
    root = File.expand_path(game_module.extracted_dir)
    path = File.expand_path(File.join(root, params[:path]))

    head :not_found and return unless path.start_with?(root + File::SEPARATOR) && File.file?(path)

    response.headers["Cache-Control"] = "public, max-age=31536000, immutable"
    send_file path, disposition: "inline"
  end
end
