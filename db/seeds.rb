# frozen_string_literal: true

puts "Seeding database..."

# Create default rooms
rooms_data = [
  {
    name: "Share Your Experience",
    description: "A space for sharing your testimony and how God has worked in your life. Every story matters and can encourage others in their faith journey.",
    room_type: :testimonies,
    icon: "✨",
    color: "#FFD700",
    rules: "Be respectful and encouraging. Share authentically but maintain appropriate boundaries.",
    position: 1
  },
  {
    name: "Overcoming Struggles",
    description: "Celebrate victories and share how you've overcome challenges through faith. Your victory story can be someone else's survival guide.",
    room_type: :struggles,
    icon: "💪",
    color: "#4CAF50",
    rules: "Focus on hope and encouragement. Be sensitive to others who may still be struggling.",
    position: 2
  },
  {
    name: "Prayer Requests",
    description: "Submit your prayer requests and join others in prayer. Let's bear one another's burdens and lift each other up in prayer.",
    room_type: :prayers,
    icon: "🙏",
    color: "#9C27B0",
    rules: "Respect privacy. Don't share others' requests without permission. Commit to praying for those you respond to.",
    position: 3
  },
  {
    name: "Past Struggles",
    description: "A safe space for healing and reflection on past challenges. Share your journey of recovery and restoration.",
    room_type: :struggles,
    icon: "🌅",
    color: "#FF7043",
    rules: "Content may be sensitive. Share with discretion and trigger warnings when needed.",
    position: 4
  },
  {
    name: "Faith Journey",
    description: "Document and share your personal growth in faith. Discuss the ups and downs of walking with God daily.",
    room_type: :growth,
    icon: "🌱",
    color: "#8BC34A",
    rules: "Be authentic about your journey, including struggles. Encourage questions and growth.",
    position: 5
  },
  {
    name: "Scripture Reflections",
    description: "Share insights from your Bible study, devotionals, and meditation on God's Word. Let's grow in understanding together.",
    room_type: :scripture,
    icon: "📖",
    color: "#3F51B5",
    rules: "Include scripture references. Be open to different interpretations. Focus on what unites us.",
    position: 6
  },
  {
    name: "Questions & Guidance",
    description: "Seek spiritual advice and wisdom from the community. No question is too small or too big when we seek together.",
    room_type: :questions,
    icon: "❓",
    color: "#00BCD4",
    rules: "Be humble in answering. Point to scripture. Respect that we may have different perspectives.",
    position: 7
  }
]

rooms_data.each do |room_data|
  Room.find_or_create_by!(name: room_data[:name]) do |room|
    room.description = room_data[:description]
    room.room_type = room_data[:room_type]
    room.icon = room_data[:icon]
    room.color = room_data[:color]
    room.rules = room_data[:rules]
    room.position = room_data[:position]
    room.is_public = true
  end
end

puts "Created #{Room.count} rooms"

# Create resource categories
categories_data = [
  { name: "Articles & Blogs", description: "Written content for spiritual growth", icon: "📝", position: 1 },
  { name: "Videos & Sermons", description: "Video content including sermons and teachings", icon: "🎬", position: 2 },
  { name: "Audio & Podcasts", description: "Audio resources and podcasts", icon: "🎧", position: 3 },
  { name: "Books & E-Books", description: "Book recommendations and digital books", icon: "📚", position: 4 },
  { name: "Bible Study Guides", description: "Guides and materials for Bible study", icon: "📖", position: 5 },
  { name: "Devotionals", description: "Daily devotionals and meditation materials", icon: "🌅", position: 6 }
]

categories_data.each do |cat_data|
  ResourceCategory.find_or_create_by!(name: cat_data[:name]) do |cat|
    cat.description = cat_data[:description]
    cat.icon = cat_data[:icon]
    cat.position = cat_data[:position]
  end
end

puts "Created #{ResourceCategory.count} resource categories"

# Create admin user (only in development)
if Rails.env.development?
  admin = User.find_or_initialize_by(email: "admin@faithcommunity.com")
  if admin.new_record?
    admin.username = "admin"
    admin.password = "password123"
    admin.password_confirmation = "password123"
    admin.role = :admin
    admin.skip_confirmation!
    admin.save!
    
    admin.profile.update(
      bio: "Welcome to Faith Community! I'm here to help.",
      faith_background: "Platform Administrator"
    )
    
    puts "Created admin user: admin@faithcommunity.com / password123"
  end

  # Create some test users
  5.times do |i|
    user = User.find_or_initialize_by(email: "user#{i + 1}@example.com")
    if user.new_record?
      user.username = "testuser#{i + 1}"
      user.password = "password123"
      user.password_confirmation = "password123"
      user.skip_confirmation!
      user.save!
      
      user.profile.update(
        bio: "Test user #{i + 1} bio here.",
        location: ["New York", "Los Angeles", "Chicago", "Houston", "Phoenix"][i]
      )
    end
  end

  puts "Created #{User.count} users"
end

puts "Seeding complete!"
