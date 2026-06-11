# Pure-Ruby reimplementation of the VASSAL module format readers:
# .vmod archives, buildFile XML, serialized piece definitions and .vsav saves.
module Vassal
  class Error < StandardError; end

  # The archive is not a valid .vmod (not a zip, no buildFile, etc.)
  class InvalidModuleError < Error; end

  # A serialized string (piece definition, save command...) could not be decoded
  class ParseError < Error; end
end
