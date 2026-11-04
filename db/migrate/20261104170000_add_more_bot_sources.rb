# More outlets for the Updates bots, so the tab stays full all day.
class AddMoreBotSources < ActiveRecord::Migration[8.1]
  SOURCES = [
    [ "news", "world", "The Guardian", "https://www.theguardian.com/world/rss" ],
    [ "news", "world", "The New York Times", "https://rss.nytimes.com/services/xml/rss/nyt/World.xml" ],
    [ "news", "world", "Sky News", "https://feeds.skynews.com/feeds/rss/world.xml" ],
    [ "news", "world", "The Independent", "https://www.independent.co.uk/news/world/rss" ],
    [ "news", "world", "UN News", "https://news.un.org/feed/subscribe/en/news/all/rss.xml" ],
    [ "news", "politics", "The Guardian Politics", "https://www.theguardian.com/politics/rss" ],
    [ "news", "politics", "NYT Politics", "https://rss.nytimes.com/services/xml/rss/nyt/Politics.xml" ],
    [ "news", "tech", "Ars Technica", "https://feeds.arstechnica.com/arstechnica/index" ],
    [ "news", "tech", "The Guardian Tech", "https://www.theguardian.com/uk/technology/rss" ],
    [ "news", "tech", "Engadget", "https://www.engadget.com/rss.xml" ],
    [ "news", "science", "NYT Science", "https://rss.nytimes.com/services/xml/rss/nyt/Science.xml" ],
    [ "news", "science", "Smithsonian", "https://www.smithsonianmag.com/rss/latest_articles/" ],
    [ "news", "health", "NYT Health", "https://rss.nytimes.com/services/xml/rss/nyt/Health.xml" ],
    [ "news", "business", "NYT Business", "https://rss.nytimes.com/services/xml/rss/nyt/Business.xml" ],
    [ "news", "business", "CNBC", "https://www.cnbc.com/id/100727362/device/rss/rss.html" ],
    [ "news", "food", "The Guardian Food", "https://www.theguardian.com/food/rss" ],
    [ "news", "food", "NYT Food", "https://rss.nytimes.com/services/xml/rss/nyt/DiningandWine.xml" ],
    [ "news", "faith", "Religion News Service", "https://religionnews.com/feed/" ],
    [ "news", "faith", "Catholic News Agency", "https://www.catholicnewsagency.com/rss/news.xml" ],
    [ "sports", nil, "BBC Football", "https://feeds.bbci.co.uk/sport/football/rss.xml" ],
    [ "sports", nil, "The Guardian Sport", "https://www.theguardian.com/sport/rss" ],
    [ "sports", nil, "ESPN Soccer", "https://www.espn.com/espn/rss/soccer/news" ],
    [ "sports", nil, "ESPN NBA", "https://www.espn.com/espn/rss/nba/news" ],
    [ "sports", nil, "Sky Sports Football", "https://www.skysports.com/rss/11095" ],
    [ "sports", nil, "Yahoo Sports", "https://sports.yahoo.com/rss/" ],
    [ "jobs", nil, "Jobicy", "https://jobicy.com/?feed=job_feed" ],
    [ "courses", nil, "Coursera", "https://blog.coursera.org/feed/" ],
    [ "courses", nil, "Opportunities Corners", "https://opportunitiescorners.com/feed/" ]
  ].freeze

  def up
    now = Time.current
    rows = SOURCES.map do |bot, topic, name, url|
      { bot: bot, topic: topic, name: name, url: url, format: "rss", active: true, created_at: now, updated_at: now }
    end
    Class.new(ActiveRecord::Base) { self.table_name = "bot_sources" }.insert_all(rows, unique_by: :url)
  end

  def down
    urls = SOURCES.map(&:last)
    execute "DELETE FROM bot_items WHERE bot_source_id IN (SELECT id FROM bot_sources WHERE url IN (#{urls.map { |u| connection.quote(u) }.join(',')}))"
    execute "DELETE FROM bot_sources WHERE url IN (#{urls.map { |u| connection.quote(u) }.join(',')})"
  end
end
