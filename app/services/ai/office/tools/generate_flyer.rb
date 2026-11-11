# frozen_string_literal: true

module Ai
  module Office
    module Tools
      class GenerateFlyer < Base
        BRAND = <<~BRAND.squish
          Style: Brethreign brand. Deep green #0E8A5F and mint #34D399 on a near-black #0b1110 or soft light background,
          elegant serif headings, generous space, calm and warm, modern and premium, not clip-art. A small "~" breath mark
          may sit near a corner as the logo. Faith-natural imagery (light, gardens, open hands, people together); no
          crosses unless asked, no stock-photo clichés, no watermarks.
        BRAND

        def self.definition
          {
            name: "generate_flyer",
            description: "Generate a flyer or social image in the Brethreign style. The founder sees it with Download and Use in a breath buttons. Takes up to a minute.",
            parameters: {
              type: "object",
              properties: {
                brief: { type: "string", description: "What the image shows: subject, mood, composition. Be concrete." },
                size: { type: "string", enum: %w[square story landscape], description: "square (1:1 feed post), story (2:3 portrait) or landscape (3:2)." },
                text_on_image: { type: "string", description: "Exact words to print on the image, short (a headline and maybe one line). Leave empty for no text." }
              },
              required: [ "brief" ]
            }
          }
        end

        def call
          brief = input["brief"].to_s.strip
          return Outcome.error("The flyer needs a brief.") if brief.blank?

          size = ImageGenerator::SIZES.key?(input["size"].to_s) ? input["size"].to_s : "square"
          words = input["text_on_image"].to_s.strip
          image = ImageGenerator.new.generate(prompt: prompt(brief, words), size: size)
          blob = ActiveStorage::Blob.create_and_upload!(
            io: StringIO.new(image.bytes),
            filename: "brethreign-flyer-#{Time.current.strftime('%Y%m%d-%H%M%S')}.#{image.content_type.split('/').last}",
            content_type: image.content_type
          )

          Outcome.new(
            result: { "status" => "image_ready", "note" => "Shown to the founder with Download and Use in a breath buttons.", "size" => size },
            card: { "kind" => "flyer", "brief" => brief, "size" => size, "text_on_image" => words, "model" => image.model },
            blob: blob
          )
        end

        private

        def prompt(brief, words)
          text_rule = words.present? ? %(Print exactly this text, spelled exactly, in a clean serif: "#{words}". No other words.) : "No text or lettering in the image."
          "#{brief}\n\n#{BRAND}\n#{text_rule}"
        end
      end
    end
  end
end
