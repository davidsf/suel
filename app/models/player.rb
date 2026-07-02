class Player < ApplicationRecord
  belongs_to :game
  belongs_to :user

  validates :side, presence: true
  validates :user_id, uniqueness: { scope: :game_id, message: :already_in_game }
  validates :side, uniqueness: { scope: :game_id, message: :taken_in_game }
  validate :side_must_exist

  private

  def side_must_exist
    return if game.nil? || game.sides.include?(side)
    errors.add(:side, :not_in_module)
  end
end
