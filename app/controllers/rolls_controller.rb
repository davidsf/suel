class RollsController < ApplicationController
  def create
    game = Game.find(params[:game_id])
    player = game.player_for(Current.user) or return head(:forbidden)

    button = game.game_module.dice_buttons[params[:button].to_i] or return head(:unprocessable_entity)

    dice = Array.new(button["n_dice"]) { SecureRandom.random_number(button["n_sides"]) + 1 }
    total = dice.sum + button["plus"]
    result = button["report_total"] ? total.to_s : dice.join(", ")
    result += " (+#{button['plus']} = #{total})" if !button["report_total"] && button["plus"].positive?

    game.game_events.create!(
      user: Current.user, kind: "roll",
      body: "🎲 #{button['name']}: #{result} — #{player.side}",
      payload: { "dice" => dice, "total" => total, "button" => button["name"] }
    )
    head :ok
  end
end
