# frozen_string_literal: true

namespace :office do
  desc "Load the Office briefing from a file: bin/rails office:import_briefing FILE=path [FORCE=1 to replace a non-empty briefing]"
  task import_briefing: :environment do
    path = ENV["FILE"].to_s
    abort "Set FILE=path/to/briefing.md" if path.blank? || !File.exist?(path)

    briefing = OfficeBriefing.first || OfficeBriefing.new
    if briefing.persisted? && briefing.body.present? && briefing.body != OfficeBriefing.default_body && ENV["FORCE"] != "1"
      abort "The briefing has been edited already. Run again with FORCE=1 to replace it."
    end

    briefing.update!(body: File.read(path))
    puts "Briefing loaded (#{briefing.body.length} characters)."
  end
end
