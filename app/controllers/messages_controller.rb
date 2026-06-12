class MessagesController < ApplicationController
  MAX_LENGTH = 500

  def create
    game = Game.find(params[:game_id])
    text = params[:body].to_s.strip.first(MAX_LENGTH)
    return head :unprocessable_entity if text.blank?

    player = game.player_for(Current.user)
    author = player&.side || Current.user.email_address.split("@").first

    game.game_events.create!(
      user: Current.user, kind: "chat",
      body: "#{author}: #{text}"
    )
    head :no_content
  end
end
