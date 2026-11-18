# frozen_string_literal: true

# Opens the pages members use most, signed in as a hidden monitor account,
# exactly as a browser would (the whole app in-process: routing, sign-in,
# views). Any page that errors, or doesn't load, raises an ErrorAlert.
# Runs every 10 minutes and shortly after each deploy (SiteHealthCheckJob).
class SiteHealthCheck
  EMAIL = "site-monitor@brethreign.invalid".freeze
  USERNAME = "site_monitor".freeze

  Failure = Data.define(:name, :path, :problem)

  def self.call = new.call

  def call
    user = self.class.monitor_user
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.host!(ENV["RAILS_HOST"].presence || "brethreign.com")
    session.https!
    return [ Failure.new("sign in", "/users/sign_in", "the monitor couldn't sign in") ] unless sign_in(session, user)

    failures = pages(user).filter_map do |name, path|
      status = session.get(path)
      problem = if status >= 500 then "returned #{status}"
      elsif status.between?(300, 399) && session.response.location.to_s.include?("/users/sign_in") then "signed the reader out"
      end
      Failure.new(name, path, problem) if problem
    rescue StandardError => e
      Failure.new(name, path, "#{e.class}: #{e.message.to_s.truncate(200)}")
    end

    report(failures)
    failures
  end

  # Fixed pages, plus a few real ones: the newest breath, room and author,
  # so content that breaks a page is caught too.
  def pages(user)
    list = {
      "Feed" => "/feed", "Following" => "/feed/following", "Trending" => "/feed/trending", "Updates" => "/feed/updates",
      "Inbox" => "/inbox", "New message" => "/conversations/new", "Notifications" => "/notifications",
      "Games" => "/games", "Rooms" => "/rooms", "Prayer circles" => "/circles", "New breath" => "/posts/new",
      "Own profile" => "/u/#{user.username}", "Settings" => "/settings/accounts/edit"
    }
    if (post = Post.published.where(moderation_status: :approved).order(published_at: :desc).first)
      list["Newest breath"] = "/posts/#{post.to_param}"
      list["Its author"] = "/u/#{post.user.username}" if post.user
    end
    if (room = Room.public_rooms.order(updated_at: :desc).first)
      list["Busiest room"] = "/rooms/#{room.to_param}"
    end
    list
  rescue StandardError
    list
  end

  def self.monitor_user
    user = User.find_by(email: EMAIL)
    return user if user
    password = SecureRandom.base58(32)
    User.create!(email: EMAIL, username: USERNAME, password: password, password_confirmation: password,
                 tour_completed_at: Time.current, welcomed_at: Time.current,
                 onboarding_dismissed_at: Time.current, background_rain: false)
  end

  private

  # Signs in through the real sign-in form, with a fresh password each run.
  def sign_in(session, user)
    password = SecureRandom.base58(32)
    user.update_columns(encrypted_password: Devise::Encryptor.digest(User, password))
    session.get("/users/sign_in")
    token = session.response.body[/name="authenticity_token" value="([^"]+)"/, 1]
    session.post("/users/sign_in", params: { authenticity_token: token, user: { email: user.email, password: password } })
    session.get("/feed") == 200
  rescue StandardError => e
    Rails.logger.warn("[SiteHealthCheck] sign-in failed: #{e.class}: #{e.message}")
    false
  end

  def report(failures)
    return if failures.empty?
    lines = failures.map { |f| "• #{f.name} (#{f.path}): #{f.problem}" }
    ErrorAlert.notify(
      key: "health|#{failures.map(&:path).sort.join(',')}",
      title: failures.one? ? "Health check: #{failures.first.name} is broken" : "Health check: #{failures.size} pages are broken",
      detail: "The automatic check couldn't open these pages:\n#{lines.join("\n")}\nChecked at #{Time.current.utc.iso8601}"
    )
  end
end
