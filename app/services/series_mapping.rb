# frozen_string_literal: true

# An explicit, hand-checked list of series (config/series_mapping.yml) for
# `rake series:suggest`, for the parts title detection can't see: a part
# with no number in its title, a title only in the body, a run with gaps.
#
#   entries = SeriesMapping.load
#   entries.each { |entry| puts entry.report_lines; entry.apply! }
class SeriesMapping
  DEFAULT_PATH = Rails.root.join("config/series_mapping.yml")

  # One planned part: the post (nil when missing), its part number, and why
  # it won't join (nil when it will).
  Part = Data.define(:post_id, :post, :number, :problem)

  attr_reader :author_name, :title, :note, :excluded

  def self.load(path = DEFAULT_PATH)
    rows = YAML.safe_load_file(path.to_s) || []
    raise ArgumentError, "#{path}: expected a list of series" unless rows.is_a?(Array)

    rows.map { |row| new(row) }
  end

  def initialize(row)
    @author_name = row.fetch("author").to_s
    @title = row.fetch("title").to_s.squish
    @numbers = case (parts = row.fetch("parts"))
    when Hash then parts.to_h { |id, number| [ Integer(id), Integer(number) ] }
    when Array then parts.each_with_index.to_h { |id, index| [ Integer(id), index + 1 ] }
    else raise ArgumentError, "#{@title}: parts must be a list or a map"
    end
    @excluded = (row["exclude"] || {}).to_h { |id, reason| [ Integer(id), reason.to_s ] }
    @create = row.fetch("create", true) != false
    @note = row["note"].to_s.presence
  end

  def create? = @create

  # Every post id the entry mentions, joined or left out.
  def post_ids = @numbers.keys + @excluded.keys

  def author
    return @author if defined?(@author)

    @author = User.where("LOWER(username) = ?", author_name.downcase).first
  end

  def existing_series
    return unless author

    key = SeriesTitle.key_for(title)
    author.series.find { |series| SeriesTitle.key_for(series.title) == key }
  end

  def parts
    @parts ||= begin
      posts = Post.where(id: @numbers.keys).includes(:user, :room, :series, :rich_text_content).index_by(&:id)
      series = existing_series
      @numbers.map do |id, number|
        post = posts[id]
        problem = if post.nil? then "no such post"
        elsif author.nil? || post.user_id != author.id then "by @#{post.user&.username}, not @#{author_name}"
        elsif post.anonymous? then "anonymous (would show the author's name)"
        elsif post.series_id && post.series_id != series&.id then "already in \"#{post.series.title}\""
        end
        Part.new(post_id: id, post: post, number: number, problem: problem)
      end
    end
  end

  def joining = parts.reject(&:problem)

  def report_lines
    status = if !create? then "report only, not created"
    elsif author.nil? then "no member @#{author_name}"
    elsif existing_series then "existing series"
    else "new series"
    end
    numbers = @numbers.values
    gaps = (1..numbers.max.to_i).to_a - numbers
    lines = [ "@#{author_name} · \"#{title}\" (#{status}, #{pluralize(parts.size, 'part')}" \
              "#{", missing part #{gaps.join(', ')}" if gaps.any?})" ]
    lines << "    note: #{note}" if note
    parts.each do |part|
      shown = part.post ? SeriesTitle.effective_title(part.post).to_s.truncate(80) : "-"
      flag = if part.problem then "  [skipped: #{part.problem}]"
      elsif part.post.series_id then "  [already in it]"
      elsif !part.post.series_listable? then "  [joins; readers won't see it: #{part.post.prayer? ? 'prayer request' : part.post.status}]"
      end
      lines << format("  Part %-2d #%-5d %s%s", part.number, part.post_id, shown, flag)
    end
    @excluded.each { |id, reason| lines << format("  left out #%-5d %s", id, reason) }
    lines
  end

  # Creates (or reuses) the series and puts the parts in with their numbers.
  # Columns only, so an old breath that fails today's validations still joins.
  # Returns [series_created?, parts_joined].
  def apply!
    return [ false, 0 ] unless create? && author && joining.any?

    Series.transaction do
      series = existing_series
      created = series.nil?
      series ||= author.series.create!(title: title)
      joining.each { |part| part.post.update_columns(series_id: series.id, series_position: part.number) }
      [ created, joining.size ]
    end
  end

  private

  def pluralize(count, word) = ActionController::Base.helpers.pluralize(count, word)
end
