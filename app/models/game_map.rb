class GameMap < ApplicationRecord
  belongs_to :game_module
  has_many :boards, -> { order(:position) }, dependent: :destroy
  has_many :decks, dependent: :destroy
  has_many :scenario_pieces, dependent: :nullify

  enum :kind, { map: "map", player_hand: "player_hand", private_map: "private" }, default: "map", prefix: :kind
end
