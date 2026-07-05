class AddBoardSetupToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :board_setup, :json, default: {}, null: false
  end
end
