# frozen_string_literal: true

require 'open-uri'
require 'net/http'

puts "🌱 Seeding Faith Community database..."
puts "=" * 50

# Helper to attach images from URL
def attach_image_from_url(record, attachment_name, url, filename)
  begin
    require 'open-uri'
    require 'net/http'
    
    # Try using Net::HTTP first for better control
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true if uri.scheme == 'https'
    http.read_timeout = 10
    http.open_timeout = 10
    
    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)
    
    # Follow redirects
    if response.is_a?(Net::HTTPRedirection)
      redirect_uri = URI.parse(response['location'])
      redirect_uri = URI.parse("#{uri.scheme}://#{uri.host}#{redirect_uri}") if redirect_uri.relative?
      http = Net::HTTP.new(redirect_uri.host, redirect_uri.port)
      http.use_ssl = true if redirect_uri.scheme == 'https'
      http.read_timeout = 10
      http.open_timeout = 10
      request = Net::HTTP::Get.new(redirect_uri.request_uri)
      response = http.request(request)
    end
    
    if response.is_a?(Net::HTTPSuccess)
      io = StringIO.new(response.body)
      content_type = response['content-type'] || 'image/jpeg'
      
      record.send(attachment_name).attach(
        io: io,
        filename: filename,
        content_type: content_type
      )
      true
    else
      puts "    ⚠️  HTTP error: #{response.code} for #{url}"
      false
    end
  rescue => e
    puts "    ⚠️  Could not attach image from #{url}: #{e.message}"
    false
  end
end

# Clear existing data in development
if Rails.env.development?
  puts "🧹 Clearing existing data..."
  [ConnectionRequest, BrethrenCard, ModerationLog, Report, Notification, Bookmark, Follow, Like, Comment, PostTag, Post, Resource, ResourceCategory, RoomMembership, Room, Profile, User, Tag].each do |model|
    model.destroy_all
  end
  ActionText::RichText.destroy_all
  ActiveStorage::Attachment.destroy_all
  ActiveStorage::Blob.destroy_all
end

# ==========================================
# ROOMS
# ==========================================
puts "\n📦 Creating rooms..."

rooms_data = [
  {
    name: "Share Your Experience",
    description: "A space for sharing your testimony and how God has worked in your life. Every story matters and can encourage others in their faith journey.",
    room_type: :testimonies,
    icon: "✨",
    color: "#FFD700",
    rules: "Be respectful and encouraging. Share authentically but maintain appropriate boundaries. Focus on how God has worked in your situation.",
    position: 1
  },
  {
    name: "Overcoming Struggles",
    description: "Celebrate victories and share how you've overcome challenges through faith. Your victory story can be someone else's survival guide.",
    room_type: :struggles,
    icon: "💪",
    color: "#4CAF50",
    rules: "Focus on hope and encouragement. Be sensitive to others who may still be struggling. Share practical steps that helped you.",
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
    rules: "Content may be sensitive. Share with discretion and trigger warnings when needed. Be compassionate in responses.",
    position: 4
  },
  {
    name: "Faith Journey",
    description: "Document and share your personal growth in faith. Discuss the ups and downs of walking with God daily.",
    room_type: :growth,
    icon: "🌱",
    color: "#8BC34A",
    rules: "Be authentic about your journey, including struggles. Encourage questions and growth. Celebrate small victories.",
    position: 5
  },
  {
    name: "Scripture Reflections",
    description: "Share insights from your Bible study, devotionals, and meditation on God's Word. Let's grow in understanding together.",
    room_type: :scripture,
    icon: "📖",
    color: "#3F51B5",
    rules: "Include scripture references. Be open to different interpretations. Focus on what unites us in Christ.",
    position: 6
  },
  {
    name: "Questions & Guidance",
    description: "Seek spiritual advice and wisdom from the community. No question is too small or too big when we seek together.",
    room_type: :questions,
    icon: "❓",
    color: "#00BCD4",
    rules: "Be humble in answering. Point to scripture. Respect that we may have different perspectives on non-essential matters.",
    position: 7
  },
  {
    name: "Brethren in Business",
    description: "Connect with fellow believers in business. Share opportunities, seek godly counsel, and support each other in conducting business with integrity and excellence.",
    room_type: :general,
    icon: "💼",
    color: "#2196F3",
    rules: "Maintain ethical standards. No spam or self-promotion without value. Focus on building godly business relationships.",
    position: 8
  },
  {
    name: "Brethren in Art",
    description: "A space for Christian artists to share their work, collaborate, and use their creative gifts to glorify God. All forms of art welcome.",
    room_type: :general,
    icon: "🎨",
    color: "#E91E63",
    rules: "Share original work or give credit. Use art to edify and inspire. Keep content appropriate and God-honoring.",
    position: 9
  },
  {
    name: "Brethren in Tech",
    description: "For believers working in technology. Share knowledge, discuss ethical tech practices, and support each other in using tech for God's glory.",
    room_type: :general,
    icon: "💻",
    color: "#00BCD4",
    rules: "Share knowledge generously. Discuss tech ethics from a biblical perspective. Help each other grow professionally and spiritually.",
    position: 10
  },
  {
    name: "The Married Room",
    description: "A private space for married couples to share wisdom, seek advice, and support each other in building godly marriages. Strengthen your union in Christ.",
    room_type: :general,
    icon: "💑",
    color: "#F06292",
    rules: "Respect privacy. Share wisdom, not gossip. Focus on building strong, Christ-centered marriages. Married couples only.",
    position: 11
  },
  {
    name: "Single Ladies",
    description: "A safe space for single women to connect, share experiences, and encourage each other in their walk with God. Find sisterhood and support.",
    room_type: :general,
    icon: "👩",
    color: "#EC407A",
    rules: "Be encouraging and supportive. Respect each other's journey. Focus on growing in Christ individually and as a community.",
    position: 12
  },
  {
    name: "Single Brothers",
    description: "A space for single men to connect, share struggles and victories, and encourage each other in godly manhood. Build brotherhood in Christ.",
    room_type: :general,
    icon: "👨",
    color: "#42A5F5",
    rules: "Be authentic and supportive. Encourage accountability. Focus on growing as godly men and preparing for God's purpose.",
    position: 13
  },
  {
    name: "Teenagers",
    description: "A space for young believers (13-19) to connect, share their faith journey, ask questions, and support each other. Navigate life with Christ together.",
    room_type: :general,
    icon: "🎓",
    color: "#FF9800",
    rules: "Be respectful and encouraging. No bullying or inappropriate content. Adults may moderate but this is primarily for teens.",
    position: 14
  },
  {
    name: "Parents Room",
    description: "For parents to share wisdom, seek advice, and support each other in raising children in the fear and admonition of the Lord. Parenting with purpose.",
    room_type: :general,
    icon: "👨‍👩‍👧‍👦",
    color: "#4CAF50",
    rules: "Share practical wisdom. Be non-judgmental. Focus on biblical principles for parenting. Respect different parenting styles within biblical boundaries.",
    position: 15
  },
  {
    name: "Recipe Room",
    description: "Share your favorite recipes, cooking tips, and meal ideas. Break bread together, literally! Food brings us together in fellowship.",
    room_type: :general,
    icon: "🍳",
    color: "#FF5722",
    rules: "Share complete recipes. Include preparation time and serving size when possible. Be mindful of dietary restrictions and allergies.",
    position: 16
  },
  {
    name: "Fitness & Wellness",
    description: "Honor God with your body. Share fitness tips, healthy recipes, and encouragement for physical and spiritual wellness. Stewardship of health.",
    room_type: :general,
    icon: "💪",
    color: "#4CAF50",
    rules: "Focus on health, not appearance. Be encouraging, not judgmental. Share what works for you while respecting different approaches.",
    position: 17
  },
  {
    name: "Music & Worship",
    description: "Share worship songs, original music, and discuss how music draws us closer to God. Let's make a joyful noise together!",
    room_type: :general,
    icon: "🎵",
    color: "#9C27B0",
    rules: "Share original work or give proper credit. Keep content worshipful and God-honoring. Encourage each other's musical gifts.",
    position: 18
  },
  {
    name: "Book Club",
    description: "Discuss Christian books, devotionals, and literature that has impacted your faith. Grow through reading and discussion together.",
    room_type: :general,
    icon: "📚",
    color: "#795548",
    rules: "Share book recommendations with brief reviews. Discuss respectfully. Focus on books that edify and build faith.",
    position: 19
  },
  {
    name: "Missions & Outreach",
    description: "Share mission experiences, outreach opportunities, and ways to serve locally and globally. Let's be the hands and feet of Jesus.",
    room_type: :general,
    icon: "🌍",
    color: "#FF9800",
    rules: "Share legitimate opportunities. Be respectful of different cultures. Focus on serving with humility and love.",
    position: 20
  },
  {
    name: "Prayer Warriors",
    description: "A dedicated space for intercessors and prayer warriors. Share prayer strategies, answered prayers, and stand in the gap together.",
    room_type: :prayers,
    icon: "⚔️",
    color: "#9C27B0",
    rules: "Commit to praying for requests shared here. Share testimonies of answered prayers. Maintain confidentiality when requested.",
    position: 21
  },
  {
    name: "Bible Study",
    description: "Deep dive into scripture together. Share study notes, discuss passages, and grow in understanding God's Word as a community.",
    room_type: :scripture,
    icon: "📖",
    color: "#3F51B5",
    rules: "Include scripture references. Be open to different interpretations while staying true to biblical truth. Respect theological differences on non-essentials.",
    position: 22
  },
  {
    name: "Young Adults",
    description: "For young adults (20-30) navigating career, relationships, and life decisions. Find community and godly counsel as you build your future.",
    room_type: :general,
    icon: "🌟",
    color: "#00BCD4",
    rules: "Be supportive and encouraging. Share wisdom from your journey. Focus on building godly foundations for the future.",
    position: 23
  },
  {
    name: "Seniors' Corner",
    description: "A space for mature believers to share wisdom, life experiences, and encourage the next generation. Your testimony is valuable!",
    room_type: :general,
    icon: "👴",
    color: "#607D8B",
    rules: "Share wisdom generously. Be patient with questions. Your experience is a gift to the community.",
    position: 24
  }
]

