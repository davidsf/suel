require "zip"

module Vassal
  # Read-only access to a .vmod archive (a ZIP file).
  #
  # Locates the build file (modern "buildFile.xml" or legacy "buildFile"),
  # the "moduledata" metadata file, and extracts the whole archive safely
  # (guarding against zip-slip and oversized entries).
  class ModuleArchive
    BUILD_FILE_NAMES = %w[buildFile.xml buildFile].freeze
    MODULE_DATA = "moduledata".freeze
    MAX_ENTRY_SIZE = 512.megabytes

    def self.open(path)
      archive = new(path)
      return yield(archive) if block_given?
      archive
    end

    def initialize(path)
      @path = path.to_s
      raise InvalidModuleError, "no such file: #{@path}" unless File.file?(@path)
      @zip = Zip::File.open(@path)
    rescue Zip::Error => e
      raise InvalidModuleError, "not a zip archive: #{e.message}"
    end

    def build_file_name
      @build_file_name ||= BUILD_FILE_NAMES.find { |name| @zip.find_entry(name) } or
        raise InvalidModuleError, "no buildFile.xml or buildFile entry found"
    end

    def build_file_xml
      read(build_file_name)
    end

    def module_data_xml
      read(MODULE_DATA) if @zip.find_entry(MODULE_DATA)
    end

    def entry_names
      @zip.entries.reject(&:directory?).map(&:name)
    end

    def save_file_names
      entry_names.select { |n| n.downcase.end_with?(".vsav") }
    end

    def image_names
      entry_names.select { |n| n.start_with?("images/") }
    end

    def read(entry_name)
      entry = @zip.find_entry(entry_name) or raise InvalidModuleError, "missing entry: #{entry_name}"
      raise InvalidModuleError, "entry too large: #{entry_name}" if entry.size > MAX_ENTRY_SIZE
      entry.get_input_stream.read
    end

    # Extracts every file entry under dest_dir, refusing paths that escape it.
    def extract_all(dest_dir)
      dest = File.expand_path(dest_dir)
      FileUtils.mkdir_p(dest)
      @zip.entries.each do |entry|
        next if entry.directory?
        raise InvalidModuleError, "entry too large: #{entry.name}" if entry.size > MAX_ENTRY_SIZE

        target = File.expand_path(File.join(dest, entry.name))
        unless target.start_with?(dest + File::SEPARATOR)
          raise InvalidModuleError, "unsafe zip entry path: #{entry.name}"
        end

        FileUtils.mkdir_p(File.dirname(target))
        entry.extract(target) { true } # overwrite
      end
      dest
    end

    def close
      @zip.close
    end
  end
end
