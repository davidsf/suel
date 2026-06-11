class CreateGameModules < ActiveRecord::Migration[8.1]
  def change
    create_table :game_modules do |t|
      t.string :name
      t.string :slug, null: false
      t.string :version
      t.string :vassal_version
      t.text :description
      t.string :status, null: false, default: "pending"
      t.text :error_message
      t.string :progress_note
      t.json :parse_warnings, default: []
      t.json :build_tree

      t.timestamps
    end
    add_index :game_modules, :slug, unique: true
  end
end
