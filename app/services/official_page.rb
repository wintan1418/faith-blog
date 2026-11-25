# frozen_string_literal: true

# The official Brethreign page: @brethreign, owned by the founder, verified.
# Run through `bin/rails pages:official` (see lib/tasks/pages.rake).
# Idempotent: every run brings the page to the same state, and the two
# optional first posts are only ever written once.
class OfficialPage
  HANDLE = "brethreign"
  ATTRIBUTES = {
    name: "Brethreign",
    category: "community",
    tagline: "Work, life and faith, talked about kindly.",
    about: "Brethreign is a social space and professional network where conversations about work, life and faith " \
           "stay sane and kind. Share a breath, join Rooms, grow your professional profile, read and pray through the " \
           "Bible every day, and find people of faith near you — with no outrage algorithm, moderation from day one " \
           "and real protections for young people. Open to everyone: employed or not, churchgoer or not. " \
           "Built in Nigeria for the world.",
    website: "https://brethreign.com",
    founded_year: 2026
  }.freeze
  POSTS = [
    { key: "welcome", title: "Welcome to the official Brethreign page",
      body: "Hello, and welcome! This is where we'll share what's new on Brethreign, the stories we love from the " \
            "community, and the occasional word of encouragement. Follow along, and thank you for helping keep this " \
            "a kind place to talk about work, life and faith." },
    { key: "app_store", title: "Brethreign is now on the App Store",
      body: "Brethreign is now on the App Store for iPhone, alongside Android on Google Play. Search “Brethreign”, " \
            "download it, and take your breaths, rooms, Bible reading and prayers with you wherever you go." }
  ].freeze

  def initialize(apply:, owner:, logo: nil, cover: nil, posts: false, out: $stdout)
    @apply = apply
    @owner_name = owner
    @logo = logo
    @cover = cover
    @posts = posts
    @out = out
  end

  def call
    owner = User.find_by("lower(username) = ?", @owner_name.to_s.downcase)
    return say("No member called @#{@owner_name}. Nothing done.") unless owner

    page = Page.by_handle(HANDLE).first
    say("#{page ? 'Updating' : 'Creating'} @#{HANDLE} (owner @#{owner.username})#{' [dry run: APPLY=1 to do it]' unless @apply}")
    return dry_run(page, owner) unless @apply

    page ||= Page.new(handle: HANDLE, created_by: owner)
    page.assign_attributes(ATTRIBUTES)
    page.city_id = owner.profile&.city_id
    page.location = owner.profile&.city ? nil : "Nigeria"
    page.status = :active
    page.verified_at ||= Time.current
    page.verified_by ||= owner
    page.verification_status = :approved
    page.staff_override = true
    attach(page, :logo, @logo)
    attach(page, :cover, @cover)
    page.save!

    Page.transaction do
      page.memberships.where(role: :owner).where.not(user_id: owner.id).update_all(role: PageMembership.roles[:admin])
      membership = page.memberships.find_or_initialize_by(user: owner)
      membership.update!(role: :owner, status: :active, accepted_at: membership.accepted_at || Time.current)
    end
    say("Page saved: /p/#{page.handle} · verified · owner @#{owner.username}#{" · city #{page.city.label}" if page.city}")

    write_posts(page, owner) if @posts
    page
  end

  private

  def say(text) = @out.puts(text)

  def dry_run(page, owner)
    ATTRIBUTES.each { |key, value| say("  #{key}: #{value.to_s.truncate(90)}") }
    say("  city: #{owner.profile&.city&.label || 'none (location: Nigeria)'}")
    say("  logo: #{@logo || 'unchanged'}#{' (missing!)' if @logo && !File.exist?(@logo)}")
    say("  cover: #{@cover || 'unchanged'}#{' (missing!)' if @cover && !File.exist?(@cover)}")
    say("  posts: #{@posts ? POSTS.map { |p| p[:key] }.join(', ') + ' (each once)' : 'none (POSTS=1 to add)'}")
    say("  existing page: #{page ? "id #{page.id}, #{page.followers_count} followers" : 'none'}")
    page
  end

  def attach(page, name, path)
    return if path.blank?
    raise ArgumentError, "#{name.to_s.upcase} file not found: #{path}" unless File.exist?(path)

    digest = Digest::MD5.file(path).base64digest
    current = page.public_send(name)
    return if current.attached? && current.blob.checksum == digest

    page.public_send(name).attach(io: File.open(path), filename: "brethreign-#{name}#{File.extname(path)}",
                                  content_type: Marcel::MimeType.for(Pathname.new(path)))
  end

  def write_posts(page, owner)
    POSTS.each do |spec|
      if page.posts.where(title: spec[:title]).exists?
        say("  post “#{spec[:title]}”: already there")
        next
      end
      post = Post.create!(user: owner, page: page, title: spec[:title], content: spec[:body],
                          status: :published, moderation_status: :approved)
      say("  post “#{spec[:title]}”: written (/posts/#{post.slug})")
    end
  end
end
