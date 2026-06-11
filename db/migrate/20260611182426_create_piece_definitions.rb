class CreatePieceDefinitions < ActiveRecord::Migration[8.1]
  def change
    create_table :piece_definitions do |t|
      t.references :game_module, null: false, foreign_key: true
      t.references :deck, foreign_key: true
      t.string :gpid
      t.string :name
      t.string :slot_kind, null: false, default: "piece"
      t.json :palette_path, default: []
      t.text :type_string
      t.text :state_string
      t.json :traits, default: []
      t.integer :position, null: false, default: 0

      t.timestamps
    end
    add_index :piece_definitions, [ :game_module_id, :gpid ]
  end
end
