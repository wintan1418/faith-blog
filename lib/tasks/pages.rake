# frozen_string_literal: true

namespace :pages do
  # The official Brethreign page (@brethreign), owned by the founder and
  # verified. Safe to run again: it creates or updates the page in place.
  #
  #   bin/rails pages:official                      # dry run: shows what it would do
  #   APPLY=1 bin/rails pages:official              # do it
  #   APPLY=1 COVER=/path/cover.jpg bin/rails pages:official
  #   APPLY=1 LOGO=/path/logo.png POSTS=1 bin/rails pages:official
  #
  # OWNER=<username> (default wintan). LOGO defaults to public/icon.png (the
  # logomark on its evergreen tile). COVER is best at 1500 x 500 (3:1).
  # POSTS=1 adds the welcome post and the App Store post once each.
  desc "Create or update the official @brethreign page (dry run unless APPLY=1)"
  task official: :environment do
    OfficialPage.new(
      apply: ENV["APPLY"] == "1",
      owner: ENV.fetch("OWNER", "wintan"),
      logo: ENV["LOGO"].presence || Rails.root.join("public/icon.png").to_s,
      cover: ENV["COVER"].presence,
      posts: ENV["POSTS"] == "1"
    ).call
  end
end
