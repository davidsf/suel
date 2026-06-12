class CreateGameEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :game_events do |t|
      t.references :game, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :kind, null: false, default: "roll"
      t.text :body, null: false
      t.json :payload, default: {}

      t.timestamps
    end
    add_index :game_events, [ :game_id, :created_at ]
  end
end
