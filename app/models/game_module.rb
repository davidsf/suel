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

  private

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
