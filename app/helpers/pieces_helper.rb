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

  # Labels to draw, with their $property$ references resolved. A label that
  # resolves to blank or "0" is dropped (e.g. an unhit hit-counter), so a
  # counter only appears once it matters.
  def piece_labels(traits)
    props = piece_properties(traits)
    traits.filter_map do |trait|
      next unless trait["kind"] == "label" && trait["text"].present?
      resolved = resolve_properties(trait["text"], props)
      next if resolved.blank? || resolved == "0"
      trait.merge("resolved" => resolved)
    end
  end

  # Inline style placing a label at its VASSAL corner (vertical t/c/b,
  # horizontal l/c/r) with its size, colors and rotation.
  def piece_label_style(label)
    transform = []
    parts = []
    case label["vertical_pos"]
    when "t" then parts << "top:0"
    when "b" then parts << "bottom:0; top:auto"
    else parts << "top:50%"; transform << "translateY(-50%)"
    end
    case label["horizontal_pos"]
    when "l" then parts << "left:0"
    when "r" then parts << "right:0; left:auto"
    else parts << "left:50%"; transform << "translateX(-50%)"
    end
    parts << "font-size:#{label['font_size']}px" if label["font_size"]
    parts << "color:rgb(#{label['fg']})" if label["fg"].present?
    parts << "background:rgb(#{label['bg']}); padding:0 2px" if label["bg"].present?
    rotate = label["rotate"].to_i
    transform << "rotate(#{-rotate}deg)" if rotate.nonzero?
    parts << "transform:#{transform.empty? ? 'none' : transform.join(' ')}"
    parts.join("; ")
  end

  # Property values a label can interpolate: per-piece dynamic properties,
  # markers, and basic properties/name.
  def piece_properties(traits)
    props = {}
    traits.each do |trait|
      case trait["kind"]
      when "dynamic_property" then props[trait["name"]] = trait["value"].to_s
      when "marker" then (trait["properties"] || {}).each { |k, v| props[k] = v.to_s }
      when "basic"
        props["pieceName"] = trait["name"].to_s if trait["name"].present?
        (trait["properties"] || {}).each { |k, v| props[k] = v.to_s }
      end
    end
    props
  end

  # Replaces $name$ tokens with property values; unknown tokens are left as-is.
  def resolve_properties(text, props)
    text.to_s.gsub(/\$([^$]+)\$/) { props[Regexp.last_match(1)] || Regexp.last_match(0) }
  end

  def piece_back_image(traits)
    traits.find { |t| t["kind"] == "mask" }&.dig("back_image")
  end
end
