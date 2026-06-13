class AddCardStateToGamePieces < ActiveRecord::Migration[8.1]
  def change
    add_reference :game_pieces, :deck, foreign_key: true, null: true
    add_column :game_pieces, :deck_position, :integer
    add_column :game_pieces, :hand_side, :string

    add_index :game_pieces, [ :game_id, :deck_id ]
    add_index :game_pieces, [ :game_id, :hand_side ]
  end
end
