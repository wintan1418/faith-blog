# Faith Community Blog Platform - Project Scope Document

## Project Overview
A faith-based community platform where brethren can share testimonies, struggles, victories, and resources through categorized rooms with threading capabilities and resource management.

## Technology Stack
- **Backend**: Ruby on Rails 8
- **Frontend**: Tailwind CSS
- **Database**: PostgreSQL
- **Authentication**: Devise (recommended)
- **File Storage**: Active Storage
- **Rich Text**: ActionText (for blog posts)

---

## Core Features & Modules

### 1. User Management System
**Models**: `User`, `Profile`

**Features**:
- User registration and authentication
- Email verification
- Profile management (bio, profile picture, faith background)
- User roles: Admin, Moderator, Member
- Privacy settings (public/private profile)

**Database Fields**:
- Users: email, password, username, role, verified_at
- Profiles: user_id, bio, avatar, location, joined_at

---

### 2. Room System (Categories)
**Models**: `Room`, `RoomMembership`

**Predefined Rooms**:
1. **Share Your Experience** - General testimonies
2. **Overcoming Struggles** - Victory stories
3. **Prayer Requests** - Community prayer support
4. **Past Struggles** - Healing and reflection
5. **Faith Journey** - Personal growth stories
6. **Scripture Reflections** - Biblical insights
7. **Questions & Guidance** - Seeking spiritual advice

**Features**:
- Room descriptions and guidelines
- Room moderators
- Optional room membership (public vs. members-only)
- Room-specific rules and tags

**Database Fields**:
- Rooms: name, description, slug, room_type, moderator_ids, is_public, rules

---

### 3. Blog Post System
**Models**: `Post`, `PostTag`, `Tag`

**Features**:
- Rich text editor for creating posts
- Assign posts to specific rooms
- Multiple tags per post
- Draft/Published status
- Featured posts (by admins)
- Post scheduling
- Edit history tracking
- Content moderation flags

**Database Fields**:
- Posts: user_id, room_id, title, content (ActionText), status, published_at, featured, views_count, slug
- Tags: name, slug, usage_count

---

### 4. Threading & Comments System
**Models**: `Comment`

**Features**:
- Nested comments (threaded discussions)
- Comment on posts and replies to comments
- Markdown support in comments
- Comment reactions (Amen, Praying, Encourage)
- Edit and delete own comments
- Report inappropriate comments
- Moderator comment management

**Database Fields**:
- Comments: user_id, post_id, parent_comment_id, content, edited_at, deleted_at, flagged

---

### 5. Resource Bank
**Models**: `Resource`, `ResourceCategory`

**Resource Types**:
- External links (blogs, articles)
- YouTube videos (embedded)
- PDF documents
- Audio files (sermons, podcasts)
- Book recommendations

**Features**:
- Categorized resources
- User submissions with admin approval
- Resource ratings and reviews
- Search and filter by category/type
- Favorite resources
- Download tracking

**Database Fields**:
- Resources: user_id, title, description, resource_type, url, file_attachment, category_id, approved, views_count, downloads_count
- ResourceCategories: name, description, icon

---

### 6. General Feed & Engagement
**Models**: `Like`, `Bookmark`, `Follow`

**Features**:
- Algorithm-based feed showing:
  - Most engaged posts (likes + comments)
  - Recent posts from followed users
  - Trending topics
  - Featured content
- Sort options: Recent, Popular, Trending
- Room-specific feeds
- Personal timeline
- Bookmarked posts collection

**Engagement Metrics**:
- Likes/Reactions
- Comments count
- Shares count
- Views count
- Engagement score calculation

**Database Fields**:
- Likes: user_id, likeable_type, likeable_id, reaction_type
- Bookmarks: user_id, post_id
- Follows: follower_id, following_id

---

### 7. Notification System
**Models**: `Notification`

**Notification Types**:
- New comment on your post
- Reply to your comment
- Someone followed you
- Post featured by admin
- New post in subscribed room
- Resource approved/rejected
- Mentioned in post/comment

**Database Fields**:
- Notifications: user_id, actor_id, notifiable_type, notifiable_id, notification_type, read_at, created_at

---

### 8. Search & Discovery
**Features**:
- Full-text search for posts
- Filter by room, tags, date range
- User search
- Resource search
- Trending tags
- Suggested users to follow

**Implementation**:
- PostgreSQL full-text search
- Or integrate pg_search gem

---

### 9. Moderation & Safety
**Models**: `Report`, `ModerationLog`

**Features**:
- Report posts/comments/users
- Admin moderation dashboard
- Content approval queue
- User warnings and suspensions
- Profanity filter
- Community guidelines page
- Appeal system