rooms = rooms_data.map do |room_data|
  Room.create!(
    name: room_data[:name],
    description: room_data[:description],
    room_type: room_data[:room_type],
    icon: room_data[:icon],
    color: room_data[:color],
    rules: room_data[:rules],
    position: room_data[:position],
    is_public: true
  )
end

puts "  ✓ Created #{Room.count} rooms"

# ==========================================
# RESOURCE CATEGORIES
# ==========================================
puts "\n📚 Creating resource categories..."

categories_data = [
  { name: "Articles & Blogs", description: "Written content for spiritual growth and biblical insights", icon: "📝", position: 1 },
  { name: "Videos & Sermons", description: "Video content including sermons, teachings, and testimonies", icon: "🎬", position: 2 },
  { name: "Audio & Podcasts", description: "Audio resources, podcasts, and recorded messages", icon: "🎧", position: 3 },
  { name: "Books & E-Books", description: "Book recommendations and digital reading materials", icon: "📚", position: 4 },
  { name: "Bible Study Guides", description: "Guides and materials for individual and group Bible study", icon: "📖", position: 5 },
  { name: "Devotionals", description: "Daily devotionals and meditation materials for spiritual growth", icon: "🌅", position: 6 }
]

categories = categories_data.map do |cat_data|
  ResourceCategory.create!(
    name: cat_data[:name],
    description: cat_data[:description],
    icon: cat_data[:icon],
    position: cat_data[:position]
  )
end

puts "  ✓ Created #{ResourceCategory.count} resource categories"

# ==========================================
# TAGS
# ==========================================
puts "\n🏷️  Creating tags..."

tag_names = [
  "testimony", "prayer", "faith", "hope", "love", "healing", "forgiveness",
  "family", "marriage", "parenting", "anxiety", "depression", "addiction",
  "grief", "loss", "gratitude", "worship", "praise", "bible-study", "devotional",
  "encouragement", "wisdom", "guidance", "salvation", "baptism", "discipleship",
  "missions", "evangelism", "church", "community", "fellowship", "spiritual-growth",
  "peace", "joy", "patience", "kindness", "goodness", "faithfulness", "gentleness",
  "self-control", "breakthrough", "miracle", "provision", "protection", "restoration"
]

tags = tag_names.map { |name| Tag.create!(name: name) }
puts "  ✓ Created #{Tag.count} tags"

# ==========================================
# USERS
# ==========================================
puts "\n👥 Creating users..."

# Admin user
admin = User.new(
  email: "admin@faithcommunity.com",
  username: "admin",
  password: "password123",
  password_confirmation: "password123",
  role: :admin
)
admin.skip_confirmation!
admin.save!
admin.profile.update!(
  bio: "Platform administrator for Faith Community. Here to serve and support our growing community of believers.",
  faith_background: "Serving Christ for over 20 years",
  location: "Online",
  website: "https://faithcommunity.com"
)

# Attach avatar for admin
avatar_url = "https://api.dicebear.com/7.x/avataaars/png?seed=admin&size=200&backgroundColor=ffd5dc"
puts "    🖼️  Adding avatar for admin..."
attach_image_from_url(admin.profile, :avatar, avatar_url, "avatar_admin.png")

# Moderator users
moderators_data = [
  { email: "pastor.james@faithcommunity.com", username: "PastorJames", bio: "Senior Pastor with a heart for discipleship and community building. Love seeing lives transformed by God's grace.", faith_background: "Ministry leader for 15 years", location: "Dallas, TX" },
  { email: "sarah.worship@faithcommunity.com", username: "SarahWorship", bio: "Worship leader and songwriter. Using music to draw hearts closer to God.", faith_background: "Leading worship since age 16", location: "Nashville, TN" }
]

moderators = moderators_data.map.with_index do |data, idx|
  user = User.new(
    email: data[:email],
    username: data[:username],
    password: "password123",
    password_confirmation: "password123",
    role: :moderator
  )
  user.skip_confirmation!
  user.save!
  user.profile.update!(bio: data[:bio], faith_background: data[:faith_background], location: data[:location])
  
  # Attach avatar using UI Avatars or DiceBear
  avatar_url = "https://api.dicebear.com/7.x/avataaars/png?seed=#{data[:username]}&size=200&backgroundColor=b6e3f4,c0aede,d1d4f9"
  puts "    🖼️  Adding avatar for #{data[:username]}..."
  attach_image_from_url(user.profile, :avatar, avatar_url, "avatar_#{data[:username]}.png")
  
  user
end

