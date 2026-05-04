# Faith Community Blog Platform

A faith-based community platform where brethren can share testimonies, struggles, victories, and resources through categorized rooms with threading capabilities and resource management.

## 🚀 Features

- **User Management**: Registration, authentication, profiles with avatars
- **Room System**: Categorized spaces for different topics (Prayer Requests, Testimonies, etc.)
- **Rich Text Posts**: Create posts with images, formatting, and tags
- **Engagement**: Like/react to posts, reshare, comment with threading
- **Social Features**: Follow users, bookmarks, notifications
- **Brethren Cards**: Share contact information via "Can I Know You More" feature
- **Resource Bank**: Share and discover resources (links, videos, documents)
- **Search**: Full-text search across posts, users, and resources
- **Admin Dashboard**: Manage users, rooms, posts, and resources
- **Real-time Updates**: Turbo Streams for instant reactions and comments

## 🛠️ Technology Stack

- **Backend**: Ruby on Rails 8.0
- **Frontend**: Tailwind CSS, Stimulus.js, Hotwire/Turbo
- **Database**: PostgreSQL
- **Authentication**: Devise
- **File Storage**: Active Storage
- **Rich Text**: ActionText (Trix editor)
- **Search**: pg_search
- **Background Jobs**: Solid Queue
- **Caching**: Solid Cache

## 📋 Prerequisites

- Ruby 3.3+ (check with `ruby -v`)
- PostgreSQL 12+ (check with `psql --version`)
- Node.js 18+ and Yarn (for JavaScript assets)
- Bundler gem (`gem install bundler`)

## 🚀 Getting Started

### 1. Clone the Repository

```bash
git clone <repository-url>
cd faith_blog
```

### 2. Install Dependencies

```bash
# Install Ruby gems
bundle install

# Install JavaScript packages
yarn install
```

### 3. Database Setup

```bash
# Create databases
rails db:create

# Run migrations
rails db:migrate

# Seed initial data (rooms, sample users, etc.)
rails db:seed
```

### 4. Configure Environment

The application uses Rails credentials for sensitive configuration. To edit:

```bash
EDITOR="code --wait" rails credentials:edit
```

Or use your preferred editor:

```bash
EDITOR="vim" rails credentials:edit
```

### 5. Start the Development Server

```bash
# Start Rails server and asset pipeline
bin/dev
```

Or separately:

```bash
# Terminal 1: Rails server
rails server

# Terminal 2: Asset pipeline (if needed)
./bin/dev
```

The application will be available at `http://localhost:3000`

## 👤 Default Login Credentials

After seeding, you can log in with:

- **Admin User**: See `LOGIN_CREDENTIALS.md` for details
- **Regular Users**: Check seed file or create new account

## 📁 Project Structure

```
faith_blog/
├── app/
│   ├── controllers/     # Application controllers
│   ├── models/          # ActiveRecord models
│   ├── views/           # ERB templates
│   ├── javascript/      # Stimulus controllers, JS
│   ├── assets/          # CSS, images
│   └── mailers/         # Email templates
├── config/              # Configuration files
├── db/                  # Migrations, seeds, schema
├── lib/                 # Custom libraries, rake tasks
└── test/                # Test files
```

## 🔧 Configuration

### Database

Edit `config/database.yml` for your database settings. Default uses PostgreSQL with connection pooling configured for scalability.

### Active Storage

File uploads are stored locally by default. For production, configure cloud storage (AWS S3, Cloudinary) in `config/storage.yml`.

### Email

Configure SMTP settings in `config/environments/production.rb`:

```ruby
config.action_mailer.smtp_settings = {
  address: 'smtp.example.com',
  port: 587,
  user_name: Rails.application.credentials.dig(:smtp, :user_name),
  password: Rails.application.credentials.dig(:smtp, :password),
  authentication: :plain
}
```

### Environment Variables

Set these in production:

- `RAILS_MASTER_KEY` - Master key for credentials
- `PRIMARY_DATABASE_URL` or `DATABASE_URL` - PostgreSQL connection URL provided by Hatchbox
- `CACHE_DATABASE_URL`, `QUEUE_DATABASE_URL`, `CABLE_DATABASE_URL` - Optional separate Rails 8 database URLs
- `SECRET_KEY_BASE` - Secret key (if not using credentials)
- SMTP credentials (via Rails credentials)

## 🧪 Testing

```bash
# Run all tests
rails test

# Run specific test file
rails test test/models/user_test.rb

# Run with coverage (if SimpleCov configured)
COVERAGE=true rails test
```

## 📦 Production Deployment

See `PRODUCTION_READINESS.md` for a comprehensive deployment checklist.

### Quick Production Setup

1. **Precompile assets**:
   ```bash
   RAILS_ENV=production rails assets:precompile
   ```

2. **Run migrations**:
   ```bash
   RAILS_ENV=production rails db:migrate
   ```

3. **Seed initial data** (if needed):
   ```bash
   RAILS_ENV=production rails db:seed
   ```

4. **Start background workers**:
   ```bash
   RAILS_ENV=production bin/rails solid_queue:start
   ```

5. **Start application server** (with process manager like systemd, PM2, etc.)

## 🔒 Security

- CSRF protection enabled
- SQL injection protection (ActiveRecord)
- XSS protection (Rails default)
- Force SSL in production
- Content Security Policy configured
- Rate limiting recommended (see `PRODUCTION_READINESS.md`)

## 📊 Performance

The application is optimized for 100-500 concurrent users:

- Database connection pooling (25 connections)
- Counter caches for engagement metrics
- Database indexes on critical queries
- Turbo Streams for real-time updates
- Fragment caching ready

See `SCALABILITY.md` for scaling strategies.

## 🐛 Troubleshooting

### Database Connection Issues

```bash
# Check PostgreSQL is running
sudo service postgresql status

# Create database user if needed
sudo -u postgres createuser -s your_username
```

### Asset Compilation Issues

```bash
# Clear asset cache
rm -rf tmp/cache/assets

# Reinstall node modules
yarn install --force
```

### Migration Issues

```bash
# Check migration status
rails db:migrate:status

# Rollback last migration
rails db:rollback

# Reset database (⚠️ deletes all data)
rails db:reset
```

## 📚 Documentation

- `PRODUCTION_READINESS.md` - Production deployment checklist
- `SCALABILITY.md` - Scaling and performance guide
- `LOGIN_CREDENTIALS.md` - Default user credentials
- `project.md` - Full project scope and requirements

## 🤝 Contributing

1. Create a feature branch
2. Make your changes
3. Write/update tests
4. Submit a pull request

## 📝 License

[Your License Here]

## 👥 Support

For issues, questions, or contributions, please [open an issue](link-to-issues) or contact the maintainers.

---

**Built with ❤️ for the faith community**
