class ModuleImportJob < ApplicationJob
  queue_as :default

  def perform(game_module)
    @game_module = game_module

    # progress_note stores an i18n key (modules.progress.*): the note outlives
    # this job and is rendered per-viewer locale by game_modules/_status.
    step!("extracting", "extracting_archive")
    extract_package

    step!("parsing", "reading_metadata")
    read_module_data

    step!("parsing", "parsing_module")
    GameModuleImporter.new(@game_module).import

    @game_module.update!(status: "ready", progress_note: nil, error_message: nil)
  rescue => e
    @game_module.update!(status: "failed", error_message: "#{e.class}: #{e.message}")
    raise unless e.is_a?(Vassal::Error)
  end

  private

  def step!(status, note)
    @game_module.update!(status:, progress_note: note)
  end

  def extract_package
    dir = @game_module.extracted_dir
    FileUtils.rm_rf(dir)
    @game_module.package.open do |file|
      Vassal::ModuleArchive.open(file.path) do |archive|
        archive.extract_all(dir)
      end
    end
  end

  def read_module_data
    archive_dir = @game_module.extracted_dir
    module_data_path = File.join(archive_dir, "moduledata")
    return unless File.file?(module_data_path)

    data = Vassal::ModuleData.parse(File.read(module_data_path))
    @game_module.update!(
      name: data.name || @game_module.name,
      version: data.version,
      vassal_version: data.vassal_version,
      description: data.description
    )
  end
end
