module PiecesHelper
  # Currently visible image of a layer trait: VASSAL's value is the 1-based
  # active level (negative when inactive).
  def layer_image(trait)
    value = trait["value"].to_i
    active = trait["always_active"] || value.positive?
    return nil unless active

    index = value.abs - 1
    images = trait["images"] || []
    images[index.clamp(0, images.length - 1)].presence
  end

  # Rotation in CSS degrees (VASSAL stores counterclockwise-negative angles).
  def piece_rotation(traits)
    angle = traits.find { |t| t["kind"] == "rotate" }&.dig("angle").to_f
    angle.zero? ? nil : -angle
  end

  def piece_labels(traits)
    traits.select { |t| t["kind"] == "label" && t["text"].present? }
  end

  def piece_back_image(traits)
    traits.find { |t| t["kind"] == "mask" }&.dig("back_image")
  end
end
