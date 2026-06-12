class CreatePlayers < ActiveRecord::Migration[8.1]
  def change
    create_table :players do |t|
      t.references :game, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :side, null: false

      t.timestamps
    end
    add_index :players, [ :game_id, :user_id ], unique: true
    add_index :players, [ :game_id, :side ], unique: true
  end
end
