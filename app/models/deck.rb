class Deck < ApplicationRecord
  belongs_to :game_map
  has_one :game_module, through: :game_map
  has_many :piece_definitions, -> { order(:position) }, dependent: :nullify

  def face_down? = settings["faceDown"] == "Always"

  # VASSAL DrawPile "drawFaceUp": drawn pieces are revealed on the table.
  def draw_face_up? = settings["drawFaceUp"].to_s == "true"
end