# Regular members with diverse backgrounds
members_data = [
  { email: "john.grace@example.com", username: "JohnGrace", bio: "Former atheist, now passionate about sharing how God transformed my life. Father of 3.", faith_background: "Saved 5 years ago", location: "Chicago, IL" },
  { email: "maria.hope@example.com", username: "MariaHope", bio: "Single mom finding strength in Christ daily. Love coffee, books, and authentic community.", faith_background: "Raised in faith, renewed at 30", location: "Miami, FL" },
  { email: "david.warrior@example.com", username: "DavidWarrior", bio: "Army veteran finding purpose in serving God. Passionate about men's ministry and discipleship.", faith_background: "Baptized overseas during deployment", location: "San Antonio, TX" },
  { email: "rachel.light@example.com", username: "RachelLight", bio: "College student navigating faith in a secular environment. Love deep theological discussions!", faith_background: "Third generation believer", location: "Boston, MA" },
  { email: "michael.restored@example.com", username: "MichaelRestored", bio: "Recovered from addiction through Christ. Now helping others find the same freedom.", faith_background: "Clean and saved for 7 years", location: "Phoenix, AZ" },
  { email: "emily.prayer@example.com", username: "EmilyPrayer", bio: "Intercessor and prayer warrior. Believe in the power of united prayer!", faith_background: "Prayer ministry for 10 years", location: "Seattle, WA" },
  { email: "daniel.seeker@example.com", username: "DanielSeeker", bio: "Software developer by day, Bible student by passion. Love connecting faith and logic.", faith_background: "Converted from Judaism", location: "San Francisco, CA" },
  { email: "grace.renewed@example.com", username: "GraceRenewed", bio: "Divorced and healed. God makes beauty from ashes. Passionate about women's ministry.", faith_background: "Found Christ in my darkest hour", location: "Atlanta, GA" },
  { email: "peter.builder@example.com", username: "PeterBuilder", bio: "Construction worker building God's kingdom one relationship at a time. Simple faith, big God.", faith_background: "Lifelong believer", location: "Denver, CO" },
  { email: "anna.missionary@example.com", username: "AnnaMissionary", bio: "Returned missionary sharing stories of God's faithfulness around the world.", faith_background: "10 years in missions", location: "Orlando, FL" },
  { email: "luke.physician@example.com", username: "DrLukeHeal", bio: "Christian physician seeing God's healing in both medicine and miracles.", faith_background: "Faith deepened through medical training", location: "Houston, TX" },
  { email: "ruth.faithful@example.com", username: "RuthFaithful", bio: "Grandmother of 8, sharing wisdom from decades of walking with Jesus.", faith_background: "65 years with the Lord", location: "Nashville, TN" },
  { email: "timothy.young@example.com", username: "TimothyYoung", bio: "Youth pastor passionate about the next generation knowing Christ.", faith_background: "Called to ministry at 18", location: "Portland, OR" },
  { email: "esther.brave@example.com", username: "EstherBrave", bio: "Advocate for persecuted Christians. Using my voice for the voiceless.", faith_background: "Immigrant believer", location: "New York, NY" },
  { email: "paul.transformed@example.com", username: "PaulTransformed", bio: "Former gang member, now church planter. Nothing is impossible with God!", faith_background: "Radical conversion at 25", location: "Los Angeles, CA" }
]

members = members_data.map.with_index do |data, idx|
  user = User.new(
    email: data[:email],
    username: data[:username],
    password: "password123",
    password_confirmation: "password123",
    role: :member
  )
  user.skip_confirmation!
  user.save!
  user.profile.update!(bio: data[:bio], faith_background: data[:faith_background], location: data[:location])
  
  # Attach avatar - alternate between different avatar styles
  styles = ['avataaars', 'lorelei', 'micah', 'notionists', 'open-peeps', 'personas']
  style = styles[idx % styles.length]
  avatar_url = "https://api.dicebear.com/7.x/#{style}/png?seed=#{data[:username]}&size=200&backgroundColor=b6e3f4,c0aede,d1d4f9,ffd5dc,ffdfbf"
  puts "    🖼️  Adding avatar for #{data[:username]}..."
  attach_image_from_url(user.profile, :avatar, avatar_url, "avatar_#{data[:username]}.png")
  
  user
end

all_users = [admin] + moderators + members
puts "  ✓ Created #{User.count} users (1 admin, #{moderators.count} moderators, #{members.count} members)"

# ==========================================
# FOLLOWS
# ==========================================
puts "\n🤝 Creating follow relationships..."

# Create random follow relationships
all_users.each do |user|
  # Each user follows 3-8 random other users
  users_to_follow = (all_users - [user]).sample(rand(3..8))
  users_to_follow.each do |followed|
    Follow.create!(follower: user, following: followed) rescue nil
  end
end

puts "  ✓ Created #{Follow.count} follow relationships"

# ==========================================
# POSTS
# ==========================================
puts "\n📝 Creating posts..."

