class AddBoardSetupToScenarios < ActiveRecord::Migration[8.1]
  def change
    add_column :scenarios, :board_setup, :json, default: {}
  end
end
