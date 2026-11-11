# frozen_string_literal: true

module Ai
  module Office
    module Tools
      # Recent breaths, reports or new members, summarised for context. Read-only.
      class RecentActivity < Base
        KINDS = %w[posts reports users].freeze

        def self.definition
          {
            name: "recent_activity",
            description: "Read the most recent breaths (posts), reports or new members (users), newest first.",
            parameters: {
              type: "object",
              properties: {
                kind: { type: "string", enum: KINDS },
                limit: { type: "integer", description: "How many, 1 to 20. Default 10." }
              },
              required: [ "kind" ]
            }
          }
        end

        def call
          kind = input["kind"].to_s.presence_in(KINDS) || "posts"
          limit = (input["limit"].presence || 10).to_i.clamp(1, 20)
          Outcome.new(result: { "kind" => kind, "items" => send(kind, limit) })
        end

        private

        def posts(limit)
          Post.includes(:user, :room, :rich_text_content).order(created_at: :desc).limit(limit).map do |post|
            {
              "id" => post.id, "author" => post.anonymous? ? "Anonymous" : post.user&.username,
              "title" => post.title, "text" => post.content.to_plain_text.squish.truncate(240),
              "room" => post.room&.name, "status" => post.status, "moderation" => post.moderation_status,
              "prayer" => post.prayer?, "likes" => post.likes_count, "comments" => post.comments_count,
              "created_at" => post.created_at.in_time_zone("Africa/Lagos").iso8601, "path" => routes.post_path(post)
            }
          end
        end

        def reports(limit)
          Report.includes(:reporter).order(created_at: :desc).limit(limit).map do |report|
            {
              "id" => report.id, "status" => report.status, "about" => "#{report.reportable_type} ##{report.reportable_id}",
              "reason" => report.reason.to_s.truncate(240), "reporter" => report.reporter&.username,
              "created_at" => report.created_at.in_time_zone("Africa/Lagos").iso8601
            }
          end
        end

        def users(limit)
          User.includes(:profile).order(created_at: :desc).limit(limit).map do |member|
            {
              "username" => member.username, "name" => member.display_name, "active" => member.active,
              "joined_at" => member.created_at.in_time_zone("Africa/Lagos").iso8601,
              "last_seen_at" => member.last_seen_at&.in_time_zone("Africa/Lagos")&.iso8601
            }
          end
        end
      end
    end
  end
end
