class CreateGamePieces < ActiveRecord::Migration[8.1]
  def change
    create_table :game_pieces do |t|
      t.references :game, null: false, foreign_key: true
      t.references :game_map, foreign_key: true
      t.references :board, foreign_key: true
      t.string :gpid
      t.string :name
      t.integer :x
      t.integer :y
      t.integer :z_order, null: false, default: 0
      t.text :type_string
      t.json :traits, default: []

      t.timestamps
    end
    add_index :game_pieces, [ :game_id, :game_map_id ]
  end
end