posts_content = [
  # Share Your Experience (Testimonies)
  {
    room: rooms[0], # Share Your Experience
    user: members[0], # JohnGrace
    title: "From Atheism to Amazing Grace - My Testimony",
    content: "<div>Five years ago, I was a committed atheist. I had all the arguments, all the 'proof' that God didn't exist. But God had other plans.</div><div><br></div><div>It started when my daughter was diagnosed with a rare illness. The doctors gave us little hope. In my desperation, I did something I never thought I'd do - I prayed.</div><div><br></div><div>What happened next changed everything. Not only did my daughter recover (the doctors called it 'unexpected'), but I felt something I couldn't explain. A peace. A presence. Something real.</div><div><br></div><div>I started reading the Bible, skeptically at first. But the more I read, the more it made sense. The more I prayed, the more I experienced God's reality.</div><div><br></div><div>Today, I stand as a living testimony that no one is too far from God's reach. If He can change this stubborn atheist's heart, He can reach anyone.</div><div><br></div><blockquote>\"For I know the plans I have for you,\" declares the LORD, \"plans to prosper you and not to harm you, plans to give you hope and a future.\" - Jeremiah 29:11</blockquote>",
    tags: ["testimony", "salvation", "faith", "healing", "hope"],
    featured: true,
    views: rand(500..2000),
    published_ago: rand(1..60).days.ago
  },
  {
    room: rooms[0],
    user: members[4], # MichaelRestored
    title: "7 Years Clean - How Jesus Broke My Chains",
    content: "<div>Today marks 7 years of freedom from addiction. Seven years ago, I was homeless, hopeless, and one bad decision away from death.</div><div><br></div><div>Alcohol and drugs had taken everything - my family, my career, my dignity. I had tried rehab three times. Nothing worked.</div><div><br></div><div>Then I met a man at a shelter who told me about Jesus. I laughed at first. But he just smiled and said, 'I was where you are. Jesus saved me. He can save you too.'</div><div><br></div><div>That night, alone and desperate, I got on my knees for the first time in my life. I said the ugliest, most honest prayer: 'God, if you're real, help me. I can't do this anymore.'</div><div><br></div><div>That was the beginning of my new life. It wasn't easy - recovery never is. But with God, with church family, with accountability, I made it. Not just surviving, but thriving.</div><div><br></div><div>If you're struggling today, please know: there IS hope. There IS freedom. His name is Jesus.</div>",
    tags: ["testimony", "addiction", "healing", "breakthrough", "restoration"],
    featured: true,
    views: rand(800..3000),
    published_ago: rand(1..45).days.ago
  },
  {
    room: rooms[0],
    user: members[7], # GraceRenewed
    title: "Beauty from Ashes - Finding God After Divorce",
    content: "<div>I never thought I'd be writing this. Divorce wasn't supposed to be part of my story. I grew up believing it was the ultimate failure.</div><div><br></div><div>When my 15-year marriage ended due to my husband's choices, I felt like God had abandoned me. I questioned everything - my faith, my worth, my future.</div><div><br></div><div>But in the rubble of my broken dreams, God began to build something new. He showed me that my identity was never in my marriage - it was always in Him.</div><div><br></div><div>Three years later, I can honestly say I'm more whole, more at peace, and more in love with Jesus than ever before. He didn't just heal me - He transformed me.</div><div><br></div><div>To anyone going through something similar: you are not your circumstances. You are not damaged goods. You are beloved, chosen, and destined for more than you can imagine.</div><div><br></div><blockquote>\"He has sent me to bind up the brokenhearted... to bestow on them a crown of beauty instead of ashes.\" - Isaiah 61:1-3</blockquote>",
    tags: ["testimony", "healing", "restoration", "hope", "faith"],
    views: rand(400..1500),
    published_ago: rand(1..30).days.ago
  },

  # Overcoming Struggles
  {
    room: rooms[1], # Overcoming Struggles
    user: members[1], # MariaHope
    title: "Single Mom Victory: How I Found Peace in the Chaos",
    content: "<div>Being a single mom of three wasn't in my life plan. When my husband left, I was terrified. How would I provide? How would I raise godly children alone?</div><div><br></div><div>But God... (don't you love those words?)</div><div><br></div><div>Here's what I've learned in 4 years of single parenting:</div><div><br></div><div><strong>1. God provides in unexpected ways</strong><br>From surprise checks in the mail to neighbors who \"happened\" to have extra groceries, I've seen provision I can't explain naturally.</div><div><br></div><div><strong>2. Community is essential</strong><br>I had to swallow my pride and accept help. My church family has been incredible - rides, meals, childcare, prayer.</div><div><br></div><div><strong>3. Quality over quantity</strong><br>I can't give my kids everything, but I can give them a mom who loves Jesus and loves them fiercely.</div><div><br></div><div><strong>4. Joy is a choice</strong><br>Some days are hard. Really hard. But I choose to find three things to thank God for every day. It changes everything.</div><div><br></div><div>If you're walking a hard road today, know this: you're not alone, and this season won't last forever. Keep pressing in!</div>",
    tags: ["family", "parenting", "faith", "provision", "encouragement"],
    views: rand(600..2000),
    published_ago: rand(1..40).days.ago
  },
  {
    room: rooms[1],
    user: members[2], # DavidWarrior
    title: "From PTSD to Peace - A Veteran's Faith Journey",
    content: "<div>Combat changes you. I came home from three deployments a different man - angry, anxious, unable to sleep without nightmares.</div><div><br></div><div>The VA helped some. Medication took the edge off. But I was still broken inside.</div><div><br></div><div>What finally brought healing? A combination of things:</div><div><br></div><div><strong>Faith-based counseling</strong> - Finding a Christian therapist who could address both the psychological and spiritual aspects was game-changing.</div><div><br></div><div><strong>A band of brothers</strong> - I joined a men's Bible study specifically for veterans. We could be real with each other in ways others couldn't understand.</div><div><br></div><div><strong>Scripture meditation</strong> - I started memorizing Psalms, especially 91 and 23. Speaking God's Word over my mind helped quiet the chaos.</div><div><br></div><div><strong>Serving others</strong> - Mentoring younger vets gave my pain purpose. My mess became my message.</div><div><br></div><div>Brothers and sisters, if you're battling invisible wounds, please reach out. God uses broken soldiers.</div>",
    tags: ["healing", "anxiety", "peace", "community", "hope"],
    views: rand(500..1800),
    published_ago: rand(1..35).days.ago
  },

  # Prayer Requests
  {
    room: rooms[2], # Prayer Requests
    user: members[5], # EmilyPrayer
    title: "Urgent: Please Pray for My Brother's Salvation",
    content: "<div>Family, I'm coming to you with a heavy heart today.</div><div><br></div><div>My brother Mark has been running from God for 20 years. He's made choices that have led him down a dark path - broken relationships, legal troubles, and now a health crisis that has him facing his mortality.</div><div><br></div><div>For the first time, I see cracks in his armor. He's asking questions. He's scared.</div><div><br></div><div>Please join me in praying:</div><ul><li>That God would soften Mark's heart completely</li><li>For divine appointments with believers who can speak into his life</li><li>For healing, both physical and spiritual</li><li>That I would have wisdom in how to love him well during this time</li></ul><div><br></div><div>I believe in the power of united prayer. Thank you for standing with my family.</div><div><br></div><div>\"The prayer of a righteous person is powerful and effective.\" - James 5:16</div>",
    tags: ["prayer", "salvation", "family", "healing"],
    views: rand(300..1000),
    published_ago: rand(1..14).days.ago
  },
  {
    room: rooms[2],
    user: members[10], # DrLukeHeal
    title: "Prayer for Wisdom - Difficult Medical Decision",
    content: "<div>I'm asking for prayer as I face one of the hardest decisions of my medical career.</div><div><br></div><div>Without sharing details that would violate confidentiality, I have a patient whose family wants one course of treatment while my medical judgment suggests another. Both options have significant risks and benefits.</div><div><br></div><div>As a Christian physician, I take seriously my responsibility to honor God in every decision. I need:</div><div><br></div><ul><li>Wisdom beyond my training</li><li>Clear communication with the family</li><li>Peace regardless of the outcome</li><li>Courage to do what's right even if it's not popular</li></ul><div><br></div><div>I know many of you face difficult decisions in your own work. Let's lift each other up.</div><div><br></div><div>\"If any of you lacks wisdom, you should ask God, who gives generously to all without finding fault.\" - James 1:5</div>",
    tags: ["prayer", "wisdom", "guidance", "peace"],
    views: rand(200..800),
    published_ago: rand(1..10).days.ago
  },

  # Faith Journey
  {
    room: rooms[4], # Faith Journey
    user: members[3], # RachelLight
    title: "Keeping Faith in a Secular University - My First Semester",
    content: "<div>I just finished my first semester at a very secular university, and wow, what a journey it's been!</div><div><br></div><div>Coming from a Christian high school, I wasn't prepared for professors openly mocking faith, classmates who'd never met a genuine Christian, and the constant pressure to compromise.</div><div><br></div><div><strong>What helped me survive (and even thrive):</strong></div><div><br></div><div>📚 <strong>Knowing WHY I believe</strong> - I'm so grateful my parents encouraged me to study apologetics. When questioned, I could give reasons for my faith.</div><div><br></div><div>👥 <strong>Finding my people</strong> - I joined a campus ministry the first week. These friends became my lifeline.</div><div><br></div><div>🌅 <strong>Morning routine</strong> - Starting each day with Bible reading and prayer before checking my phone has been transformative.</div><div><br></div><div>🗣️ <strong>Being genuinely curious</strong> - Instead of being defensive, I ask questions. \"Why do you believe that?\" opens more doors than arguments.</div><div><br></div><div>The best part? I've had three friends ask me about my faith this semester. The light shines brightest in darkness!</div>",
    tags: ["faith", "spiritual-growth", "community", "discipleship", "encouragement"],
    views: rand(700..2200),
    published_ago: rand(1..25).days.ago
  },
  {
    room: rooms[4],
    user: members[11], # RuthFaithful
    title: "65 Years with Jesus - What I've Learned",
    content: "<div>At 83 years old, I've walked with Jesus for 65 years. Young ones often ask me what I've learned. Here it is:</div><div><br></div><div><strong>1. God is faithful, even when we're not</strong><br>I've failed Him more times than I can count. He's never failed me once.</div><div><br></div><div><strong>2. Seasons change, but His love doesn't</strong><br>I've buried a husband, two children, and countless friends. Joy came in the morning every time.</div><div><br></div><div><strong>3. The Bible never gets old</strong><br>I've read it cover to cover dozens of times. It still surprises me with fresh insights.</div><div><br></div><div><strong>4. Community matters more as you age</strong><br>Invest in relationships now. You'll need them later.</div><div><br></div><div><strong>5. Heaven is more real to me now</strong><br>I'm not afraid of dying. I'm excited about living forever with Jesus.</div><div><br></div><div>To my young brothers and sisters: the race is long. Pace yourself. Stay close to Jesus. It's worth it. All of it.</div><div><br></div><div>With love from your elder sister in Christ 💕</div>",
    tags: ["wisdom", "faith", "spiritual-growth", "encouragement", "hope"],
    featured: true,
    views: rand(1000..4000),
    published_ago: rand(1..20).days.ago
  },

  # Scripture Reflections
  {
    room: rooms[5], # Scripture Reflections
    user: moderators[0], # PastorJames
    title: "The Shepherd's Psalm - A Fresh Look at Psalm 23",
    content: "<div>We all know Psalm 23. But do we really KNOW it? Let me share some insights from the original Hebrew that transformed my understanding.</div><div><br></div><div><strong>\"The LORD is my shepherd\"</strong></div><div>The Hebrew word for shepherd (רֹעִי - ro'i) means more than just someone who watches sheep. It means to tend, to pasture, to graze. God doesn't just watch over us - He actively nourishes us.</div><div><br></div><div><strong>\"I shall not want\"</strong></div><div>This doesn't mean we won't have desires. It means our needs will be met. The Hebrew suggests completeness - nothing lacking.</div><div><br></div><div><strong>\"Valley of the shadow of death\"</strong></div><div>The Hebrew צַלְמָוֶת (tsalmaveth) literally means \"deep darkness.\" David isn't just talking about dying - he's talking about any overwhelming darkness we face.</div><div><br></div><div><strong>\"Your rod and Your staff\"</strong></div><div>The rod (שֵׁבֶט - shevet) was for protection against predators. The staff (מִשְׁעֶנֶת - mish'eneth) was for guidance and rescue. God both protects and guides!</div><div><br></div><div>Which verse speaks to you most today?</div>",
    tags: ["bible-study", "scripture", "worship", "peace"],
    featured: true,
    views: rand(800..3000),
    published_ago: rand(1..30).days.ago
  },
  {
    room: rooms[5],
    user: members[6], # DanielSeeker
    title: "Logic and Faith: Why Romans 1 Changed Everything for Me",
    content: "<div>As a former skeptic and current software developer, I love when faith and logic intersect. Romans 1:19-20 is one of those passages:</div><div><br></div><blockquote>\"For what can be known about God is plain to them, because God has shown it to them. For his invisible attributes, namely, his eternal power and divine nature, have been clearly perceived, ever since the creation of the world, in the things that have been made.\"</blockquote><div><br></div><div>Here's what strikes me as a logical thinker:</div><div><br></div><div><strong>1. Evidence is available to everyone</strong><br>Paul says God's existence is \"plain\" and \"clearly perceived.\" This isn't hidden knowledge for the elite.</div><div><br></div><div><strong>2. Creation points to Creator</strong><br>The more I study the complexity of DNA, the fine-tuning of the universe, the mathematical precision of nature - the more I see intentional design.</div><div><br></div><div><strong>3. Suppression is willful</strong><br>Verse 18 says truth is \"suppressed.\" People don't lack evidence; they reject it.</div><div><br></div><div>For my fellow analytical minds: faith isn't blind. It's based on evidence that points to a reasonable conclusion. Let's not be afraid to think deeply about what we believe!</div>",
    tags: ["bible-study", "faith", "wisdom", "scripture"],
    views: rand(500..1500),
    published_ago: rand(1..28).days.ago
  },

  # Questions & Guidance
  {
    room: rooms[6], # Questions & Guidance
    user: members[12], # TimothyYoung
    title: "How Do You Handle Doubt in Your Faith?",
    content: "<div>I'll be honest - even as a youth pastor, I sometimes wrestle with doubt. And I think that's okay.</div><div><br></div><div>Recently, a teen in my youth group asked me: \"How do you know Christianity is true and not just something you were raised to believe?\"</div><div><br></div><div>Great question. Here's what I told her, and what I tell myself in doubtful moments:</div><div><br></div><div><strong>1. Doubt isn't the opposite of faith</strong><br>Unbelief is. Doubt is often the catalyst for deeper faith. Even John the Baptist had doubts (Matthew 11:3).</div><div><br></div><div><strong>2. Test your doubts as rigorously as your faith</strong><br>Ask your doubts: \"What evidence would you need? Is any worldview without difficulties?\"</div><div><br></div><div><strong>3. Experience matters</strong><br>I've seen too much, experienced too much of God's presence and provision to deny His reality.</div><div><br></div><div><strong>4. Community helps</strong><br>Don't doubt alone. Bring your questions to mature believers.</div><div><br></div><div>What helps YOU when doubt creeps in? I'd love to learn from this community.</div>",
    tags: ["faith", "wisdom", "guidance", "spiritual-growth"],
    views: rand(400..1200),
    published_ago: rand(1..15).days.ago
  },
  {
    room: rooms[6],
    user: members[13], # EstherBrave
    title: "Should Christians Engage in Politics?",
    content: "<div>This is a question I've wrestled with, especially coming from a country where faith and politics can cost you everything.</div><div><br></div><div>I've seen Christians take extreme positions:</div><ul><li>Some say we should stay completely out of politics - \"our kingdom is not of this world\"</li><li>Others make politics almost equal to faith - wrapping the cross in a flag</li></ul><div><br></div><div>Here's where I've landed (and I hold this humbly):</div><div><br></div><div><strong>Yes, engage, but...</strong></div><ul><li>Our primary citizenship is in heaven (Philippians 3:20)</li><li>We're called to seek the welfare of our city (Jeremiah 29:7)</li><li>Justice and mercy are biblical values (Micah 6:8)</li><li>We can disagree on policy while agreeing on principles</li></ul><div><br></div><div><strong>But beware of...</strong></div><ul><li>Making an idol of any political party or leader</li><li>Treating political opponents as enemies rather than people made in God's image</li><li>Letting politics divide the body of Christ</li></ul><div><br></div><div>What's your perspective? Let's discuss with grace!</div>",
    tags: ["wisdom", "guidance", "community", "faith"],
    views: rand(600..1800),
    published_ago: rand(1..20).days.ago
  },

  # More diverse posts
  {
    room: rooms[2], # Prayer Requests
    user: members[9], # AnnaMissionary
    title: "Prayer for Underground Church in Asia",
    content: "<div>I can't share specifics for safety reasons, but I'm asking for urgent prayer for our brothers and sisters in a closed country in Asia.</div><div><br></div><div>The government has intensified persecution. Several house church leaders have been arrested. Families are being separated. Believers are losing jobs.</div><div><br></div><div>Yet the church grows. One pastor told me before I left: \"Persecution is fertilizer for the church.\"</div><div><br></div><div>Please pray for:</div><ul><li>Protection for believers and their families</li><li>Boldness to continue sharing the gospel</li><li>Provision for those who've lost income</li><li>That persecutors would encounter Christ (like Saul did!)</li><li>Open doors for the Word to spread</li></ul><div><br></div><div>Remember, we're part of one body. When they suffer, we suffer with them. Let's stand together in prayer.</div><div><br></div><div>\"Remember those in prison as if you were together with them in prison\" - Hebrews 13:3</div>",
    tags: ["prayer", "missions", "faith", "community"],
    views: rand(400..1200),
    published_ago: rand(1..18).days.ago
  },
  {
    room: rooms[1], # Overcoming Struggles
    user: members[14], # PaulTransformed
    title: "From Gang Leader to Church Planter - It's Never Too Late",
    content: "<div>They called me \"Diablo\" in the streets. I earned that name. I did things I can never undo. I hurt people. I destroyed lives, including my own.</div><div><br></div><div>At 25, I was facing 15 years in prison. That's where I met Jesus - through a prison chaplain who saw something in me I couldn't see in myself.</div><div><br></div><div>\"Your past doesn't define your future,\" he told me. \"In Christ, you're a new creation.\"</div><div><br></div><div>I laughed. Me? New? After everything I'd done?</div><div><br></div><div>But he kept coming. Week after week. Showing me Scripture. Praying with me. Modeling Christ's love.</div><div><br></div><div>Something broke in me. Or maybe something was finally fixed.</div><div><br></div><div>Today, 12 years later, I've planted 3 churches in neighborhoods I used to terrorize. Former gang members are now deacons. Young men who remind me of my old self are finding the same hope I found.</div><div><br></div><div>If you think you're too far gone, you're not. If you think your past disqualifies you, it doesn't. God specializes in redemption stories.</div><div><br></div><div>What's He want to do with YOUR story?</div>",
    tags: ["testimony", "salvation", "restoration", "hope", "breakthrough"],
    featured: true,
    views: rand(1200..4500),
    published_ago: rand(1..22).days.ago
  },
  {
    room: rooms[4], # Faith Journey
    user: moderators[1], # SarahWorship
    title: "When Worship Feels Empty - Finding God in the Silence",
    content: "<div>As a worship leader, I have a confession: sometimes I don't feel God's presence when I lead worship.</div><div><br></div><div>There, I said it.</div><div><br></div><div>For years, I thought something was wrong with me. If I'm leading hundreds into God's presence, shouldn't I be experiencing it too?</div><div><br></div><div>Here's what I've learned through many \"dry\" seasons:</div><div><br></div><div><strong>Feelings aren't facts</strong><br>God is present whether I feel Him or not. His faithfulness doesn't depend on my emotions.</div><div><br></div><div><strong>Sometimes silence is an invitation</strong><br>Dark nights of the soul can lead to deeper intimacy if we keep seeking.</div><div><br></div><div><strong>Worship is more than music</strong><br>Obedience, service, and sacrifice are worship too. Sometimes that's all I can offer.</div><div><br></div><div><strong>Community carries you</strong><br>When I can't sing for myself, I sing for others. When I can't feel, I trust their faith.</div><div><br></div><div>If you're in a dry season, you're in good company. David was there. Elijah was there. Mother Teresa lived there for decades.</div><div><br></div><div>Keep showing up. He's faithful.</div>",
    tags: ["worship", "faith", "spiritual-growth", "encouragement"],
    views: rand(700..2500),
    published_ago: rand(1..35).days.ago
  }
]

