class ChartsController < ApplicationController
  allow_unauthenticated_access

  def show
    @game_module = GameModule.find_by!(slug: params[:game_module_slug])
    @windows = @game_module.charts || []
    # Embedded in the game table dialog when ?frame=1 (no chrome/layout).
    render layout: false if params[:frame]
  end
end
