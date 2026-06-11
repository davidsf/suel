class PalettesController < ApplicationController
  allow_unauthenticated_access

  def show
    @game_module = GameModule.find_by!(slug: params[:game_module_slug])
    @groups = @game_module.piece_definitions.where(deck_id: nil)
      .order(:position).group_by(&:palette_path)
    @decks = @game_module.decks.includes(:piece_definitions, :game_map)
  end
end
