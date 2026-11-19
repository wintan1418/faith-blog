# frozen_string_literal: true

require "test_helper"

# Only the super admin may see who is behind an anonymous breath.
class AnonymousSuperAdminOnlyTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    seen = { tour_completed_at: Time.current, welcomed_at: Time.current }
    @author = create_member("hidden_writer", **seen)
    @admin = create_member("plain_admin", **seen).tap { |u| u.update_columns(role: User.roles[:admin]) }
    @moderator = create_member("plain_mod", **seen).tap { |u| u.update_columns(role: User.roles[:moderator]) }
    @super = create_member("the_founder", **seen).tap { |u| u.update_columns(role: User.roles[:super_admin]) }
    room = Room.create!(name: "Prayer Wall", description: "x", room_type: :general, is_public: true)
    @post = Post.create!(user: @author, room: room, title: "Please pray", content: "A hard season",
                         status: :published, moderation_status: :approved, anonymous: true)
    Comment.create!(post: @post, user: @author, content: "Thank you for praying", moderation_status: :approved)
    @review = AiModerationReview.create!(reviewable: @post, user: @author, severity: "low", recommended_action: "allow")
  end

  test "admins and moderators never see the anonymous author" do
    [ @admin, @moderator ].each do |staff|
      sign_in staff
      [ admin_posts_path, admin_moderation_reviews_path, admin_moderation_review_path(@review), post_path(@post) ].each do |path|
        get path
        assert_no_match "hidden_writer", response.body, "#{staff.role} saw the author on #{path}"
      end
      sign_out staff
    end
  end

  test "the super admin can see who wrote it" do
    sign_in @super
    get admin_posts_path
    assert_match "hidden_writer", response.body
    get admin_moderation_review_path(@review)
    assert_match "hidden_writer", response.body
  end
end
