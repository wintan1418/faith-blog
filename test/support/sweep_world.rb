# frozen_string_literal: true

# A small but complete world for the crash sweeps: one of every record a page
# can be about (posts of each kind, a room, a circle, a chat with files, a
# resource, admin records, notifications of many kinds), owned by a normal
# member, with a second member and a super admin around them.
module SweepWorld
  PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")

  def png_upload(name = "pixel.png")
    Rack::Test::UploadedFile.new(StringIO.new(PNG), "image/png", true, original_filename: name)
  end

  def png_blob(name = "pixel.png")
    { io: StringIO.new(PNG), filename: name, content_type: "image/png" }
  end

  def settled(username, **attrs)
    create_member(username, welcomed_at: Time.current, tour_completed_at: Time.current,
                            onboarding_dismissed_at: Time.current, **attrs)
  end

  def build_sweep_world
    @member = settled("sweep_member")
    @other = settled("sweep_other")
    @admin = settled("sweep_admin", role: :super_admin)
    [ @member, @other ].each do |u|
      u.brethren_card.update!(church_or_assembly: "Grace Assembly", bio: "A short profile for testing.",
                              occupation: "Builder", whatsapp_number: "+2348012345678", email: u.email)
    end
    ConnectionRequest.create!(sender: @member, receiver: @other, status: :pending)
    ConnectionRequest.find_by(sender: @member, receiver: @other).update!(status: :accepted)
    Follow.create!(follower: @other, following: @member)
    Follow.create!(follower: @member, following: @other)

    @room = Room.create!(name: "Sweep Room", description: "A room for the sweep", room_type: :general, is_public: true)
    RoomMembership.create!(user: @member, room: @room)

    @post = Post.create!(user: @member, room: @room, title: "", content: "Grace and peace to you @sweep_other #hope",
                         status: :published, moderation_status: :approved, allow_comments: true)
    @post.images.attach(png_blob)
    @series = @member.series.create!(title: "Sweep Series")
    @post.update!(series: @series)
    @thread = Post.create!(user: @member, room: @room, kind: :thread, title: "A thread for sweeping",
                           content: "Let us talk about grace together.", status: :published,
                           moderation_status: :approved, allow_comments: true)
    @prayer = Post.create!(user: @other, room: @room, content: "Please pray for my family this week.",
                           status: :published, moderation_status: :approved, prayer_status: :prayer_pending,
                           allow_comments: true)
    @anon = Post.create!(user: @member, content: "An anonymous breath of thanks.", anonymous: true,
                         status: :published, moderation_status: :approved, allow_comments: true)
    @draft = Post.create!(user: @member, content: "Still writing this one.", status: :draft)
    @scheduled = Post.create!(user: @member, content: "Coming soon to the feed.", status: :scheduled,
                              scheduled_for: 2.days.from_now)
    @held = Post.create!(user: @member, content: "Held for review breath.", status: :published,
                         moderation_status: :pending_review)
    @quote = Post.create!(user: @other, content: "Quoting this, amen.", quoted_post: @post, status: :published,
                          moderation_status: :approved)

    @comment = Comment.create!(user: @other, post: @post, content: "Amen to this @sweep_member")
    @reply = Comment.create!(user: @member, post: @post, parent_comment: @comment, content: "Thank you!")
    Like.create!(user: @other, likeable: @post, reaction_type: :amen)
    Like.create!(user: @member, likeable: @comment, reaction_type: :love)
    Reshare.create!(user: @other, post: @post)
    Bookmark.create!(user: @member, post: @prayer)
    PrayerIntercession.create!(user: @member, post: @prayer)
    @prayer.update!(prayer_status: :prayer_answered)

    @circle = Circle.create!(name: "Sweep Circle", owner: @member)
    @circle.circle_memberships.find_or_create_by!(user: @member) { |m| m.role = :owner }
    @circle.circle_memberships.find_or_create_by!(user: @other)
    @circle_breath = CircleBreath.create!(circle: @circle, user: @other, body: "Peace be with this circle.")
    @circle_prayer = CirclePrayer.create!(circle: @circle, user: @other, title: "Pray for rain")
    @circle_prayer.mark_answered!(by: @other)

    @conversation = Conversation.find_or_create_between!(@member, @other)
    @message = Message.create!(conversation: @conversation, sender: @other, body: "Hello brother!")
    @file_message = Message.new(conversation: @conversation, sender: @member, body: "A photo")
    @file_message.images.attach(png_blob)
    @file_message.save!
    @file_attachment = @file_message.images.attachments.first

    @category = ResourceCategory.create!(name: "Sweep Category")
    @resource = Resource.create!(title: "Sweep Resource", description: "Useful", url: "https://example.com/r",
                                 resource_type: :link, user: @member, resource_category: @category)

    @experience = @member.experiences.create!(title: "Builder", organization: "Grace Co", start_on: 2.years.ago.to_date)
    @education = @member.educations.create!(school: "Grace School")
    @certification = @member.certifications.create!(name: "First Aid")
    @portfolio_item = @member.portfolio_items.create!(title: "A good work")
    @member.profile.update!(skills_list: "Carpentry, Teaching", headline: "Builder")
    SkillEndorsement.create!(user: @member, endorser: @other, skill: "Carpentry")

    @report = Report.create!(reporter: @other, reportable: @post, reason: "This looks like spam to me.")
    @review = AiModerationReview.create!(reviewable: @held, user: @member, severity: "medium",
                                         recommended_action: Ai::Moderation::Policy::ACTIONS.first)
    @mod_log = ModerationLog.create!(moderator: @admin, target: @post, action: "hold")
    @bible_verse = BibleVerse.create!(text: "Jesus wept.", reference: "John 11:35")
    @golden_breath = GoldenBreath.create!(text: "Grace upon grace.")
    @broadcast = Broadcast.create!(subject: "Hello all", sender: @admin, body: "<p>Grace and peace to every member this week.</p>")
    @office_conversation = OfficeConversation.create!(user: @admin, title: "Planning")
    @office_card = @office_conversation.messages.create!(role: 1, content: "Here is a draft",
                                                         payload: { "card" => { "kind" => "breath", "title" => "Draft", "body" => "A drafted breath for review." } })
    @figure = ChurchHistoryFigure.first || ChurchHistoryFigure.create!(name: "Augustine", slug: "augustine", era: ChurchHistoryFigure.eras.keys.first)

    Notification.create!(user: @member, actor: @other, notifiable: @member, notification_type: :birthday)
    Notification.create!(user: @member, notifiable: @member.profile, notification_type: :content_removed)
    Notification.create!(user: @member, notifiable: @portfolio_item, notification_type: :content_removed)
    Notification.create!(user: @member, notifiable: @held, notification_type: :post_held_for_review)
    Notification.create!(user: @member, notifiable: @held, notification_type: :post_blocked)
    Notification.create!(user: @member, notifiable: @post, notification_type: :post_featured)
    Notification.create!(user: @member, notifiable: @resource, notification_type: :resource_approved)
    @notification = @member.notifications.order(:id).first
  end

  # The value for a route's path parameter ("posts", "id"), or nil if unknown.
  def sweep_param_for(controller, name)
    case [ controller, name ]
    in [ "circles", "code" ] then @circle.invite_code
    in [ "circles", "slug" ] then @circle.slug
    in [ "rooms/posts", "room_id" ] then @room.to_param
    in [ "rooms", "id" ] then @room.to_param
    in [ "posts", "id" ] then @post.to_param
    in [ "series", "slug" ] | [ "series_parts" | "series_follows", "series_slug" ] then @series.slug
    in [ "series_parts", "id" ] then @post.to_param
    in [ "cards" | "users" | "brethren_cards" | "joins", "username" ] then @member.username
    in [ "portfolio_items", "username" ] then @member.username
    in [ "portfolio_items", "id" ] then @portfolio_item.id
    in [ "resource_items", "id" ] then @resource.to_param
    in [ "resource_categories", "id" ] then @category.to_param
    in [ "scripture_pages", "slug" ] then "john-3-16"
    in [ "index_now_keys", "indexnow_key" ] then "#{IndexNow.key}.txt"
    in [ "sitemaps", "page" ] then "1"
    in [ "church_history", "slug" ] then @figure.slug
    in [ "church_history", "era" ] then ChurchHistoryFigure.eras.keys.first
    in [ "reading_plans", "slug" ] then ReadingPlan.all.first&.slug || "none"
    in [ "notifications", "id" ] then @notification.id
    in [ "blog", "slug" ] then BlogArticle.all.first&.slug || "none"
    in [ "settings/experiences", "id" ] then @experience.id
    in [ "settings/educations", "id" ] then @education.id
    in [ "settings/certifications", "id" ] then @certification.id
    in [ "settings/portfolio_items", "id" ] then @portfolio_item.id
    in [ "conversations", "id" ] then @conversation.id
    in [ "messages", "conversation_id" ] then @conversation.id
    in [ "messages", "id" ] then @message.id
    in [ "message_files", "conversation_id" ] then @conversation.id
    in [ "message_files", "message_id" ] then @file_message.id
    in [ "message_files", "id" ] then @file_attachment.id
    in [ "message_files", "filename" ] then "pixel.png"
    in [ "admin/users", "id" ] then @member.id
    in [ "admin/rooms", "id" ] then @room.to_param
    in [ "admin/posts", "id" ] then @post.to_param
    in [ "admin/resources", "id" ] then @resource.to_param
    in [ "admin/reports", "id" ] then @report.id
    in [ "admin/moderation_logs", "id" ] then @mod_log.id
    in [ "admin/bible_verses", "id" ] then @bible_verse.id
    in [ "admin/golden_breaths", "id" ] then @golden_breath.id
    in [ "admin/moderation_reviews", "id" ] then @review.id
    in [ "admin/broadcasts", "id" ] then @broadcast.id
    in [ "admin/office/conversations", "id" ] then @office_conversation.id
    in [ "admin/office/cards", "id" ] then @office_card.id
    in [ "email_unsubscribes", "token" ] then "not-a-real-token"
    else nil
    end
  end
end
