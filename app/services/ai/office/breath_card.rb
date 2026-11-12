# frozen_string_literal: true

module Ai
  module Office
    # Changes to an existing breath card (an OfficeMessage whose card kind is
    # "breath"), from the card's buttons or the update_breath tool.
    #
    # A draft only changes the card. A posted or scheduled breath also changes
    # the real Post: its text, room and the one image the Office attached
    # (the post's other images are kept). The founder asked for the change,
    # so it goes straight to the post; moderation is left as it stands, the
    # same as when they edit their own post.
    #
    # The card's image is always another message's attachment, named by
    # card["image_message_id"]: a flyer card, or the breath card itself when
    # an image was uploaded to it.
    class BreathCard
      LIVE = %w[posted scheduled].freeze

      Result = Data.define(:errors) do
        def ok? = errors.empty?
      end

      def self.breath?(message) = message&.card_kind == "breath"

      # A message in the conversation whose image can go on a breath.
      def self.image_source(conversation, id)
        return nil if id.blank?

        message = conversation.messages.find_by(id: id.to_i)
        message if message&.image&.attached?
      end

      def initialize(message, admin:)
        @message = message
        @admin = admin
      end

      def card = @message.card_data
      def status = card["status"].presence || "draft"
      def live? = LIVE.include?(status)
      def draft? = status == "draft"

      def image_message
        self.class.image_source(@message.conversation, card["image_message_id"])
      end

      def post
        @post ||= Post.find_by(id: card["post_id"]) if card["post_id"].present?
      end

      # changes: any of "title", "body", "room_id", "prayer", "image_message_id"
      # (nil removes the image). Only the keys given are touched.
      def update(changes)
        changes = changes.stringify_keys
        changes["image_message_id"] = changes["image_message_id"].presence&.to_i if changes.key?("image_message_id")
        if changes.key?("image_message_id") && changes["image_message_id"].present? &&
           !self.class.image_source(@message.conversation, changes["image_message_id"])
          return fail!("That image isn't in this conversation.")
        end

        changes = changes.merge("room_name" => Room.find_by(id: changes["room_id"])&.name) if changes.key?("room_id")
        return update_post(changes) if live?
        return fail!("This breath can't be changed any more.") unless draft?

        @message.update_card!(changes.merge("error" => nil))
        Result.new(errors: [])
      end

      private

      def update_post(changes)
        return fail!("The posted breath has been deleted, so it can't be changed.") unless post

        Post.transaction do
          post.title = changes["title"].to_s.strip.presence if changes.key?("title")
          post.content = BreathPublisher.html_body(changes["body"]) if changes.key?("body") && changes["body"].present?
          post.room_id = changes["room_id"] if changes.key?("room_id")
          if changes.key?("image_message_id")
            new_blob = self.class.image_source(@message.conversation, changes["image_message_id"])&.image&.blob
            replace_office_image(new_blob)
            changes["post_image_blob_id"] = new_blob&.id
          end
          raise ActiveRecord::Rollback unless post.save
        end
        return fail!("Couldn't update the posted breath: #{post.errors.full_messages.to_sentence}") if post.errors.any?

        @message.update_card!(changes.merge("post_slug" => post.slug, "updated_at" => Time.current.iso8601, "error" => nil))
        Result.new(errors: [])
      end

      # Swaps the image the Office put on the post (if any) for new_blob,
      # keeping every other image. Same approach as PostsController#update:
      # assign the full list so the post's own validations (type, size, at
      # most 5) still run.
      def replace_office_image(new_blob)
        old_blob_id = card["post_image_blob_id"] || image_message&.image&.blob&.id
        kept = post.images.attachments.reject { |a| a.blob_id == old_blob_id || a.blob_id == new_blob&.id }
        post.images = kept.map { |a| a.blob.signed_id } + [ new_blob&.signed_id ].compact
      end

      def fail!(error)
        @message.update_card!("error" => error)
        Result.new(errors: [ error ])
      end
    end
  end
end
