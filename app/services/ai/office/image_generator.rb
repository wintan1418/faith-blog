# frozen_string_literal: true

require "base64"
require "zlib"

module Ai
  module Office
    # Makes flyer images: OpenAI Images when OPENAI_API_KEY is set, else Gemini
    # image output when GEMINI_API_KEY is set, else (and in tests) a plain
    # brand-coloured placeholder so the flow still works end to end.
    # OFFICE_IMAGE_MODEL overrides the model.
    class ImageGenerator
      Image = Data.define(:bytes, :content_type, :model)

      SIZES = {
        "square" => "1024x1024",
        "story" => "1024x1536",
        "landscape" => "1536x1024"
      }.freeze

      OPENAI_ENDPOINT = URI("https://api.openai.com/v1/images/generations")
      OPENAI_MODELS = %w[gpt-image-2 gpt-image-1.5 gpt-image-1].freeze
      GEMINI_MODEL = "gemini-2.5-flash-image"
      GEMINI_TEMPLATE = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent"
      TIMEOUT = 240

      def self.provider
        return "stub" if ENV["OFFICE_STUB"] == "1" || ENV["AI_MODERATION_STUB"] == "1"
        return "openai" if ENV["OPENAI_API_KEY"].present?
        return "gemini" if ENV["GEMINI_API_KEY"].present?

        "stub"
      end

      def generate(prompt:, size:)
        size = SIZES.key?(size.to_s) ? size.to_s : "square"
        case self.class.provider
        when "openai" then openai(prompt, size)
        when "gemini" then gemini(prompt, size)
        else stub(size)
        end
      end

      private

      def openai(prompt, size)
        models = ENV["OFFICE_IMAGE_MODEL"].present? ? [ ENV["OFFICE_IMAGE_MODEL"] ] : OPENAI_MODELS.dup
        begin
          model = models.first
          json = post(OPENAI_ENDPOINT, { "authorization" => "Bearer #{ENV['OPENAI_API_KEY']}" },
                      { model: model, prompt: prompt, size: SIZES[size], quality: "high", n: 1 })
        rescue Client::ApiError => e
          raise unless models.size > 1 && e.status.in?([ 400, 403, 404 ]) && e.message.match?(/model/i)

          models.shift
          retry
        end

        b64 = json.dig("data", 0, "b64_json")
        raise Client::ApiError, "OpenAI returned no image" if b64.blank?

        Image.new(bytes: Base64.decode64(b64), content_type: "image/png", model: model)
      end

      def gemini(prompt, size)
        model = ENV["OFFICE_IMAGE_MODEL"].presence || GEMINI_MODEL
        aspect = { "square" => "1:1", "story" => "2:3", "landscape" => "3:2" }.fetch(size)
        json = post(URI(format(GEMINI_TEMPLATE, model)), { "x-goog-api-key" => ENV["GEMINI_API_KEY"] },
                    { contents: [ { role: "user", parts: [ { text: prompt } ] } ],
                      generationConfig: { responseModalities: [ "IMAGE" ], imageConfig: { aspectRatio: aspect } } })
        part = Array(json.dig("candidates", 0, "content", "parts")).find { |p| p["inlineData"] }
        raise Client::ApiError, "Gemini returned no image" unless part

        Image.new(bytes: Base64.decode64(part.dig("inlineData", "data")), content_type: part.dig("inlineData", "mimeType") || "image/png", model: model)
      end

      def post(uri, headers, body)
        request = Net::HTTP::Post.new(uri)
        headers.each { |k, v| request[k] = v }
        request["content-type"] = "application/json"
        request.body = JSON.dump(body)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 15
        http.read_timeout = TIMEOUT
        response = http.request(request)
        unless response.is_a?(Net::HTTPSuccess)
          raise Client::ApiError.new("Image API #{response.code}: #{response.body.to_s.truncate(400)}", status: response.code.to_i)
        end

        JSON.parse(response.body)
      rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError, IOError => e
        raise Client::ApiError, "Image API unreachable: #{e.class}"
      rescue JSON::ParserError
        raise Client::ApiError, "Image API sent a non-JSON reply"
      end

      # A real PNG in brand green fading to near-black, so stub flyers can be
      # downloaded and attached to breaths like generated ones.
      def stub(size)
        width, height = SIZES[size].split("x").map { |n| n.to_i / 4 }
        top = [ 0x0E, 0x8A, 0x5F ]
        bottom = [ 0x0B, 0x11, 0x10 ]
        rows = (0...height).map do |y|
          t = y.to_f / (height - 1)
          pixel = top.zip(bottom).map { |a, b| (a + (b - a) * t).round }.pack("C3")
          "\x00".b + (pixel * width)
        end
        png = "\x89PNG\r\n\x1A\n".b +
              chunk("IHDR", [ width, height, 8, 2, 0, 0, 0 ].pack("N2C5")) +
              chunk("IDAT", Zlib::Deflate.deflate(rows.join)) +
              chunk("IEND", "")
        Image.new(bytes: png, content_type: "image/png", model: "stub")
      end

      def chunk(type, data)
        [ data.bytesize ].pack("N") + type.b + data.b + [ Zlib.crc32(type + data) ].pack("N")
      end
    end
  end
end
