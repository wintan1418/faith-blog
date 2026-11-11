# frozen_string_literal: true

# The AI-written figure quotes included misattributions (a Bible verse given
# as Whitefield's words, Davy Crockett's line given to Müller, legends such
# as Francis's "use words") and modern Bible wording. Correct two, and clear
# the doubtful ones so the quote box is hidden for those figures.
class CorrectChurchHistoryQuotes < ActiveRecord::Migration[8.1]
  CORRECTIONS = {
    "Peter the Apostle" => "Lord, to whom shall we go? thou hast the words of eternal life. (John 6:68)",
    "Paul the Apostle" => "For I am persuaded, that neither death, nor life, nor angels, nor principalities, " \
                          "nor powers, nor things present, nor things to come, nor height, nor depth, nor any " \
                          "other creature, shall be able to separate us from the love of God, which is in " \
                          "Christ Jesus our Lord. (Romans 8:38-39)",
    "Athanasius of Alexandria" => "He was made man that we might be made God."
  }.freeze

  DOUBTFUL = [
    "Justin Martyr", "Origen of Alexandria", "Boniface", "Bernard of Clairvaux", "Francis of Assisi",
    "Thomas Aquinas", "Catherine of Siena", "Ulrich Zwingli", "Menno Simons", "Thomas Cranmer", "John Calvin",
    "George Whitefield", "Charles Wesley", "Mary Slessor", "George Müller", "Charles F. Parham", "Evan Roberts",
    "Aimee Semple McPherson", "William Branham", "Reinhard Bonnke", "C. S. Lewis"
  ].freeze

  def up
    CORRECTIONS.each do |name, quote|
      execute "UPDATE church_history_figures SET featured_quote = #{connection.quote(quote)} " \
              "WHERE name = #{connection.quote(name)}"
    end
    names = DOUBTFUL.map { |name| connection.quote(name) }.join(", ")
    execute "UPDATE church_history_figures SET featured_quote = NULL WHERE name IN (#{names})"
  end

  def down
    # The old quotes were wrong; nothing to restore.
  end
end
