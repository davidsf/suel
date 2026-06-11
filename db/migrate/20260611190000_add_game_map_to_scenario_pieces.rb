class AddGameMapToScenarioPieces < ActiveRecord::Migration[8.1]
  def change
    add_reference :scenario_pieces, :game_map, foreign_key: true
  end
end
