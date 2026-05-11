# frozen_string_literal: true

class ChurchHistoryFigure < ApplicationRecord
  enum :era, {
    apostolic: 0,    # 33–100   apostles, very early
    patristic: 1,    # 100–500  early church fathers
    medieval:  2,    # 500–1500 monks, mystics, schoolmen
    reformation: 3,  # 1500–1700 reformers
    modern:    4,    # 1700–1900 awakenings, world missions
    revivalists: 5   # 1900–now  pentecostal, modern revivalists, witnesses
  }, prefix: :era

  validates :name, :slug, :era, presence: true
  validates :slug, uniqueness: true

  before_validation :set_slug, on: :create

  scope :ordered, -> { order(:era, :sort_order, :birth_year, :name) }

  ERA_LABELS = {
    "apostolic"   => "Apostolic (33–100)",
    "patristic"   => "Patristic (100–500)",
    "medieval"    => "Medieval (500–1500)",
    "reformation" => "Reformation (1500–1700)",
    "modern"      => "Modern (1700–1900)",
    "revivalists" => "Revivalists (1900–today)"
  }.freeze

  ERA_DESCRIPTIONS = {
    "apostolic"   => "The first generation after Christ. Apostles, evangelists, and the first martyrs.",
    "patristic"   => "The church fathers — Augustine, Athanasius, Chrysostom. Creeds, councils, defenders of the faith.",
    "medieval"    => "Monks, mystics, and scholars. Benedict, Francis, Aquinas, Wycliffe — the church through the long centuries.",
    "reformation" => "Luther, Calvin, Tyndale, Knox. Scripture back into the hands of the people.",
    "modern"      => "Awakenings and missions. Wesley, Whitefield, Edwards, Carey, Taylor, Spurgeon, Moody.",
    "revivalists" => "Pentecostal outpouring and modern witnesses. Seymour, Wigglesworth, McPherson, Kuhlman, Graham, Bonnke, ten Boom, Bonhoeffer."
  }.freeze

  def years
    return nil unless birth_year || death_year
    "#{birth_year || "?"}–#{death_year || "today"}"
  end

  private

  def set_slug
    self.slug ||= name.to_s.parameterize
  end
end
