class CreateBoards < ActiveRecord::Migration[8.1]
  def change
    create_table :boards do |t|
      t.references :game_map, null: false, foreign_key: true
      t.string :name
      t.string :image_filename
      t.integer :width
      t.integer :height
      t.boolean :reversible, null: false, default: false
      t.json :grid
      t.integer :position, null: false, default: 0

      t.timestamps
    end
  end
end
