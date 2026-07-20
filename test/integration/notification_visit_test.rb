# frozen_string_literal: true

require "test_helper"

# Notification links (email + in-app) route through /notifications/:id/visit
# so the destination is computed at click time. Old links to deleted or
# re-slugged breaths must land somewhere sensible, never on a bare 404.
class NotificationVisitTest < ActionDispatch::IntegrationTest
  setup do
    @author = User.create!(username: "notif_author", email: "notif_author@example.com",
                           password: "password123", password_confirmation: "password123")
    @commenter = User.create!(username: "notif_actor", email: "notif_actor@example.com",
                              password: "password123", password_confirmation: "password123")
    @room = Room.create!(name: "Notif Room", description: "x")
    @post = Post.create!(user: @author, room: @room, title: "A breath", content: "Body",
                         status: :published, moderation_status: :approved)
    @comment = @post.comments.create!(user: @commenter, content: "Amen!")
    @notification = Notification.create!(user: @author, actor: @commenter,
                                         notifiable: @comment, notification_type: :new_comment)
  end

  test "visit marks the notification read and redirects to the live target" do
    sign_in @author
    get visit_notification_path(@notification)

    assert_redirected_to post_path(@post)
    assert @notification.reload.read?
  end

  test "visit for a notification whose target was deleted lands on notifications, not a 404" do
    @post.destroy # destroys comment + its notifications via dependent: :destroy
    sign_in @author

    get visit_notification_path(@notification.id)
    assert_redirected_to notifications_path
    follow_redirect!
    assert_response :success
  end

  test "visit requires sign-in so email clicks round-trip through login" do
    get visit_notification_path(@notification)
    assert_redirected_to new_user_session_path
  end

  test "notification email links through the visit redirector" do
    email = NotificationMailer.with(notification: @notification).community_notification
    assert_match %r{/notifications/#{@notification.id}/visit}, email.body.encoded
  end

  test "a dead post link gives a signed-in reader a soft landing on the feed" do
    dead_path = post_path(@post)
    @post.destroy
    sign_in @author

    get dead_path
    assert_redirected_to feed_path
    follow_redirect!
    assert_match(/isn.t here anymore/, flash[:alert])
  end
end
