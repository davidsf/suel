class CreatePrototypes < ActiveRecord::Migration[8.1]
  def change
    create_table :prototypes do |t|
      t.references :game_module, null: false, foreign_key: true
      t.string :name, null: false
      t.text :type_string
      t.text :state_string

      t.timestamps
    end
    add_index :prototypes, [ :game_module_id, :name ], unique: true
  end
end
