# Faith Community - Scalability Guide

## Current Architecture

The Faith Community platform is built to handle **hundreds of concurrent users** with the following optimizations:

---

## 🗄️ Database Optimizations

### Connection Pooling
```yaml
# config/database.yml
pool: 25  # Handles up to 25 concurrent database connections per process
timeout: 5000  # 5 second connection timeout
prepared_statements: true  # Faster repeated queries
```

### Indexes (Already Applied)
All critical queries are indexed:
- Users: `email`, `username`, `role`
- Posts: `slug`, `status`, `published_at`, `room_id`, `user_id`
- Comments: `post_id`, `parent_comment_id`, `created_at`
- Likes: `likeable_type + likeable_id + user_id` (unique)
- Follows: `follower_id + following_id` (unique)
- Notifications: `user_id`, `read_at`, `notification_type`

### Counter Caches
Avoid N+1 queries with counter caches:
- `posts.likes_count`
- `posts.comments_count`
- `posts.views_count`
- `rooms.posts_count`
- `comments.replies_count`

---

## ⚡ Performance Features

### Turbo Streams (Real-time without WebSockets)
- Reactions update instantly without page reload
- Comments appear in real-time
- Notifications update live
- Uses HTTP/2 for efficiency

### Fragment Caching
Enable in views for frequently accessed content:
```erb
<% cache post do %>
  <%= render post %>
<% end %>
```

### Russian Doll Caching
Nested caching for complex views:
```erb
<% cache room do %>
  <% room.posts.each do |post| %>
    <% cache post do %>
      <%= render post %>
    <% end %>
  <% end %>
<% end %>
```

---

## 🚀 Scaling Strategies

### Horizontal Scaling (Multiple Servers)

1. **Load Balancer Setup**
   - Use nginx or HAProxy
   - Sticky sessions for WebSocket connections
   - Health checks on `/up` endpoint

2. **Database Scaling**
   - Read replicas for read-heavy operations
   - Connection pooling with PgBouncer
   - Separate databases for cache/queue (already configured)

3. **Background Jobs (Solid Queue)**
   - Already configured for:
     - Email notifications
     - Heavy data processing
     - Scheduled tasks

### Vertical Scaling (Better Hardware)

For up to 500 concurrent users:
- **RAM**: 4GB minimum, 8GB recommended
- **CPU**: 2 cores minimum, 4 cores recommended
- **Database**: PostgreSQL with 2GB RAM minimum

---

## 📊 Monitoring Recommendations

### Application Monitoring
```ruby
# Gemfile (add for production)
gem 'rack-mini-profiler'  # Development profiling
gem 'memory_profiler'     # Memory analysis
```

### Key Metrics to Watch
- Response time (aim for < 200ms average)
- Database query count per request
- Memory usage
- Active database connections
- Background job queue depth

---

## 🔒 Rate Limiting (Recommended)

Add to protect against abuse:
```ruby
# Gemfile
gem 'rack-attack'

# config/initializers/rack_attack.rb
Rack::Attack.throttle('req/ip', limit: 300, period: 5.minutes) do |req|
  req.ip
end
```

---

## 📈 Capacity Estimates

| Users | Posts/Day | DB Connections | RAM | Response Time |
|-------|-----------|----------------|-----|---------------|
| 100   | 500       | 10-15          | 2GB | < 100ms       |
| 500   | 2,000     | 20-30          | 4GB | < 150ms       |
| 1,000 | 5,000     | 40-50          | 8GB | < 200ms       |
| 5,000 | 20,000    | 100+ (pooler)  | 16GB| < 300ms       |

---

## 🌐 CDN & Assets

### Static Assets
- Use `propshaft` for asset fingerprinting
- Enable gzip compression in nginx
- Consider CDN for images/attachments (Cloudflare, AWS CloudFront)

### Active Storage
For high traffic, configure cloud storage:
```yaml
# config/storage.yml
amazon:
  service: S3
  access_key_id: <%= ENV['AWS_ACCESS_KEY_ID'] %>
  secret_access_key: <%= ENV['AWS_SECRET_ACCESS_KEY'] %>
  region: us-east-1
  bucket: faith-community-production
```

---

## 🔄 Deployment Checklist

Before deploying for scale:

- [ ] Run `RAILS_ENV=production rails assets:precompile`
- [ ] Enable caching: `config.action_controller.perform_caching = true`
- [ ] Set `RAILS_SERVE_STATIC_FILES=true` or use nginx
- [ ] Configure Redis for session storage (if using multiple servers)
- [ ] Set up database backups
- [ ] Configure log rotation
- [ ] Set up error tracking (Sentry/Honeybadger)
- [ ] Enable HTTPS with SSL certificate
- [ ] Configure proper CORS headers

---

## Current Stack Can Handle

✅ **100-500 concurrent users** easily with current setup
✅ **Real-time reactions** via Turbo Streams
✅ **Efficient database queries** with proper indexing
✅ **Background job processing** for heavy tasks
✅ **Caching ready** for view fragments

For **1000+ concurrent users**, consider:
- Adding Redis for caching
- Database read replicas
- Load balancer with multiple app servers
- CDN for static assets

