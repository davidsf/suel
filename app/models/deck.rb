class Deck < ApplicationRecord
  belongs_to :game_map
  has_one :game_module, through: :game_map
  has_many :piece_definitions, -> { order(:position) }, dependent: :nullify

  def face_down? = settings["faceDown"] == "Always"
end
