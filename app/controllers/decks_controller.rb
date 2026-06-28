class DecksController < ApplicationController
  include ActionView::RecordIdentifier

  before_action :set_game_and_deck
  before_action :require_player
  before_action :authorize_deck!

  def draw
    # Dragged out of the deck onto the table (VASSAL style): place at the drop
    # point. Broadcasts (deck marker + map append) update everyone, the actor
    # included, so no turbo_stream response is needed.
    if params[:x].present?
      map = @game.game_module.game_maps.find(params[:map])
      card = @game.draw_to_map!(@deck, by: @player.side, game_map: map,
                                x: params[:x].to_i, y: params[:y].to_i)
      return head :unprocessable_entity unless card
      return head :no_content
    end

    # No coordinates: draw into the side's hand (hand-map decks / card games).
    card = @game.draw_card!(@deck, side: @player.side)
    return head :unprocessable_entity unless card

    # Actor feedback: update the deck marker and append the card to their tray.
    render turbo_stream: [
      turbo_stream.replace(dom_id(@deck), partial: "decks/deck_marker", locals: { deck: @deck, game: @game }),
      turbo_stream.append("hand_tray", partial: "game_pieces/hand_card",
                          locals: { game_piece: card, game_module: @game.game_module })
    ]
  end

  def shuffle
    @game.shuffle_deck!(@deck, by: @player.side)
    render turbo_stream: turbo_stream.replace(dom_id(@deck), partial: "decks/deck_marker",
                                              locals: { deck: @deck, game: @game })
  end

  def reshuffle
    if @game.reshuffle_deck!(@deck, by: @player.side)
      head :no_content
    else
      head :unprocessable_entity
    end
  end

  private

  def set_game_and_deck
    @game = Game.find(params[:game_id])
    @deck = Deck.joins(:game_map)
      .where(game_maps: { game_module_id: @game.game_module_id })
      .find(params[:id])
  end

  def require_player
    @player = @game.player_for(Current.user)
    head :forbidden unless @player
  end

  # A deck living on a player's hand map belongs to that side only.
  def authorize_deck!
    map = @deck.game_map
    return unless map.kind_player_hand? && map.side != @player.side
    head :forbidden
  end
end