**Database Fields**:
- Reports: reporter_id, reportable_type, reportable_id, reason, status, reviewed_by, reviewed_at
- ModerationLogs: moderator_id, action, target_type, target_id, notes

---

## Database Schema Overview

### Core Tables
1. **users** - Authentication and basic info
2. **profiles** - Extended user information
3. **rooms** - Category/room definitions
4. **posts** - Blog posts and testimonies
5. **comments** - Threaded discussions
6. **resources** - Resource bank items
7. **tags** - Content tagging
8. **likes** - Polymorphic engagement
9. **bookmarks** - Saved content
10. **follows** - User relationships
11. **notifications** - User notifications
12. **reports** - Content moderation
13. **room_memberships** - User-room relationships

---

## User Roles & Permissions

### Member (Default)
- Create posts in all public rooms
- Comment and engage
- Submit resources (with approval)
- Bookmark and follow

### Moderator
- All member permissions
- Moderate assigned rooms
- Review reported content
- Feature posts in their rooms
- Ban users from rooms

### Admin
- All moderator permissions
- Manage all rooms
- Approve resources
- Feature posts globally
- User management
- System configuration

---

## UI/UX Pages

### Public Pages
1. Landing page with mission statement
2. About/Community Guidelines
3. Login/Register pages
4. Browse rooms (preview)

### Authenticated Pages
1. **Dashboard/Home Feed** - Personalized feed
2. **Room Pages** - Room-specific feeds
3. **Create Post** - Rich text editor
4. **Post Detail** - Single post with comments
5. **Profile Pages** - User profiles
6. **Resource Bank** - Browse/search resources
7. **Notifications Center**
8. **Settings** - Profile, privacy, notifications
9. **Bookmarks** - Saved posts
10. **Following** - People you follow

### Admin Pages
1. Admin dashboard
2. Moderation queue
3. User management
4. Room management
5. Resource approval
6. Analytics

---

## Key Rails 8 Features to Leverage

1. **Hotwire/Turbo**: Real-time updates for comments, likes, notifications
2. **Action Cable**: Live notifications and presence indicators
3. **Active Storage**: File uploads for resources and avatars
4. **Action Text**: Rich text editing for posts
5. **Active Record**: Complex associations and queries
6. **Action Mailer**: Email notifications and digests
7. **Rails Credentials**: Secure API keys and secrets

---

## Development Phases

### Phase 1: Foundation (Weeks 1-2)
- Setup Rails 8 app with Tailwind
- User authentication (Devise)
- Basic models and associations
- Room creation and management
- Basic UI layout

### Phase 2: Core Features (Weeks 3-5)
- Blog post creation (ActionText)
- Threading/comment system
- Room-specific posting
- Basic feed implementation
- Profile pages

### Phase 3: Engagement (Weeks 6-7)
- Likes and reactions
- Bookmarking
- Following system
- Notification system
- Search functionality

### Phase 4: Resource Bank (Week 8)
- Resource model and uploads
- Category system
- Approval workflow
- Resource display and filtering

### Phase 5: Moderation (Week 9)
- Reporting system
- Moderation dashboard
- User roles refinement
- Content guidelines enforcement

### Phase 6: Polish & Launch (Week 10-12)
- UI/UX refinements
- Performance optimization
- Testing (RSpec)
- Security audit
- Deployment setup
- Beta testing

---

## Technical Considerations

### Performance
- Database indexing on frequently queried fields
- Caching for feeds and popular content
- Pagination for lists
- Lazy loading images
- Background jobs for emails and heavy processing

### Security
- SQL injection prevention (Rails default)
- XSS protection (Rails default)
- CSRF tokens
- Content Security Policy
- Rate limiting
- Input sanitization
- Secure file uploads

### Scalability
- Database connection pooling
- Redis for caching and job queues
- CDN for static assets
- Background job processing (Sidekiq)

---

## Third-Party Integrations (Optional)

1. **Email**: SendGrid or Mailgun
2. **File Storage**: AWS S3 or Cloudinary
3. **Analytics**: Google Analytics
4. **Monitoring**: Sentry or Honeybadger
5. **Search**: Elasticsearch (if needed)

---

## Success Metrics

1. User registration and retention rates
2. Posts created per week
3. Engagement rate (comments/likes per post)
4. Active rooms
5. Resource downloads
6. User satisfaction surveys

---

## Future Enhancements

- Mobile app (React Native/Flutter)
- Private messaging
- Live prayer rooms (video/audio)
- Daily devotionals
- Bible verse integration
- Event management for church activities
- Donation/tithe integration
- Multi-language support

---

## Conclusion

This platform will create a safe, engaging space for brethren to share their faith journeys, support one another, and grow together spiritually. The room-based structure provides organization while threading enables deep, meaningful conversations.