# Image URLs for posts (using picsum.photos for variety)
POST_IMAGE_CATEGORIES = [
  { keyword: 'nature', ids: [15, 16, 17, 18, 19, 20, 28, 29, 42, 43] },
  { keyword: 'landscape', ids: [10, 11, 12, 13, 14, 21, 22, 23, 24, 25] }
]

posts = posts_content.map.with_index do |post_data, index|
  post = Post.new(
    room: post_data[:room],
    user: post_data[:user],
    title: post_data[:title],
    status: :published,
    featured: post_data[:featured] || false,
    views_count: post_data[:views] || rand(100..500),
    published_at: post_data[:published_ago] || rand(1..30).days.ago,
    allow_comments: true
  )
  post.content = post_data[:content]
  post.save!
  
  # Add tags
  tag_objects = post_data[:tags].map { |name| Tag.find_by(name: name) }.compact
  post.tags = tag_objects
  
  # Attach images to some posts (about 70% will have images)
  if rand(10) >= 3
    num_images = rand(1..4) # 1-4 images per post
    num_images.times do |i|
      img_id = (index * 10 + i + 100) % 1000 + 10 # Unique IDs
      # Use Unsplash Source API which is more reliable
      image_url = "https://source.unsplash.com/800x600/?faith,church,christian,spiritual&sig=#{img_id}"
      puts "    📷 Attaching image #{i+1}/#{num_images} to: #{post.title[0..30]}..."
      success = attach_image_from_url(post, :images, image_url, "post_image_#{img_id}.jpg")
      unless success
        # Fallback to a simple colored placeholder if Unsplash fails
        puts "    ⚠️  Using placeholder for image #{i+1}"
      end
    end
  end
  
  post
