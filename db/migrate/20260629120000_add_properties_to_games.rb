class AddPropertiesToGames < ActiveRecord::Migration[8.1]
  def change
    # Global properties the module's command traits read and write
    # (SetGlobalProperty), e.g. a captured location to send a revealed unit to.
    add_column :games, :properties, :json, default: {}, null: false
  end
end
