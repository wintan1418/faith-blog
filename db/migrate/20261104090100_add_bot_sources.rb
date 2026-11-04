# Starting sources for the Updates bots: well-known outlets from around the
# world, read through their public feeds and APIs (not scraped pages).
# Admins can switch any of them off at /admin/bots.
class AddBotSources < ActiveRecord::Migration[8.0]
  SOURCES = [
    # News: world
    [ "news", "world", "BBC News", "https://feeds.bbci.co.uk/news/world/rss.xml" ],
    [ "news", "world", "Al Jazeera", "https://www.aljazeera.com/xml/rss/all.xml" ],
    [ "news", "world", "DW", "https://rss.dw.com/rdf/rss-en-all" ],
    [ "news", "world", "France 24", "https://www.france24.com/en/rss" ],
    [ "news", "world", "NPR", "https://feeds.npr.org/1004/rss.xml" ],
    [ "news", "world", "ABC News (Australia)", "https://www.abc.net.au/news/feed/51120/rss.xml" ],
    # News: politics
    [ "news", "politics", "BBC Politics", "https://feeds.bbci.co.uk/news/politics/rss.xml" ],
    [ "news", "politics", "NPR Politics", "https://feeds.npr.org/1014/rss.xml" ],
    [ "news", "politics", "Politico Europe", "https://www.politico.eu/feed/" ],
    # News: tech & AI
    [ "news", "tech", "BBC Technology", "https://feeds.bbci.co.uk/news/technology/rss.xml" ],
    [ "news", "tech", "The Verge", "https://www.theverge.com/rss/ai-artificial-intelligence/index.xml" ],
    [ "news", "tech", "TechCrunch", "https://techcrunch.com/category/artificial-intelligence/feed/" ],
    [ "news", "tech", "MIT Technology Review", "https://www.technologyreview.com/feed/" ],
    [ "news", "tech", "Wired", "https://www.wired.com/feed/tag/ai/latest/rss" ],
    # News: science & discoveries
    [ "news", "science", "ScienceDaily", "https://www.sciencedaily.com/rss/top/science.xml" ],
    [ "news", "science", "BBC Science", "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml" ],
    [ "news", "science", "NASA", "https://www.nasa.gov/news-release/feed/" ],
    [ "news", "science", "New Scientist", "https://www.newscientist.com/feed/home/" ],
    [ "news", "science", "Phys.org", "https://phys.org/rss-feed/" ],
    # News: health, business, food, faith
    [ "news", "health", "BBC Health", "https://feeds.bbci.co.uk/news/health/rss.xml" ],
    [ "news", "health", "ScienceDaily Health", "https://www.sciencedaily.com/rss/health_medicine.xml" ],
    [ "news", "business", "BBC Business", "https://feeds.bbci.co.uk/news/business/rss.xml" ],
    [ "news", "food", "Eater", "https://www.eater.com/rss/index.xml" ],
    [ "news", "food", "Bon Appétit", "https://www.bonappetit.com/feed/rss" ],
    [ "news", "faith", "Christianity Today", "https://www.christianitytoday.com/feed/" ],
    [ "news", "faith", "The Christian Post", "https://www.christianpost.com/rss" ],
    [ "news", "faith", "Vatican News", "https://www.vaticannews.va/en.rss.xml" ],
    # Sports
    [ "sports", nil, "BBC Sport", "https://feeds.bbci.co.uk/sport/rss.xml" ],
    [ "sports", nil, "ESPN", "https://www.espn.com/espn/rss/news" ],
    [ "sports", nil, "Sky Sports", "https://www.skysports.com/rss/12040" ],
    [ "sports", nil, "CBS Sports", "https://www.cbssports.com/rss/headlines/" ],
    # Jobs (remote, open worldwide)
    [ "jobs", nil, "We Work Remotely", "https://weworkremotely.com/remote-jobs.rss" ],
    [ "jobs", nil, "Remotive", "https://remotive.com/api/remote-jobs?limit=40", "remotive" ],
    [ "jobs", nil, "Himalayas", "https://himalayas.app/jobs/api?limit=40", "himalayas" ],
    # Free courses & scholarships
    [ "courses", nil, "Class Central", "https://www.classcentral.com/report/feed/" ],
    [ "courses", nil, "freeCodeCamp", "https://www.freecodecamp.org/news/rss/" ],
    [ "courses", nil, "Opportunity Desk", "https://opportunitydesk.org/feed/" ],
    [ "courses", nil, "Scholars4Dev", "https://www.scholars4dev.com/feed/" ]
  ].freeze

  def up
    now = Time.current
    rows = SOURCES.map do |bot, topic, name, url, format|
      { bot: bot, topic: topic, name: name, url: url, format: format || "rss", active: true, created_at: now, updated_at: now }
    end
    Class.new(ActiveRecord::Base) { self.table_name = "bot_sources" }.insert_all(rows, unique_by: :url)
  end

  def down
    execute "DELETE FROM bot_items"
    execute "DELETE FROM bot_sources"
  end
end
