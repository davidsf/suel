class GamesController < ApplicationController
  def index
    @games = Game.includes(:game_module, :scenario, players: :user).order(created_at: :desc)
  end

  def new
    @scenario = Scenario.ready.find(params[:scenario_id])
    @game = Game.new(scenario: @scenario, game_module: @scenario.game_module,
                     name: "#{@scenario.game_module.name} — #{@scenario.name}")
  end

  def create
    @scenario = Scenario.ready.find(params.dig(:game, :scenario_id))
    @game = Game.new(
      scenario: @scenario,
      game_module: @scenario.game_module,
      creator: Current.user,
      name: params.dig(:game, :name)
    )
    side = params.dig(:game, :side)

    Game.transaction do
      @game.save!
      @game.copy_scenario_pieces!
      @game.players.create!(user: Current.user, side: side)
    end
    redirect_to @game, notice: "Partida creada."
  rescue ActiveRecord::RecordInvalid => e
    @game.errors.merge!(e.record.errors) unless e.record == @game
    render :new, status: :unprocessable_entity
  end

  def show
    @game = Game.includes(:game_module, players: :user).find(params[:id])
    @game_module = @game.game_module
    @player = @game.player_for(Current.user)

    placed = @game.game_pieces.where.not(game_map_id: nil)
    map_ids = placed.group(:game_map_id).order(count_all: :desc).count.keys
    @maps = map_ids.filter_map { |map_id| GameMap.includes(:boards).find_by(id: map_id) }
    @game_map = @maps.find { |m| m.id == params[:map].to_i } || @maps.first
    @layout = @game_map ? @game.board_layout(@game_map).entries : []

    @pieces = @game_map ? placed.where(game_map_id: @game_map.id).order(:z_order) : GamePiece.none
  end
end
