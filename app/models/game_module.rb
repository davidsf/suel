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

  # Player sides from the module's PlayerRoster, derived at runtime from the
  # persisted build_tree (the importer doesn't store them separately). Modules
  # without a roster get two generic sides so games are always creatable.
  def sides
    roster = find_nodes(build_tree, "VASSAL.build.module.PlayerRoster").first
    entries = (roster&.dig("children") || [])
      .filter_map { |node| node["text"] if node["class"] == "entry" }
    entries.presence || [ "Bando A", "Bando B" ]
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
