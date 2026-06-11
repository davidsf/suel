class CreateDecks < ActiveRecord::Migration[8.1]
  def change
    create_table :decks do |t|
      t.references :game_map, null: false, foreign_key: true
      t.string :name
      t.string :owning_board
      t.integer :x
      t.integer :y
      t.integer :width
      t.integer :height
      t.json :settings, default: {}

      t.timestamps
    end
  end
end
