class GamePiecesController < ApplicationController
  before_action :set_game_and_piece
  before_action :require_player

  def move
    @piece.move_to!(params[:x].to_i, params[:y].to_i)
    render_piece
  end

  def flip
    if @piece.flip!(by: @player.side)
      render_piece
    else
      head :unprocessable_entity
    end
  end

  def rotate
    direction = params[:direction].to_i.clamp(-1, 1)
    if direction.nonzero? && @piece.rotate!(direction)
      render_piece
    else
      head :unprocessable_entity
    end
  end

  def cycle_layer
    if @piece.cycle_layer!(params[:index].to_i, params.fetch(:delta, 1).to_i)
      render_piece
    else
      head :unprocessable_entity
    end
  end

  private

  def set_game_and_piece
    @game = Game.find(params[:game_id])
    @piece = @game.game_pieces.find(params[:id])
  end

  def require_player
    @player = @game.player_for(Current.user)
    head :forbidden unless @player
  end

  # Immediate feedback for the actor, independent of cable delivery; everyone
  # else gets the same partial via the model's broadcast.
  def render_piece
    render turbo_stream: turbo_stream.replace(
      @piece,
      partial: "game_pieces/game_piece",
      locals: { game_piece: @piece, game_module: @game.game_module }
    )
  end
end