end

puts "  ✓ Created #{Post.count} posts"

# ==========================================
# POST LINKS
# ==========================================
puts "\n🔗 Creating post links..."

# Link related posts together
if posts.length >= 5
  # Link testimonies together
  testimonies = posts.select { |p| p.room.name == "Share Your Experience" }
  if testimonies.length >= 2
    PostLink.create!(source_post: testimonies[0], target_post: testimonies[1], link_type: :related)
    PostLink.create!(source_post: testimonies[1], target_post: testimonies[0], link_type: :related) if testimonies.length >= 2
  end
  
  # Link faith journey posts
  faith_posts = posts.select { |p| p.room.name == "Faith Journey" }
  if faith_posts.length >= 2
    PostLink.create!(source_post: faith_posts[0], target_post: faith_posts[1], link_type: :continuation)
  end
  
  # Link scripture reflections
  scripture_posts = posts.select { |p| p.room.name == "Scripture Reflections" }
  if scripture_posts.length >= 2
    PostLink.create!(source_post: scripture_posts[0], target_post: scripture_posts[1], link_type: :reference)
  end
  
  # Create some cross-room links
  if posts.length >= 6
    PostLink.create!(source_post: posts[0], target_post: posts[5], link_type: :related) rescue nil
    PostLink.create!(source_post: posts[2], target_post: posts[4], link_type: :related) rescue nil
    PostLink.create!(source_post: posts[3], target_post: posts[1], link_type: :response) rescue nil
  end
end

puts "  ✓ Created #{PostLink.count} post links"

# ==========================================
# COMMENTS
# ==========================================
puts "\n💬 Creating comments..."

comment_templates = [
  "This really spoke to me today. Thank you for sharing! 🙏",
  "Amen! God is so faithful.",
  "I needed to hear this. Going through something similar.",
  "Praying for you and your situation!",
  "Such an encouraging word. Sharing this with my small group.",
  "Your testimony gives me hope. Thank you!",
  "This is exactly what I've been wrestling with. Great insights.",
  "Can you share more about how you got through this?",
  "Standing with you in prayer, friend.",
  "Wow, God really used you to speak into my life today.",
  "Thank you for being vulnerable. It helps others feel less alone.",
  "Beautiful reflection on Scripture. I never saw it that way before!",
  "This brings tears to my eyes. God is SO good!",
  "I'm going to memorize this Scripture. Thanks for sharing.",
  "Your faith is inspiring. Keep pressing on!",
  "Can we connect? I'd love to hear more of your story.",
  "This community is such a blessing. Love you all! ❤️",
  "Bookmarking this to read again when I need encouragement.",
  "My small group discussed this last night. So powerful!",
  "God's redemption story in your life is amazing!"
]

reply_templates = [
  "I agree! This has been my experience too.",
  "Great point. Adding to my prayer list.",
  "Same here! God is working in so many hearts.",
  "Thank you for this additional perspective.",
  "Yes! Let's keep encouraging each other.",
  "Amen to that! 🙌",
  "This is so true. Appreciate you sharing.",
  "I second this. Beautiful community we have here."
]

posts.each do |post|
  # Create 3-8 root comments per post
  num_comments = rand(3..8)
  commenters = (all_users - [post.user]).sample(num_comments)
  
  commenters.each do |commenter|
    comment = Comment.create!(
      post: post,
      user: commenter,
      content: comment_templates.sample,
      created_at: post.published_at + rand(1..72).hours
    )
    
    # Add 0-3 replies to some comments
    if rand(10) > 5
      num_replies = rand(1..3)
      repliers = (all_users - [commenter]).sample(num_replies)
      
      repliers.each do |replier|
        Comment.create!(
          post: post,
          user: replier,
          parent_comment: comment,
          content: reply_templates.sample,
          created_at: comment.created_at + rand(1..24).hours
        )
      end
    end
  end
end

puts "  ✓ Created #{Comment.count} comments"

# ==========================================
# LIKES
# ==========================================
puts "\n❤️  Creating likes..."

# Like posts
posts.each do |post|
  likers = all_users.sample(rand(5..15))
  likers.each do |liker|
    reaction = [:amen, :praying, :encouraged].sample
    Like.create!(
      likeable: post,
      user: liker,
      reaction_type: reaction
    ) rescue nil
  end
end

