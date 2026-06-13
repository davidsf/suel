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
      @game.materialize_decks!
      @game.players.create!(user: Current.user, side: side)
    end
    redirect_to @game, notice: "Partida creada."
  rescue ActiveRecord::RecordInvalid => e
    @game.errors.merge!(e.record.errors) unless e.record == @game
    render :new, status: :unprocessable_entity
  end

  # Live snap preview while dragging: where would a piece land, and its
  # location name. Read-only and cheap (pure geometry over the layout).
  def snap
    game = Game.find(params[:id])
    game_map = GameMap.where(game_module_id: game.game_module_id).find(params[:map])
    x = params[:x].to_i
    y = params[:y].to_i

    entry = game.board_layout(game_map).entry_at(x, y)
    if entry
      local_x, local_y = entry.board.snap_point(x - entry.x, y - entry.y)
      render json: { x: local_x + entry.x, y: local_y + entry.y,
                     location: entry.board.location_name(local_x, local_y) }
    else
      render json: { x:, y:, location: nil }
    end
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
    @dice_buttons = @game_module.dice_buttons
    @events = @game.game_events.order(:created_at).last(100)
  end
end
