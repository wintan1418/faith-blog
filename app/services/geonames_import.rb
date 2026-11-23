# frozen_string_literal: true

require "net/http"
require "csv"

# Loads GeoNames cities (https://www.geonames.org, CC BY 4.0) into `cities`.
# Downloads cities5000 (every place with 5,000+ people), the region names and
# the country names, then upserts by GeoNames id, so running it again only
# refreshes what's there. Used by `bin/rails cities:import`.
class GeonamesImport
  BASE = "https://download.geonames.org/export/dump/"
  DATASETS = %w[cities500 cities1000 cities5000 cities15000].freeze
  BATCH = 2_000
  SAMPLE = Rails.root.join("db/cities_sample.csv")

  def initialize(dataset: "cities5000", dir: Rails.root.join("tmp/geonames"), log: $stdout)
    raise ArgumentError, "dataset must be one of #{DATASETS.join(', ')}" unless DATASETS.include?(dataset)

    @dataset = dataset
    @dir = Pathname(dir)
    @log = log
  end

  def call
    FileUtils.mkdir_p(@dir)
    countries = parse_countries(fetch("countryInfo.txt"))
    regions = parse_regions(fetch("admin1CodesASCII.txt"))
    zip = fetch("#{@dataset}.zip")

    count = 0
    rows = []
    each_city_line(zip) do |fields|
      row = self.class.row_from(fields, regions, countries)
      next unless row

      rows << row
      next if rows.size < BATCH

      count += upsert(rows)
      rows = []
    end
    count += upsert(rows)
    @log.puts "Cities: #{count} loaded from #{@dataset} (#{City.count} in the table)."
    count
  end

  # A cities file line (tab separated, see GeoNames readme) as attributes for City.
  def self.row_from(fields, regions, countries)
    id, name, ascii, alternates, lat, lng, feature_class, _code, country, _cc2, admin1 = fields
    return if feature_class != "P" || name.blank? || country.blank?

    ascii = ascii.presence || name
    {
      geonames_id: id.to_i, name: name.first(200), ascii_name: ascii.first(200),
      admin1_code: admin1.presence, admin1_name: regions["#{country}.#{admin1}"],
      country_code: country, country_name: countries[country] || country,
      lat: lat.to_f, lng: lng.to_f, population: fields[14].to_i,
      search_key: City.normalize(ascii),
      search_tokens: City.tokens_for(ascii, name, City.useful_alternates(alternates))
    }
  end

  # The small built-in list for development and tests (no download needed).
  def self.load_sample!
    rows = sample_rows
    City.upsert_all(rows, unique_by: :geonames_id, update_only: rows.first.keys - %i[geonames_id]) if rows.any?
    rows.size
  end

  def self.sample_rows
    CSV.foreach(SAMPLE, headers: true).map do |r|
      {
        geonames_id: r["geonames_id"].to_i, name: r["name"], ascii_name: r["ascii_name"],
        admin1_code: r["admin1_code"], admin1_name: r["admin1_name"],
        country_code: r["country_code"], country_name: r["country_name"],
        lat: r["lat"].to_f, lng: r["lng"].to_f, population: r["population"].to_i,
        search_key: City.normalize(r["ascii_name"]),
        search_tokens: City.tokens_for(r["ascii_name"], r["name"], r["alternates"].to_s.split("|"))
      }
    end
  end

  private

  def upsert(rows)
    return 0 if rows.empty?

    City.upsert_all(rows, unique_by: :geonames_id, update_only: rows.first.keys - %i[geonames_id])
    rows.size
  end

  def fetch(file)
    path = @dir.join(file)
    if path.exist? && path.mtime > 1.day.ago
      @log.puts "Using #{path} (downloaded today)."
      return path
    end

    @log.puts "Downloading #{BASE}#{file}..."
    download(URI("#{BASE}#{file}"), path)
    path
  end

  def download(uri, path, redirects = 3)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 15, read_timeout: 120) do |http|
      http.request(Net::HTTP::Get.new(uri)) do |response|
        if response.is_a?(Net::HTTPRedirection) && redirects.positive?
          return download(URI(response["location"]), path, redirects - 1)
        end
        raise "GeoNames download failed: #{uri} (#{response.code})" unless response.is_a?(Net::HTTPSuccess)

        File.open("#{path}.part", "wb") { |f| response.read_body { |chunk| f.write(chunk) } }
      end
    end
    File.rename("#{path}.part", path)
  end

  def each_city_line(zip_path)
    Zip::File.open(zip_path.to_s) do |zip|
      entry = zip.find_entry("#{@dataset}.txt") or raise "#{@dataset}.txt missing from #{zip_path}"
      entry.get_input_stream.each_line do |line|
        yield line.force_encoding(Encoding::UTF_8).chomp.split("\t", -1)
      end
    end
  end

  # countryInfo.txt: ISO code in column 1, name in column 5; "#" lines are comments.
  def parse_countries(path)
    File.foreach(path, encoding: "UTF-8").each_with_object({}) do |line, map|
      next if line.start_with?("#")

      cols = line.chomp.split("\t")
      map[cols[0]] = cols[4] if cols[0].present? && cols[4].present?
    end
  end

  # admin1CodesASCII.txt: "NG.48<TAB>Ondo State<TAB>Ondo State<TAB>2326168".
  def parse_regions(path)
    File.foreach(path, encoding: "UTF-8").each_with_object({}) do |line, map|
      code, name, ascii = line.chomp.split("\t")
      map[code] = ascii.presence || name if code.present?
    end
  end
end