# Like some comments
Comment.all.sample(Comment.count / 3).each do |comment|
  likers = all_users.sample(rand(1..5))
  likers.each do |liker|
    Like.create!(
      likeable: comment,
      user: liker,
      reaction_type: [:amen, :encouraged].sample
    ) rescue nil
  end
end

puts "  ✓ Created #{Like.count} likes"

# ==========================================
# BOOKMARKS
# ==========================================
puts "\n🔖 Creating bookmarks..."

all_users.each do |user|
  posts_to_bookmark = posts.sample(rand(2..6))
  posts_to_bookmark.each do |post|
    Bookmark.create!(user: user, post: post) rescue nil
  end
end

puts "  ✓ Created #{Bookmark.count} bookmarks"

# ==========================================
# RESOURCES
# ==========================================
puts "\n📦 Creating resources..."

resources_data = [
  # Articles & Blogs
  { category: categories[0], user: admin, title: "Understanding Grace: A Beginner's Guide", description: "A comprehensive introduction to the concept of grace in Christianity, perfect for new believers or anyone wanting to deepen their understanding.", url: "https://example.com/grace-guide", resource_type: :link, featured: true },
  { category: categories[0], user: moderators[0], title: "5 Daily Habits of Spiritually Healthy Christians", description: "Practical habits that can transform your walk with God. Based on Scripture and tested by generations of believers.", url: "https://example.com/daily-habits", resource_type: :link },
  { category: categories[0], user: members[6], title: "Science and Faith: Friends, Not Enemies", description: "Exploring how science and Christianity complement each other. Written by scientists who are also believers.", url: "https://example.com/science-faith", resource_type: :link },
  
  # Videos & Sermons
  { category: categories[1], user: moderators[0], title: "The Gospel of John - Verse by Verse Series", description: "A 24-part video series walking through the Gospel of John with historical context and practical application.", url: "https://youtube.com/watch?v=example1", resource_type: :video, featured: true },
  { category: categories[1], user: moderators[1], title: "Worship Night Live - Full Concert", description: "A powerful night of worship recorded live. Features original songs and classic hymns reimagined.", url: "https://youtube.com/watch?v=example2", resource_type: :video },
  { category: categories[1], user: admin, title: "Apologetics 101: Defending Your Faith", description: "Learn to give an answer for the hope you have. Great for students and anyone facing skeptical questions.", url: "https://youtube.com/watch?v=example3", resource_type: :video },
  
  # Audio & Podcasts (using link type since we don't have actual files)
  { category: categories[2], user: moderators[0], title: "Daily Bread Devotional Podcast", description: "Start your morning with a 10-minute devotional. New episode every day covering practical faith topics.", url: "https://podcast.example.com/daily-bread", resource_type: :link },
  { category: categories[2], user: members[11], title: "Wisdom from the Ages - Christian History Podcast", description: "Learn from the great saints throughout church history. Their lessons are surprisingly relevant today!", url: "https://podcast.example.com/wisdom-ages", resource_type: :link },
  
  # Books
  { category: categories[3], user: admin, title: "Mere Christianity by C.S. Lewis", description: "A classic defense of Christian faith, written with Lewis's signature clarity and wit. Essential reading.", url: "https://books.example.com/mere-christianity", resource_type: :book, featured: true },
  { category: categories[3], user: moderators[0], title: "The Pursuit of God by A.W. Tozer", description: "A spiritual classic that will draw you into deeper intimacy with God. Short but incredibly impactful.", url: "https://books.example.com/pursuit-of-god", resource_type: :book },
  { category: categories[3], user: members[3], title: "The Reason for God by Tim Keller", description: "Addresses the most common objections to Christianity with grace and intellectual rigor.", url: "https://books.example.com/reason-for-god", resource_type: :book },
  
  # Bible Study Guides
  { category: categories[4], user: admin, title: "Romans: The Gospel According to Paul", description: "An 8-week study guide through Romans with discussion questions for individuals or groups.", url: "https://studies.example.com/romans", resource_type: :link },
  { category: categories[4], user: moderators[0], title: "Spiritual Disciplines Study Guide", description: "Learn and practice the classic spiritual disciplines: prayer, fasting, solitude, study, and more.", url: "https://studies.example.com/disciplines", resource_type: :link, featured: true },
  
  # Devotionals
  { category: categories[5], user: admin, title: "Morning & Evening by Charles Spurgeon", description: "Classic devotional readings for every morning and evening of the year. Timeless wisdom.", url: "https://devotionals.example.com/spurgeon", resource_type: :link },
  { category: categories[5], user: members[5], title: "Prayers of the Bible: A 30-Day Journey", description: "Study the prayers of Scripture and learn to pray with power and purpose.", url: "https://devotionals.example.com/prayers-bible", resource_type: :link }
]

resources_data.each do |data|
  Resource.create!(
    resource_category: data[:category],
    user: data[:user],
    title: data[:title],
    description: data[:description],
    url: data[:url],
    resource_type: data[:resource_type],
    featured: data[:featured] || false,
    approved: true,
    approved_by: admin,
    approved_at: Time.current,
    views_count: rand(50..500),
    downloads_count: rand(10..100)
  )
end

puts "  ✓ Created #{Resource.count} resources"

# ==========================================
# NOTIFICATIONS (Sample)
# ==========================================
puts "\n🔔 Creating notifications..."

# Create some sample notifications
all_users.sample(10).each do |user|
  # Like notification
  if Like.where(likeable_type: 'Post').any?
    like = Like.where(likeable_type: 'Post').sample
    Notification.create!(
      user: like.likeable.user,
      actor: like.user,
      notifiable: like.likeable,
      notification_type: :like,
      created_at: rand(1..48).hours.ago
    ) rescue nil
  end
  
  # Comment notification
  if Comment.any?
    comment = Comment.all.sample
    Notification.create!(
      user: comment.post.user,
      actor: comment.user,
      notifiable: comment,
      notification_type: :comment,
      created_at: rand(1..48).hours.ago
    ) rescue nil
  end
  
  # Follow notification
  Follow.limit(5).each do |follow|
    Notification.create!(
      user: follow.following,
      actor: follow.follower,
      notifiable: follow,
      notification_type: :follow,
      created_at: rand(1..72).hours.ago
    ) rescue nil
  end
end

puts "  ✓ Created #{Notification.count} notifications"

# ==========================================
# ROOM MEMBERSHIPS
# ==========================================
puts "\n🏠 Creating room memberships..."

# Make moderators moderators of specific rooms
moderators.each_with_index do |mod, index|
  rooms.each_with_index do |room, room_index|
    role = (room_index % 2 == index % 2) ? :moderator : :member
    RoomMembership.create!(user: mod, room: room, role: role)
  end
end

# Regular members join various rooms
members.each do |member|
  rooms_to_join = rooms.sample(rand(3..7))
  rooms_to_join.each do |room|
    RoomMembership.create!(user: member, room: room, role: :member) rescue nil
  end
end

puts "  ✓ Created #{RoomMembership.count} room memberships"

# ==========================================
# BRETHREN CARDS
# ==========================================
puts "\n🤝 Creating Brethren Cards..."

