class GamePiecesController < ApplicationController
  include ActionView::RecordIdentifier

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

  def adjust_property
    if @piece.adjust_property!(params[:index].to_i, params.fetch(:delta, 1).to_i)
      render_piece
    else
      head :unprocessable_entity
    end
  end

  # Run a VASSAL key command the piece exposes (e.g. "Reveal"). The keystroke
  # must be one of the piece's own menu commands; effects reach every viewer via
  # the model broadcasts plus the game's command-result broadcast. deck is the
  # player's destination pick for a ReturnToDeck command that prompts for one.
  def command
    keystroke = params[:command].to_s
    return head :forbidden unless @piece.menu_commands.any? { |c| c["key"] == keystroke }

    deck_choice = params[:deck].present? ? @game.deck_named_id(params[:deck]) : nil
    result = PieceCommand.run(@piece, keystroke, by: @player.side, deck_choice:)
    @game.apply_command_result(result)
    head :ok
  end

  # Play a card from the actor's hand onto a map.
  def play
    return head :forbidden unless @piece.hand_side == @player.side
    game_map = GameMap.where(game_module_id: @game.game_module_id).find(params[:map])
    return head :unprocessable_entity unless @piece.play_to!(game_map, params[:x].to_i, params[:y].to_i)

    @game.after_card_played(@piece, by: @player.side)
    # Actor: drop the card from the tray (the public append reaches them via cable).
    render turbo_stream: turbo_stream.remove(dom_id(@piece, :hand))
  end

  # Move an on-map piece to another map (the web equivalent of dragging a
  # piece between VASSAL's separate map windows). Generic: any map piece can go
  # to any real map of the module. Like #command, returns head :ok and lets the
  # broadcasts update every viewer.
  def relocate
    return head :unprocessable_entity unless @piece.on_map?
    game_map = GameMap.where(game_module_id: @game.game_module_id).kind_map.find(params[:map])
    from_map = @piece.game_map
    @piece.relocate_to!(game_map, params[:x].to_i, params[:y].to_i)
    @game.after_piece_relocated(@piece, from_map:)
    head :ok
  end

  # Send a card (from the actor's hand, or any map piece) to a deck.
  def discard
    return head :forbidden if @piece.in_hand? && @piece.hand_side != @player.side
    deck = @game.deck_named_id(params[:deck]) or return head(:unprocessable_entity)

    from_hand = @piece.in_hand?
    on_map_id = @piece.on_map? ? dom_id(@piece) : nil
    @piece.discard_to!(deck)
    @game.after_card_discarded(@piece, deck:, by: @player.side, from_hand:)

    if from_hand
      render turbo_stream: turbo_stream.remove(dom_id(@piece, :hand))
    else
      render turbo_stream: turbo_stream.remove(on_map_id)
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
