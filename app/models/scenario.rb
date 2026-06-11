class Scenario < ApplicationRecord
  belongs_to :game_module
  has_many :scenario_pieces, -> { order(:z_order) }, dependent: :destroy

  enum :kind, { vsav: "vsav", module_setup: "module_setup" }, default: "vsav"
  enum :status, %w[pending ready failed].index_by(&:itself), default: "pending"
end
