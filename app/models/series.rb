# frozen_string_literal: true

# A writer's multi-part series: an ordered run of their own breaths
# ("The Gospel and Material Prosperity", parts 1–3). A breath is in at most
# one series (posts.series_id) and posts.series_position is its part number:
# the writer's own numbering, gaps included (parts 1, 2, 3, 4, 6 when part 5
# was never posted). Parts are listed in that order.
#
# Who sees which parts: readers only ever see parts that are fine to show on a
# public page (Post.series_listable: live, approved, signed, not a prayer
# request, not in a private room). The author also sees their own drafts,
# held breaths and private-room parts, marked as visible only to them.
class Series < ApplicationRecord
  extend FriendlyId
  friendly_id :slug_source, use: :slugged

  TITLE_MAX = 120
  DESCRIPTION_MAX = 280

  belongs_to :user
  has_many :posts, -> { order(:series_position, :published_at, :id) }, inverse_of: :series

  validates :title, presence: true, length: { maximum: TITLE_MAX }
  validates :description, length: { maximum: DESCRIPTION_MAX }
  validates :slug, presence: true, uniqueness: true
  validate :title_unique_for_author

  # Deleting a series keeps its breaths, just ungrouped.
  before_destroy { posts.update_all(series_id: nil, series_position: nil) }

  def title=(value)
    super(value.to_s.squish.presence)
  end

  # Series that have something a reader can see.
  scope :with_listable_parts, -> { where(id: Post.series_listable.where.not(series_id: nil).select(:series_id)) }

  # Series a signed-out reader (or a search engine) can open: a public part,
  # by an active member whose profile isn't private.
  scope :publicly_listed, -> {
    with_listable_parts.where(user_id: User.active.select(:id))
                       .where.not(user_id: Profile.where(public_profile: false).select(:user_id))
  }

  # The parts this viewer may see, in order. The author sees all of them.
  def parts_for(viewer)
    scope = posts.includes(:room, :rich_text_content, :ai_moderation_review)
    (author?(viewer) ? scope : scope.merge(Post.series_listable)).to_a
  end

  # The series page exists for a reader when it has a part they may see and
  # the author's profile is open to them (same rule as the profile's breaths).
  def readable_by?(viewer)
    return true if author?(viewer)
    return false unless user&.active?
    return false if viewer && viewer.blocked_user_ids.include?(user_id)
    return false if user.profile&.public_profile? == false && !viewer&.admin_or_moderator?

    parts_for(viewer).any?
  end

  def author?(viewer)
    viewer.present? && viewer.id == user_id
  end

  # Where a newly added breath goes: after the last part, unless its title
  # carries a part number not yet taken ("… (5)" posted after part 6 slots
  # in between; "… (6)" after part 4 leaves part 5 as a gap).
  def next_position(title: nil)
    taken = posts.where.not(series_position: nil).pluck(:series_position)
    parsed = SeriesTitle.parse(title)
    numbered = parsed.part if parsed && (parsed.key.nil? || parsed.key == SeriesTitle.key_for(self.title))
    numbered&.positive? && !taken.include?(numbered) ? numbered : taken.max.to_i + 1
  end

  # Numbers the given parts (in the order given) with the part numbers their
  # titles carry, gaps kept; a part with no number, or one already taken,
  # counts on from the part before it. Columns only.
  def number_parts!(ordered_posts)
    taken = []
    last = 0
    transaction do
      ordered_posts.each do |post|
        number = SeriesTitle.parse(SeriesTitle.effective_title(post))&.part
        unless number&.positive? && !taken.include?(number)
          number = last + 1
          number += 1 while taken.include?(number)
        end
        taken << number
        last = number
        Post.where(id: post.id).update_all(series_id: id, series_position: number)
      end
    end
  end

  # Move a part one place up (-1) or down (+1): it swaps part numbers with
  # its neighbour, so gaps in the numbering stay where they are.
  def move!(post, offset)
    rows = posts.reorder(:series_position, :published_at, :id).pluck(:id, :series_position)
    from = rows.index { |id, _| id == post.id }
    return false unless from

    to = from + offset
    return false if to.negative? || to >= rows.size

    transaction do
      if rows[from][1] == rows[to][1] || rows.any? { |_, number| number.nil? }
        # Muddled numbering (two parts sharing a number): count 1, 2, 3 … again.
        rows.insert(to, rows.delete_at(from))
        rows.each_with_index { |(id, _), index| Post.where(id: id).update_all(series_position: index + 1) }
      else
        Post.where(id: rows[from][0]).update_all(series_position: rows[to][1])
        Post.where(id: rows[to][0]).update_all(series_position: rows[from][1])
      end
    end
    true
  end

  # A slug from plain text, so a title in Unicode bold still gets a readable address.
  def slug_source
    SeriesTitle.normalize(title).presence || "series-#{SecureRandom.hex(3)}"
  end

  # Renaming keeps the address, so shared links keep working.
  def should_generate_new_friendly_id?
    slug.blank?
  end

  private

  def title_unique_for_author
    return if title.blank? || user_id.blank?

    key = SeriesTitle.key_for(title)
    clash = Series.where(user_id: user_id).where.not(id: id).any? { |s| SeriesTitle.key_for(s.title) == key }
    errors.add(:title, "matches one of your other series") if clash
  end
end
