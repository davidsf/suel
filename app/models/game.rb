class Game < ApplicationRecord
  COPY_BATCH_SIZE = 500

  belongs_to :game_module
  belongs_to :scenario
  belongs_to :creator, class_name: "User"
  has_many :players, dependent: :destroy
  has_many :game_pieces, dependent: :destroy

  enum :status, %w[open finished].index_by(&:itself), default: "open"

  validates :name, presence: true
  validate :scenario_must_be_ready, on: :create

  delegate :sides, to: :game_module

  def free_sides
    sides - players.pluck(:side)
  end

  def player_for(user)
    user && players.find_by(user: user)
  end

  # Copies the scenario's placed pieces as this game's mutable pieces, baking
  # in the same stack-spread offsets the scenario viewer computes at render
  # time (stored coordinates must be final: broadcasts replace pieces 1:1).
  def copy_scenario_pieces!
    now = Time.current
    stack_offsets = Hash.new(0)
    rows = scenario.scenario_pieces.where.not(game_map_id: nil).order(:z_order).map do |piece|
      offset = stack_offsets["#{piece.game_map_id}/#{piece.x},#{piece.y}"]
      stack_offsets["#{piece.game_map_id}/#{piece.x},#{piece.y}"] += 1
      {
        game_id: id,
        game_map_id: piece.game_map_id,
        board_id: piece.board_id,
        gpid: piece.gpid,
        name: piece.name,
        x: piece.x.to_i + offset * 6,
        y: piece.y.to_i - offset * 6,
        z_order: piece.z_order,
        type_string: piece.type_string,
        traits: piece.traits,
        created_at: now, updated_at: now
      }
    end
    rows.each_slice(COPY_BATCH_SIZE) { |slice| GamePiece.insert_all(slice) }
  end

  private

  def scenario_must_be_ready
    errors.add(:scenario, "no está listo") unless scenario&.ready?
  end
end
