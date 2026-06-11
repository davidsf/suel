class CreateScenarioPieces < ActiveRecord::Migration[8.1]
  def change
    create_table :scenario_pieces do |t|
      t.references :scenario, null: false, foreign_key: true
      t.references :board, foreign_key: true
      t.string :piece_uid
      t.string :map_identifier
      t.integer :x
      t.integer :y
      t.string :gpid
      t.string :name
      t.integer :z_order, null: false, default: 0
      t.text :type_string
      t.json :traits, default: []
      t.json :state, default: {}

      t.timestamps
    end
  end
end
