# frozen_string_literal: true

namespace :faith do
  desc "Seed starter production rooms, resource library items, and promote the owner admin"
  task seed_starter_content: :environment do
    admin = seed_owner_admin!

    starter_rooms.each do |attributes|
      room = Room.find_or_initialize_by(name: attributes.fetch(:name))
      room.assign_attributes(attributes)
      room.is_public = true
      room.save!
    end

    categories = {}
    starter_resource_categories.each do |attributes|
      category = ResourceCategory.find_or_initialize_by(name: attributes.fetch(:name))
      category.assign_attributes(attributes)
      category.save!
      categories[category.name] = category
    end

    starter_resources.each do |attributes|
      category = categories.fetch(attributes.delete(:category))
      resource = Resource.find_or_initialize_by(title: attributes.fetch(:title))
      resource.assign_attributes(
        attributes.merge(
          user: admin,
          resource_category: category,
          approved: true,
          approved_by: admin,
          approved_at: Time.current
        )
      )
      resource.save!
    end

    puts "Seeded #{starter_rooms.size} rooms."
    puts "Seeded #{starter_resource_categories.size} resource categories."
    puts "Seeded #{starter_resources.size} approved starter resources."
    puts "Promoted #{admin.email} to #{admin.role}."
  end

  def seed_owner_admin!
    user = User.find_or_initialize_by(email: "wintan1418@gmail.com")

    if user.new_record?
      user.username = available_owner_username
      user.password = SecureRandom.hex(16)
      user.password_confirmation = user.password
    end

    user.role = :admin
    user.active = true if user.respond_to?(:active=)
    user.verified_at ||= Time.current if user.respond_to?(:verified_at=)
    user.save!

    user.profile&.update!(
      bio: "Faith Community owner and platform administrator.",
      faith_background: "Building a thoughtful home for faith-filled conversation."
    )

    user
  end

  def starter_rooms
    [
      {
        name: "Prayer Requests",
        description: "A focused room for asking for prayer, standing with others, and returning with praise reports.",
        room_type: :prayers,
        icon: "pray",
        color: "#10b981",
        rules: "Keep requests respectful and confidential. Avoid sharing another person's private details without permission.",
        position: 1
      },
      {
        name: "Testimonies",
        description: "Share how God has helped, restored, provided, healed, or carried you through a season.",
        room_type: :testimonies,
        icon: "sparkles",
        color: "#f59e0b",
        rules: "Tell the truth with humility. Encourage others without turning the room into self-promotion.",
        position: 2
      },
      {
        name: "Bible Study",
        description: "Discuss scripture, study notes, devotionals, and questions from the Word.",
        room_type: :scripture,
        icon: "book-open",
        color: "#2563eb",
        rules: "Use scripture references where possible. Disagree with patience and keep the focus on growth.",
        position: 3
      },
      {
        name: "Questions & Guidance",
        description: "Ask honest faith questions and receive thoughtful, scripture-shaped counsel from the community.",
        room_type: :questions,
        icon: "message-circle-question",
        color: "#14b8a6",
        rules: "Answer with humility. Do not shame questions. Point people toward wisdom, prayer, and scripture.",
        position: 4
      },
      {
        name: "Encouragement",
        description: "Short encouragements, verses, reminders, and words that help people keep going.",
        room_type: :growth,
        icon: "heart-handshake",
        color: "#22c55e",
        rules: "Keep it uplifting and sincere. Avoid arguments and heavy debates in this room.",
        position: 5
      },
      {
        name: "Faith Journey",
        description: "A place to reflect on spiritual growth, discipline, doubts, milestones, and lessons from daily walking with God.",
        room_type: :growth,
        icon: "route",
        color: "#0ea5e9",
        rules: "Share your journey honestly. Respect different growth seasons and avoid comparison.",
        position: 6
      },
      {
        name: "Worship & Music",
        description: "Share worship songs, playlists, lyrics reflections, and creative worship moments.",
        room_type: :general,
        icon: "music",
        color: "#8b5cf6",
        rules: "Credit creators where needed. Keep shared content edifying and appropriate.",
        position: 7
      },
      {
        name: "Serving & Outreach",
        description: "Coordinate outreach ideas, service opportunities, mission stories, and ways to love people practically.",
        room_type: :general,
        icon: "hand-heart",
        color: "#ef4444",
        rules: "Share legitimate opportunities only. Serve with humility and protect vulnerable people.",
        position: 8
      }
    ]
  end

  def starter_resource_categories
    [
      { name: "Bible Study", description: "Tools for reading, understanding, and applying scripture.", icon: "book-open", position: 1 },
      { name: "Prayer", description: "Guides and resources for personal and communal prayer.", icon: "hands", position: 2 },
      { name: "Discipleship", description: "Materials for spiritual growth, habits, and following Jesus daily.", icon: "footprints", position: 3 },
      { name: "Sermons & Teaching", description: "Trusted teaching libraries and message archives.", icon: "video", position: 4 },
      { name: "Worship", description: "Music, audio scripture, and worship resources.", icon: "music", position: 5 },
      { name: "Care & Counsel", description: "Resources for grief, anxiety, relationships, and pastoral care.", icon: "heart", position: 6 }
    ]
  end

  def starter_resources
    [
      {
        category: "Bible Study",
        title: "BibleProject",
        description: "Accessible Bible videos, podcasts, classes, and book overviews for understanding scripture as one unified story.",
        resource_type: :video,
        url: "https://bibleproject.com/",
        featured: true
      },
      {
        category: "Bible Study",
        title: "Bible Gateway",
        description: "A searchable Bible reading and study tool with multiple translations, reading plans, and passage lookup.",
        resource_type: :link,
        url: "https://www.biblegateway.com/",
        featured: true
      },
      {
        category: "Bible Study",
        title: "Enduring Word Commentary",
        description: "Free Bible commentary and study notes for personal reading, teaching preparation, and group study.",
        resource_type: :link,
        url: "https://enduringword.com/",
        featured: false
      },
      {
        category: "Prayer",
        title: "24-7 Prayer",
        description: "Prayer guides, ideas, and resources for building a deeper rhythm of prayer.",
        resource_type: :link,
        url: "https://www.24-7prayer.com/",
        featured: true
      },
      {
        category: "Prayer",
        title: "YouVersion Prayer",
        description: "Prayer lists, guided prayer, and Bible app tools that help people pray consistently.",
        resource_type: :link,
        url: "https://www.youversion.com/the-bible-app/",
        featured: false
      },
      {
        category: "Discipleship",
        title: "The Navigators Discipleship Resources",
        description: "Practical discipleship tools for spiritual habits, scripture memory, mentoring, and small groups.",
        resource_type: :link,
        url: "https://www.navigators.org/resource/",
        featured: true
      },
      {
        category: "Discipleship",
        title: "Practicing the Way",
        description: "Resources for apprentices of Jesus, spiritual formation, community practice, and rule of life.",
        resource_type: :link,
        url: "https://www.practicingtheway.org/",
        featured: true
      },
      {
        category: "Sermons & Teaching",
        title: "The Gospel Coalition",
        description: "Articles, essays, podcasts, and teaching resources from a broad evangelical network.",
        resource_type: :link,
        url: "https://www.thegospelcoalition.org/",
        featured: false
      },
      {
        category: "Sermons & Teaching",
        title: "Desiring God",
        description: "Sermons, devotionals, books, podcasts, and articles focused on Christian joy and doctrine.",
        resource_type: :link,
        url: "https://www.desiringgod.org/",
        featured: false
      },
      {
        category: "Worship",
        title: "Streetlights Bible",
        description: "Audio Bible and scripture-centered music designed for listening, worship, and meditation.",
        resource_type: :link,
        url: "https://www.streetlightsbible.com/",
        featured: true
      },
      {
        category: "Worship",
        title: "Dwell Audio Bible",
        description: "An audio Bible experience for scripture listening, plans, and reflective engagement with the Word.",
        resource_type: :link,
        url: "https://dwellapp.io/",
        featured: false
      },
      {
        category: "Care & Counsel",
        title: "Biblical Counseling Coalition",
        description: "Articles and resources for biblical care, counseling, suffering, relationships, and wise pastoral support.",
        resource_type: :link,
        url: "https://www.biblicalcounselingcoalition.org/",
        featured: true
      },
      {
        category: "Care & Counsel",
        title: "GriefShare",
        description: "Support resources and group-finder tools for people walking through grief and loss.",
        resource_type: :link,
        url: "https://www.griefshare.org/",
        featured: false
      }
    ]
  end

  def available_owner_username
    return "wintan1418" unless User.exists?(username: "wintan1418")

    "wintan1418_admin"
  end
end
