module Vassal
  # Port of VASSAL.tools.io.{Obfuscating,Deobfuscating}*Stream: saved games are
  # "obfuscated" as "!VCSK" + a random key in 2 hex chars + each byte XOR key
  # written as 2 hex chars. Plain text passes through unchanged.
  module Obfuscation
    HEADER = "!VCSK".freeze

    def self.deobfuscate(data)
      data = data.b
      return data.force_encoding(Encoding::UTF_8) unless data.start_with?(HEADER)

      hex = data[HEADER.length..].delete("^0-9a-fA-F")
      raise ParseError, "odd obfuscated payload length" if hex.length.odd?

      bytes = [ hex ].pack("H*").bytes
      key = bytes.shift
      raise ParseError, "missing obfuscation key" if key.nil?

      bytes.map { |b| b ^ key }.pack("C*").force_encoding(Encoding::UTF_8)
    end

    def self.obfuscate(data, key: 0xA5)
      hex = data.b.bytes.map { |b| format("%02x", b ^ key) }.join
      "#{HEADER}#{format('%02x', key)}#{hex}"
    end
  end
end
