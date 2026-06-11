class PieceDefinition < ApplicationRecord
  belongs_to :game_module
  belongs_to :deck, optional: true

  enum :slot_kind, { piece: "piece", card: "card" }, default: "piece"

  # Trait kinds parsed by Vassal::Piece::TraitRegistry; unknown traits keep kind: "unknown"
  def basic_trait = traits.find { |t| t["kind"] == "basic" }
  def image_filename = basic_trait&.dig("image")
end
