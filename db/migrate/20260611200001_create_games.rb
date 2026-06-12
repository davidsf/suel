class CreateGames < ActiveRecord::Migration[8.1]
  def change
    create_table :games do |t|
      t.references :game_module, null: false, foreign_key: true
      t.references :scenario, null: false, foreign_key: true
      t.references :creator, null: false, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.string :status, null: false, default: "open"

      t.timestamps
    end
  end
end