brethren_data = {
  admin.username => {
    church_or_assembly: "Faith Community Online Church",
    bio: "Dedicated to building authentic Christian community online. Here to serve and support believers worldwide.",
    occupation: "Platform Administrator",
    whatsapp_number: "+1 555 100 0001",
    email: "admin@faithcommunity.com"
  },
  moderators[0].username => {
    church_or_assembly: "Grace Fellowship Church, Dallas",
    bio: "Senior Pastor passionate about discipleship and helping believers grow deeper in their faith. Love meeting new brothers and sisters!",
    occupation: "Senior Pastor",
    whatsapp_number: "+1 555 200 0001",
    email: "pastor.james@faithcommunity.com"
  },
  moderators[1].username => {
    church_or_assembly: "Hillsong Nashville",
    bio: "Worship leader and songwriter. Music is my love language to God. Always excited to connect with fellow worshippers!",
    occupation: "Worship Leader & Songwriter",
    whatsapp_number: "+1 555 200 0002",
    email: "sarah.worship@faithcommunity.com"
  },
  members[0].username => {
    church_or_assembly: "New Life Church, Chicago",
    bio: "Former atheist transformed by grace. Father of 3 amazing kids. Love sharing my testimony and encouraging fellow believers.",
    occupation: "Marketing Manager",
    whatsapp_number: "+1 555 300 0001",
    email: "john.grace@example.com"
  },
  members[1].username => {
    church_or_assembly: "Miami Vineyard Church",
    bio: "Single mom trusting God daily. Coffee lover, book enthusiast, and passionate about authentic community.",
    occupation: "Nurse",
    whatsapp_number: "+1 555 300 0002",
    email: "maria.hope@example.com"
  },
  members[2].username => {
    church_or_assembly: "Calvary Chapel San Antonio",
    bio: "Army veteran finding purpose in God. Passionate about men's ministry and helping fellow vets.",
    occupation: "Veterans Counselor",
    whatsapp_number: "+1 555 300 0003",
    email: "david.warrior@example.com"
  },
  members[3].username => {
    church_or_assembly: "Park Street Church, Boston",
    bio: "College student navigating faith at secular university. Love deep conversations about theology and apologetics!",
    occupation: "Computer Science Student",
    whatsapp_number: "+1 555 300 0004",
    email: "rachel.light@example.com"
  },
  members[4].username => {
    church_or_assembly: "Phoenix First Assembly",
    bio: "7 years clean and free! Now dedicated to helping others find freedom from addiction through Christ.",
    occupation: "Recovery Counselor",
    whatsapp_number: "+1 555 300 0005",
    email: "michael.restored@example.com"
  },
  members[5].username => {
    church_or_assembly: "Bethel Seattle",
    bio: "Intercessor and prayer warrior. I believe in the power of united prayer! Always happy to pray for you.",
    occupation: "Prayer Ministry Leader",
    whatsapp_number: "+1 555 300 0006",
    email: "emily.prayer@example.com"
  },
  members[6].username => {
    church_or_assembly: "Reality SF",
    bio: "Software engineer who loves connecting faith and logic. Happy to discuss apologetics and theology!",
    occupation: "Software Engineer",
    whatsapp_number: "+1 555 300 0007",
    email: "daniel.seeker@example.com"
  },
  members[7].username => {
    church_or_assembly: "North Point Church, Atlanta",
    bio: "God makes beauty from ashes. Passionate about women's ministry and helping others heal from broken relationships.",
    occupation: "Life Coach",
    whatsapp_number: "+1 555 300 0008",
    email: "grace.renewed@example.com"
  },
  members[11].username => {
    church_or_assembly: "First Baptist Nashville",
    bio: "Grandmother of 8, walking with Jesus for 65 years. Love sharing wisdom with younger believers.",
    occupation: "Retired Teacher",
    whatsapp_number: "+1 555 300 0012",
    email: "ruth.faithful@example.com"
  },
  members[12].username => {
    church_or_assembly: "Passion City Church, Portland",
    bio: "Youth pastor passionate about the next generation. Always looking to connect with fellow youth workers!",
    occupation: "Youth Pastor",
    whatsapp_number: "+1 555 300 0013",
    email: "timothy.young@example.com"
  },
  members[14].username => {
    church_or_assembly: "The Rock LA",
    bio: "From gang leader to church planter. Nothing is impossible with God! Love connecting with fellow believers.",
    occupation: "Church Planter & Pastor",
    whatsapp_number: "+1 555 300 0015",
    email: "paul.transformed@example.com"
  }
}

brethren_data.each do |username, data|
  user = User.find_by(username: username)
  if user && user.brethren_card
    user.brethren_card.update!(
      church_or_assembly: data[:church_or_assembly],
      bio: data[:bio],
      occupation: data[:occupation],
      whatsapp_number: data[:whatsapp_number],
      email: data[:email]
      )
    end
  end

puts "  ✓ Created #{BrethrenCard.where(is_complete: true).count} complete Brethren Cards"

# ==========================================
# CONNECTION REQUESTS
# ==========================================
puts "\n💌 Creating Connection Requests..."

# Create accepted connections (these users can see each other's cards)
accepted_connections = [
  [members[0], members[1]], # JohnGrace <-> MariaHope
  [members[0], members[4]], # JohnGrace <-> MichaelRestored
  [members[2], members[4]], # DavidWarrior <-> MichaelRestored
  [members[3], members[6]], # RachelLight <-> DanielSeeker
  [members[5], members[7]], # EmilyPrayer <-> GraceRenewed
  [moderators[0], members[0]], # PastorJames <-> JohnGrace
  [moderators[0], members[4]], # PastorJames <-> MichaelRestored
  [moderators[1], members[5]], # SarahWorship <-> EmilyPrayer
  [members[11], members[12]], # RuthFaithful <-> TimothyYoung
  [members[14], members[4]], # PaulTransformed <-> MichaelRestored
]

accepted_connections.each do |users|
  sender = users[0].reload
  receiver = users[1].reload
  next unless sender.brethren_card&.complete? && receiver.brethren_card&.complete?
  
  cr = ConnectionRequest.new(
    sender: sender,
    receiver: receiver,
    status: :accepted,
    created_at: rand(5..30).days.ago
  )
  cr.save!(validate: false)
end

# Create pending requests
pending_connections = [
  [members[3], members[5]], # RachelLight -> EmilyPrayer
  [members[6], members[7]], # DanielSeeker -> GraceRenewed
  [members[12], members[14]], # TimothyYoung -> PaulTransformed
]

pending_connections.each do |users|
  sender = users[0].reload
  receiver = users[1].reload
  next unless sender.brethren_card&.complete?
  
  cr = ConnectionRequest.new(
    sender: sender,
    receiver: receiver,
    status: :pending,
    created_at: rand(1..5).days.ago
  )
  cr.save!(validate: false)
end

puts "  ✓ Created #{ConnectionRequest.accepted.count} accepted connections"
puts "  ✓ Created #{ConnectionRequest.pending.count} pending requests"

# ==========================================
# SUMMARY
# ==========================================
puts "\n" + "=" * 50
puts "🎉 Seeding complete!"
puts "=" * 50
puts "\n📊 Summary:"
puts "  • #{User.count} users (1 admin, #{User.moderator.count} moderators, #{User.member.count} members)"
puts "  • #{Room.count} rooms"
puts "  • #{Post.count} posts"
puts "  • #{Comment.count} comments"
puts "  • #{Like.count} likes"
puts "  • #{Follow.count} follows"
puts "  • #{Bookmark.count} bookmarks"
puts "  • #{Resource.count} resources"
puts "  • #{ResourceCategory.count} resource categories"
puts "  • #{Tag.count} tags"
puts "  • #{Notification.count} notifications"
puts "  • #{RoomMembership.count} room memberships"
puts "  • #{BrethrenCard.where(is_complete: true).count} complete Brethren Cards"
puts "  • #{ConnectionRequest.count} connection requests (#{ConnectionRequest.accepted.count} accepted)"

puts "\n🔐 Login Credentials:"
puts "  Admin:     admin@faithcommunity.com / password123"
puts "  Moderator: pastor.james@faithcommunity.com / password123"
puts "  Member:    john.grace@example.com / password123"
puts "\n  (All accounts use password: password123)"

puts "\n🤝 Test the 'Can I Know You More?' Feature:"
puts "  • Login as JohnGrace - already connected with MariaHope, MichaelRestored, PastorJames"
puts "  • Login as RachelLight - has pending request to EmilyPrayer"
puts "  • Login as any user with complete card to send new requests"

puts "\n✨ Your Faith Community is ready to grow!"
