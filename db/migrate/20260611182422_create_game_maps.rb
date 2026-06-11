class CreateGameMaps < ActiveRecord::Migration[8.1]
  def change
    create_table :game_maps do |t|
      t.references :game_module, null: false, foreign_key: true
      t.string :name
      t.string :kind, null: false, default: "map"
      t.string :side
      t.json :settings, default: {}
      t.integer :position, null: false, default: 0

      t.timestamps
    end
  end
end
