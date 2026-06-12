class Player < ApplicationRecord
  belongs_to :game
  belongs_to :user

  validates :side, presence: true
  validates :user_id, uniqueness: { scope: :game_id, message: "ya está en la partida" }
  validates :side, uniqueness: { scope: :game_id, message: "ya está ocupado" }
  validate :side_must_exist

  private

  def side_must_exist
    return if game.nil? || game.sides.include?(side)
    errors.add(:side, "no existe en este módulo")
  end
end
