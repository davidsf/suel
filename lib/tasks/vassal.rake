namespace :vassal do
  desc "Import every .vmod in a directory and report results: rake vassal:soak[/path/to/dir]"
  task :soak, [ :dir ] => :environment do |_t, args|
    dir = args[:dir] or abort "usage: rake vassal:soak[/path/to/dir]"
    Dir.glob(File.join(dir, "*.vmod")).sort.each do |path|
      game_module = GameModule.new
      game_module.package.attach(io: File.open(path), filename: File.basename(path), content_type: "application/zip")
      game_module.save!
      started = Time.current
      ModuleImportJob.perform_now(game_module)
      game_module.reload
      puts format(
        "%-55s %-7s %5.1fs maps=%d boards=%d decks=%d pieces=%d protos=%d scenarios=%d/%d piezas=%d avisos=%d",
        File.basename(path), game_module.status, Time.current - started,
        game_module.game_maps.count, game_module.boards.count, game_module.decks.count,
        game_module.piece_definitions.count, game_module.prototypes.count,
        game_module.scenarios.ready.count, game_module.scenarios.count,
        ScenarioPiece.joins(:scenario).where(scenarios: { game_module_id: game_module.id }).count,
        game_module.parse_warnings.size
      )
      puts "  ERROR: #{game_module.error_message}" if game_module.failed?
      game_module.parse_warnings.first(5).each { |w| puts "  aviso: #{w}" }
    ensure
      FileUtils.rm_rf(game_module.extracted_dir) if game_module&.persisted?
      game_module&.destroy
    end
  end

  desc "Build a small test fixture module from a real .vmod: rake vassal:make_fixture[/path/to/module.vmod]"
  task :make_fixture, [ :source ] => :environment do |_t, args|
    require "zip"

    source = args[:source] or abort "usage: rake vassal:make_fixture[/path/to/module.vmod]"
    dest = Rails.root.join("test", "fixtures", "files", "mini.vmod")
    max_image_bytes = 20.kilobytes
    max_images = 5

    FileUtils.rm_f(dest)
    images_taken = 0
    Zip::File.open(source) do |zip|
      smallest_vsav = zip.entries.select { |e| e.name.end_with?(".vsav") }.min_by(&:size)
      Zip::OutputStream.open(dest) do |out|
        zip.entries.each do |entry|
          next if entry.directory?
          keep =
            Vassal::ModuleArchive::BUILD_FILE_NAMES.include?(entry.name) ||
            entry.name == Vassal::ModuleArchive::MODULE_DATA ||
            entry == smallest_vsav ||
            (entry.name.start_with?("images/") && entry.size < max_image_bytes &&
              (images_taken += 1) <= max_images)
          next unless keep

          out.put_next_entry(entry.name)
          out.write entry.get_input_stream.read
        end
      end
    end
    puts "#{dest} (#{File.size(dest) / 1024} KB)"
  end
end
