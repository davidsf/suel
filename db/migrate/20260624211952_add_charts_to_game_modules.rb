class AddChartsToGameModules < ActiveRecord::Migration[8.1]
  def change
    add_column :game_modules, :charts, :json, default: []
  end
end
