class GamesController < ApplicationController
  def index
    @games = Game.includes(:game_module, :scenario, players: :user).order(created_at: :desc)
    @modules = GameModule.ready.includes(game_maps: :boards).order(:name)
      .select { |m| m.scenarios.ready.exists? }
  end

  def new
    @scenario = Scenario.ready.find(params[:scenario_id])
    @game = Game.new(scenario: @scenario, game_module: @scenario.game_module,
                     name: "#{@scenario.game_module.name} — #{@scenario.name}")
    @board_choice_maps = @scenario.maps_needing_board_choice
  end

  def create
    @scenario = Scenario.ready.find(params.dig(:game, :scenario_id))
    @game = Game.new(
      scenario: @scenario,
      game_module: @scenario.game_module,
      creator: Current.user,
      name: params.dig(:game, :name)
    )
    # Dynamic map-identifier keys, so permit the whole sub-hash; the values
    # are validated against the module's boards by the model.
    @game.choose_boards(params.dig(:game, :board_setup)&.permit!&.to_h)
    side = params.dig(:game, :side)

    Game.transaction do
      @game.save!
      @game.copy_scenario_pieces!
      @game.materialize_decks!
      @game.players.create!(user: Current.user, side: side)
    end
    redirect_to @game, notice: t("flash.game_created")
  rescue ActiveRecord::RecordInvalid => e
    @game.errors.merge!(e.record.errors) unless e.record == @game
    @board_choice_maps = @scenario.maps_needing_board_choice
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
    piece_map_ids = placed.group(:game_map_id).order(count_all: :desc).count.keys
    # Every map window of the module is reachable, as in VASSAL (each Map has
    # a toolbar launch button): piece-bearing maps first (busiest first, any
    # kind), then deck hosts (e.g. a "Cards" display), then the rest — charts,
    # tables, setup cards — in module order.
    module_maps = @game_module.game_maps.kind_map.includes(:boards).to_a
    deck_map_ids = @game_module.game_maps.kind_map.joins(:decks).distinct.pluck(:id)
    piece_maps = piece_map_ids.filter_map do |id|
      module_maps.find { |m| m.id == id } || GameMap.includes(:boards).find_by(id: id)
    end
    rest = module_maps.reject { |m| piece_map_ids.include?(m.id) }
      .sort_by { |m| [ deck_map_ids.include?(m.id) ? 0 : 1, m.position ] }
    @maps = piece_maps + rest
    @game_map = @maps.find { |m| m.id == params[:map].to_i } || @maps.first
    # VASSAL ToolbarMenu grouping: menu entries match map windows by their
    # launch button text (buttonName); unmatched entries are skipped and empty
    # menus don't render. Grouped maps leave the flat tab list.
    @map_menus = @game_module.toolbar_menus.filter_map do |menu|
      maps = menu["items"].filter_map { |item| @maps.find { |m| m.settings["buttonName"] == item } }.uniq
      { name: menu["name"], icon: menu["icon"], maps: } if maps.any?
    end
    @tab_maps = @maps - @map_menus.flat_map { |m| m[:maps] }
    @layout = @game_map ? @game.board_layout(@game_map).entries : []
    # Destinations offered by the "move to another map" piece menu: every real
    # map of the module except the one in view (VASSAL lets a piece be dragged
    # to any map window; we don't classify maps).
    @destination_maps = @game_module.game_maps.kind_map.where.not(id: @game_map&.id).order(:position)

    @pieces = @game_map ? placed.where(game_map_id: @game_map.id).order(:z_order) : GamePiece.none
    @dice_buttons = @game_module.dice_buttons
    @special_dice = @game_module.special_dice
    @events = @game.game_events.order(:created_at).last(100)

    # Decks shown on the current map (markers on hand maps live in the tray)
    @decks = @game_map ? @game_map.decks.reject { |d| @game_map.kind_player_hand? } : []
    @all_decks = @game_module.decks.to_a
    # Hands exist only if the module defines PlayerHand windows (VASSAL's
    # PrivateMap owned by a side) — modules like Holland '44 have none, so no
    # hand tray and no card counts.
    hand_maps = @game_module.game_maps.kind_player_hand
    @module_has_hands = hand_maps.exists?
    if @player
      @hand_cards = @game.game_pieces.in_hand(@player.side).order(:id)
      @hand_decks = hand_maps.where(side: @player.side).flat_map(&:decks)
      # The player's own hand: a PlayerHand for their side (blank = any side),
      # or cards already held (never strand them without a tray).
      @player_hand = @hand_cards.any? || hand_maps.where(side: [ nil, "", @player.side ]).exists?
    end
  end
end
