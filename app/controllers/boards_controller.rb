class BoardsController < ApplicationController
  allow_unauthenticated_access

  def show
    @game_module = GameModule.find_by!(slug: params[:game_module_slug])
    @board = @game_module.boards.find(params[:id])
    @game_map = @board.game_map
  end
end
