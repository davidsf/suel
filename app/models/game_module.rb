class GameModule < ApplicationRecord
  STATUSES = %w[pending extracting parsing ready failed].freeze

  broadcasts_refreshes

  has_one_attached :package

  has_many :game_maps, -> { order(:position) }, dependent: :destroy
  has_many :boards, through: :game_maps
  has_many :decks, through: :game_maps
  has_many :prototypes, dependent: :destroy
  has_many :piece_definitions, -> { order(:position) }, dependent: :destroy
  has_many :scenarios, dependent: :destroy
  has_many :games, dependent: :destroy

  enum :status, STATUSES.index_by(&:itself), default: "pending"

  validates :slug, presence: true, uniqueness: true
  validates :package, presence: true, on: :create

  before_validation :assign_slug, on: :create

  def to_param = slug

  # Directory where the .vmod contents are extracted (images, buildFile, scenarios...)
  def extracted_dir
    base = Rails.configuration.x.vassal.modules_dir
    base = base.call if base.respond_to?(:call)
    Pathname(base).join(id.to_s)
  end

  def extracted? = File.directory?(extracted_dir)

  # Reference chart windows (CRTs, terrain charts...) parsed at import time.
  def charts? = charts.present?

  # Dice buttons defined anywhere in the module (toolbar, folders, maps...),
  # derived at runtime from the persisted build_tree.
  def dice_buttons
    find_nodes(build_tree, "VASSAL.build.module.DiceButton").map do |node|
      attrs = node["attributes"] || {}
      {
        "name" => attrs["name"].presence || attrs["text"].presence || "Dados",
        "label" => attrs["text"].presence || attrs["name"].presence || "Dados",
        "n_dice" => attrs["nDice"].to_i.clamp(1, 100),
        "n_sides" => attrs["nSides"].to_i.clamp(2, 1000),
        "plus" => attrs["plus"].to_i,
        "report_total" => attrs["reportTotal"] == "true"
      }
    end.uniq
  end

  # Toolbar dropdown menus (VASSAL ToolbarMenu), derived at runtime from the
  # persisted build_tree. In VASSAL each menu hides the toolbar buttons whose
  # untranslated text matches an entry of menuItems (a SequenceEncoder list
  # with ',') and re-exposes them as menu entries; unmatched entries are
  # skipped. The visible label is "text" (empty in practice) — fall back to
  # tooltip, then the editor-only description. propertyGate/canDisable/hotkey
  # and nested menu-in-menu are deliberately ignored; menus defined inside a
  # Map reference map-internal buttons and simply match no map window.
  def toolbar_menus
    find_nodes(build_tree, "VASSAL.build.module.ToolbarMenu").filter_map do |node|
      attrs = node["attributes"] || {}
      decoder = Vassal::SequenceEncoder::Decoder.new(attrs["menuItems"].to_s, ",")
      items = []
      items << decoder.next_token("") while decoder.more_tokens?
      items = items.reject(&:blank?)
      next if items.empty?
      { "name" => attrs["text"].presence || attrs["tooltip"].presence || attrs["description"].presence,
        "icon" => attrs["icon"].presence, "items" => items }
    end
  end

  # Image-faced dice (SpecialDiceButton → SpecialDie → SpecialDieFace). Each
  # button holds one or more dice; each die is a list of faces {value,text,icon}.
  def special_dice
    find_nodes(build_tree, "VASSAL.build.module.SpecialDiceButton").map do |node|
      attrs = node["attributes"] || {}
      dice = find_nodes(node, "VASSAL.build.module.SpecialDie").map do |die|
        find_nodes(die, "VASSAL.build.module.SpecialDieFace").map do |face|
          fa = face["attributes"] || {}
          { "value" => fa["value"].to_i, "text" => fa["text"].presence, "icon" => fa["icon"].presence }
        end
      end.reject(&:empty?)
      { "name" => attrs["name"].presence || attrs["text"].presence || "Dado",
        "label" => attrs["text"].presence || attrs["name"].presence || "Dado",
        "dice" => dice }
    end.reject { |b| b["dice"].empty? }
  end

  # The module's box art / splash, derived at runtime from the persisted
  # build_tree. VASSAL stores it as the Documentation AboutScreen's fileName,
  # which is an image resource (resolved under images/). Returns a path relative
  # to the extracted dir, or nil when the module declares no about screen.
  def cover_image
    node = find_nodes(build_tree, "VASSAL.build.module.documentation.AboutScreen").first
    file = node&.dig("attributes", "fileName").to_s.delete_prefix("/")
    return if file.blank?
    file.start_with?("images/") ? file : "images/#{file}"
  end

  # Player sides from the module's PlayerRoster, derived at runtime from the
  # persisted build_tree (the importer doesn't store them separately). Modules
  # without a roster get two generic sides so games are always creatable.
  def sides
    roster = find_nodes(build_tree, "VASSAL.build.module.PlayerRoster").first
    entries = (roster&.dig("children") || [])
      .filter_map { |node| node["text"] if node["class"] == "entry" }
    entries.presence || [ "Bando A", "Bando B" ]
  end

  # The marker PieceDefinition a PlaceMarker trait's spec points to. The spec is
  # a "ClassName:Label" breadcrumb ending in the slot ("…PieceSlot:Disrupted
  # Marker"); the intermediate widget labels match the slot's stored
  # palette_path. A purely numeric spec is a bare gpid (some modules store it so).
  def piece_definition_for_spec(spec)
    spec = spec.to_s
    return if spec.blank?
    return piece_definitions.find_by(gpid: spec) if spec.match?(/\A\d+\z/)

    labels = spec.split("/").map { |segment| segment.split(":", 2).last.to_s }
    name = labels.last
    path = labels[1..-2] || [] # drop the PieceWindow label and the leaf slot name
    by_name = piece_definitions.where(name: name)
    by_name.find { |definition| definition.palette_path == path } || by_name.first
  end

  private

  # Depth-first search over the persisted build_tree json.
  def find_nodes(node, class_name)
    return [] unless node.is_a?(Hash)
    found = node["class"] == class_name ? [ node ] : []
    (node["children"] || []).each { |child| found.concat(find_nodes(child, class_name)) }
    found
  end

  def assign_slug
    return if slug.present?
    base = (name.presence || package&.filename&.base || "module").to_s.parameterize
    base = "module" if base.blank?
    candidate = base
    n = 1
    candidate = "#{base}-#{n += 1}" while self.class.exists?(slug: candidate)
    self.slug = candidate
  end
end
