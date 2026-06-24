class RollsController < ApplicationController
  def create
    @game = Game.find(params[:game_id])
    @player = @game.player_for(Current.user) or return head(:forbidden)

    if params[:special]
      roll_special
    else
      roll_numeric
    end
  end

  private

  def roll_numeric
    button = @game.game_module.dice_buttons[params[:button].to_i] or return head(:unprocessable_entity)

    dice = Array.new(button["n_dice"]) { SecureRandom.random_number(button["n_sides"]) + 1 }
    total = dice.sum + button["plus"]
    result = button["report_total"] ? total.to_s : dice.join(", ")
    result += " (+#{button['plus']} = #{total})" if !button["report_total"] && button["plus"].positive?

    @game.game_events.create!(
      user: Current.user, kind: "roll",
      body: "🎲 #{button['name']}: #{result} — #{@player.side}",
      payload: { "dice" => dice, "total" => total, "button" => button["name"] }
    )
    head :ok
  end

  # One random face per die; the event carries the face icons so the log can
  # show them.
  def roll_special
    button = @game.game_module.special_dice[params[:special].to_i] or return head(:unprocessable_entity)

    faces = button["dice"].map { |die| die[SecureRandom.random_number(die.size)] }
    total = faces.sum { |f| f["value"].to_i }
    labels = faces.map { |f| f["text"].presence || f["value"] }.join(", ")
    body = "🎲 #{button['name']}: #{labels}"
    body += " (total #{total})" if faces.size > 1
    body += " — #{@player.side}"

    @game.game_events.create!(
      user: Current.user, kind: "roll",
      body: body, payload: { "faces" => faces, "total" => total, "button" => button["name"] }
    )
    head :ok
  end
end
