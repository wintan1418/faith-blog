# frozen_string_literal: true

# Development only: one sample page so /pages and /p/<handle> have something in
# them locally. Never runs in production.
return unless Rails.env.development?

owner = User.where(role: %i[admin super_admin]).order(:id).first || User.order(:id).first
return puts("  (no members yet: skipping the sample page)") unless owner

page = Page.by_handle("gracechapelakure").first || Page.new(handle: "gracechapelakure")
page.assign_attributes(
  name: "Grace Chapel Akure", category: "church", created_by: owner,
  tagline: "A warm, Bible-loving family church in the heart of Akure.",
  about: "We gather every Sunday to worship, pray and open the Scriptures together.\n\nEveryone is welcome: come as you are.",
  website: "https://example.org", city: City.find_by(name: "Akure"), founded_year: 1998, size_range: "201-500",
  tradition: "Non-denominational", service_times: "Sundays 8:00 am and 10:30 am\nWednesdays 6:00 pm Bible study"
)
page.staff_override = true
page.save!
page.memberships.find_or_create_by!(user: owner) { |m| m.assign_attributes(role: :owner, status: :active, accepted_at: Time.current) }
unless page.posts.exists?
  Post.create!(user: owner, page: page, title: "Welcome to Grace Chapel on Brethreign",
               content: "We're glad you found us. Follow the page for service updates and encouragement through the week.",
               status: :published, moderation_status: :approved)
end
puts "  Sample page: /p/#{page.handle}"
