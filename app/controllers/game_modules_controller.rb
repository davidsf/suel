class GameModulesController < ApplicationController
  allow_unauthenticated_access

  def index
    @game_modules = GameModule.includes(game_maps: :boards).order(:name)
  end

  def show
    @game_module = GameModule.includes(game_maps: %i[boards decks]).find_by!(slug: params[:slug])
    @scenarios = @game_module.scenarios.order(:kind, :name)
  end
end
