# frozen_string_literal: true

require "minitest/mock"

# Search indexing never reaches the network in tests: SearchIndexing::Http.request
# is stubbed and every call is recorded as { method:, url:, body:, headers: }.
module SearchIndexingStubs
  FAKE_KEY = OpenSSL::PKey::RSA.generate(2048)

  def fake_google_credentials(email: "indexer@brethreign-test.iam.gserviceaccount.com")
    { "type" => "service_account", "client_email" => email, "private_key" => FAKE_KEY.to_pem,
      "token_uri" => "https://oauth2.googleapis.com/token" }
  end

  def with_env(values)
    saved = values.keys.to_h { |k| [ k, ENV[k] ] }
    values.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  def with_indexnow(&)
    with_env("INDEXNOW_ENABLED" => "1", "INDEXNOW_KEY" => "testkey1234567890", &)
  end

  def with_google(&)
    SearchConsole::Client.reset_tokens!
    with_env("GOOGLE_SEARCH_CONSOLE_CREDENTIALS" => fake_google_credentials.to_json, &)
  end

  # Records requests and yields the list to the block. `responder` (method,
  # url, body) returns [status, body]; the default answers 200 with no body.
  def stub_http(responder = nil)
    calls = []
    responder ||= ->(*) { [ 200, "" ] }
    fake = lambda do |method, url, body = nil, headers = {}|
      calls << { method: method, url: url, body: body, headers: headers }
      status, response_body = responder.call(method, url, body)
      SearchIndexing::Http::Response.new(status: status, body: response_body.is_a?(String) ? response_body : response_body.to_json)
    end
    SearchIndexing::Http.stub(:request, fake) { yield calls }
  end

  def stub_http_answering(status, body, &)
    SearchIndexing::Http.stub(:request, ->(*) { SearchIndexing::Http::Response.new(status: status, body: body) }, &)
  end

  GOOGLE_TOKEN = { access_token: "ya29.test-token", expires_in: 3600, token_type: "Bearer" }.freeze

  # Like stub_http, but Google's token endpoint answers a token.
  def stub_google(responder = nil, &)
    responder ||= ->(*) { [ 200, {} ] }
    google = lambda do |method, url, body|
      url.start_with?("https://oauth2.googleapis.com/token") ? [ 200, GOOGLE_TOKEN ] : responder.call(method, url, body)
    end
    stub_http(google, &)
  end
end
