# frozen_string_literal: true

# www.brethreign.com -> brethreign.com, for every page. One address keeps
# Google sign-in working (its return address is registered for brethreign.com
# only) and gives search engines a single site to index.
class CanonicalHost
  HOSTS = { "www.brethreign.com" => "brethreign.com" }.freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)
    target = HOSTS[request.host.to_s.downcase]
    return @app.call(env) unless target

    scheme = Rails.env.production? ? "https" : request.scheme
    port = Rails.env.production? || [ 80, 443 ].include?(request.port) ? "" : ":#{request.port}"
    location = "#{scheme}://#{target}#{port}#{request.fullpath}"
    status = request.get? || request.head? ? 301 : 308 # 308 keeps the method for form posts
    [ status, { "location" => location, "content-type" => "text/html" }, [] ]
  end
end

Rails.application.config.middleware.insert_before 0, CanonicalHost
