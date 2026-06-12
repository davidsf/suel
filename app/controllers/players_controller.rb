class PlayersController < ApplicationController
  def create
    game = Game.find(params[:game_id])
    player = game.players.build(user: Current.user, side: params[:side])
    if player.save
      redirect_to game, notice: "Te has unido como #{player.side}."
    else
      redirect_to game, alert: player.errors.full_messages.to_sentence
    end
  end
end
