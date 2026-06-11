module Vassal
  # Image metadata/previews via libvips, loaded lazily: if the system library
  # is missing everything degrades to nil and the views fall back to natural
  # image sizes.
  module Images
    def self.available?
      return @available if defined?(@available)
      @available =
        begin
          require "vips"
          true
        rescue LoadError
          false
        end
    end

    def self.dimensions(path)
      return nil unless available?
      image = Vips::Image.new_from_file(path.to_s)
      [ image.width, image.height ]
    rescue StandardError
      nil
    end

    # Writes a downscaled preview next to nothing in particular — caller picks
    # the destination. Returns false when vips is unavailable or fails.
    def self.preview(source, destination, max_width: 2000)
      return false unless available?
      image = Vips::Image.thumbnail(source.to_s, max_width)
      image.write_to_file(destination.to_s)
      true
    rescue StandardError
      false
    end
  end
end
