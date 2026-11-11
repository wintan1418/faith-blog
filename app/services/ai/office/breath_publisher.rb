# frozen_string_literal: true

module Ai
  module Office
    # Turns an Office breath card into a real Post, the same way the composer
    # does (PostsController#create): live straight away (or scheduled), with
    # the usual AI moderation running behind it from the model's callbacks.
    class BreathPublisher
      TZ = "Africa/Lagos"

      Result = Data.define(:post, :errors) do
        def ok? = errors.empty?
      end

      # The account Office breaths go out from: OFFICE_POST_AS (a staff
      # username, e.g. an official Brethreign account) or the admin themselves.
      def self.author_for(admin)
        name = ENV["OFFICE_POST_AS"].to_s.strip.delete_prefix("@")
        official = User.find_by(username: name) if name.present?
        official && (official.admin? || official.super_admin?) ? official : admin
      end

      # "2026-11-12T09:00" (or any parseable time) read as Lagos time. nil when blank or invalid.
      def self.parse_time(value)
        return nil if value.blank?

        Time.find_zone(TZ).parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def initialize(card:, admin:, schedule_at: nil)
        @card = card.stringify_keys
        @admin = admin
        @schedule_at = schedule_at
      end

      def call
        post = Post.new(
          user: self.class.author_for(@admin),
          title: @card["title"].to_s.strip.presence,
          content: html_body,
          room_id: room&.id,
          kind: :breath,
          prayer_status: ActiveModel::Type::Boolean.new.cast(@card["prayer"]) ? :prayer_pending : :not_a_prayer,
          moderation_status: :approved
        )

        if @schedule_at.present? && @schedule_at > Time.current
          post.status = :scheduled
          post.scheduled_for = @schedule_at
          post.published_at = nil
        else
          post.status = :published
        end

        blob = image_blob
        post.images.attach(blob.signed_id) if blob

        post.save ? Result.new(post: post, errors: []) : Result.new(post: post, errors: post.errors.full_messages)
      end

      private

      def room
        @room ||= Room.public_rooms.find_by(id: @card["room_id"]) if @card["room_id"].present?
      end

      def image_blob
        id = @card["image_message_id"]
        OfficeMessage.find_by(id: id)&.image&.blob if id.present?
      end

      # Plain text from the card → simple paragraphs for Action Text.
      def html_body
        @card["body"].to_s.strip.split(/\n{2,}/).map do |para|
          "<p>#{ERB::Util.h(para.strip).gsub("\n", '<br>')}</p>"
        end.join
      end
    end
  end
end
