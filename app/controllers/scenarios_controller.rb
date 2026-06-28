class ScenariosController < ApplicationController
  allow_unauthenticated_access

  def index
    @game_module = GameModule.find_by!(slug: params[:game_module_slug])
    @scenarios = @game_module.scenarios.ready.order(:kind, :name)
  end

  def show
    @game_module = GameModule.find_by!(slug: params[:game_module_slug])
    @scenario = @game_module.scenarios.find(params[:id])

    placed = @scenario.scenario_pieces.where.not(game_map_id: nil)
    @maps = GameMap.where(id: placed.select(:game_map_id).distinct).includes(:boards)
      .sort_by { |m| -placed.where(game_map_id: m.id).count }
    @game_map = @maps.find { |m| m.id == params[:map].to_i } || @maps.first
    @layout = @game_map ? @scenario.board_layout(@game_map).entries : []

    @pieces = @game_map ? placed.where(game_map_id: @game_map.id).order(:z_order) : ScenarioPiece.none
    @unresolved_count = @scenario.scenario_pieces.where(game_map_id: nil).count
    @decks = @scenario.module_setup? && @game_map ? @game_map.decks.includes(:piece_definitions) : []
  end
end
