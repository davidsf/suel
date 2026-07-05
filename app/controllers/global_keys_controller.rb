# Fires a module-toolbar Global Key Command (e.g. Empire of the Sun's "Setup"
# scenario buttons). The client only names a button by index into the module's
# own definitions — the keystroke and targeting always come from the buildFile.
class GlobalKeysController < ApplicationController
  def create
    @game = Game.find(params[:game_id])
    @player = @game.player_for(Current.user) or return head(:forbidden)
    gkc = @game.game_module.global_key_commands[params[:button].to_i] or return head(:unprocessable_entity)

    result = ApplicationRecord.transaction { PieceCommand.broadcast(@game, gkc, by: @player.side) }
    @game.apply_command_result(result)
    @game.game_events.create!(user: Current.user, kind: "chat",
      body: t("game_log.global_key", name: gkc["name"], side: @player.side))
    head :ok
  end
end
