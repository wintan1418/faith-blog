# Cloudinary Image Storage Status

## Current Configuration

### ✅ Cloudinary is Configured
- Cloudinary gem is installed
- Credentials are set in `.env` file (not committed to git)

### 📍 Current Storage Service

**Development Mode:**
- Currently using: **Local Storage** (files stored in `/storage` directory)
- To switch to Cloudinary, add to `.env`:
  ```
  RAILS_STORAGE_SERVICE=cloudinary
  ```

**Production Mode:**
- Configured to use: **Cloudinary** (when `RAILS_STORAGE_SERVICE=cloudinary` is set)

## How Images Are Currently Handled

### Right Now (Local Storage)
- **Avatar uploads** → Stored in `/home/wintan/faith_blog/storage/`
- **Post images** → Stored in `/home/wintan/faith_blog/storage/`
- Images are served directly from your server
- URLs look like: `http://localhost:4190/rails/active_storage/disk/...`

### When Using Cloudinary
- **Avatar uploads** → Uploaded to Cloudinary CDN
- **Post images** → Uploaded to Cloudinary CDN
- Images are served from Cloudinary's fast CDN
- URLs look like: `https://res.cloudinary.com/wintan1418/image/upload/...`
- Automatic image optimization and transformations
- Better performance and scalability

## How to Enable Cloudinary

### Option 1: Enable in Development (Recommended for Testing)

1. Edit your `.env` file:
   ```bash
   # Add or uncomment this line:
   RAILS_STORAGE_SERVICE=cloudinary
   ```

2. Restart your server:
   ```bash
   # Stop current server (Ctrl+C)
   bin/dev
   ```

3. New uploads will go to Cloudinary!

### Option 2: Keep Local for Development, Use Cloudinary in Production

This is the default setup. Just set `RAILS_STORAGE_SERVICE=cloudinary` in your production environment variables.

## Migrating Existing Images to Cloudinary

If you want to move existing local images to Cloudinary:

```ruby
# In Rails console: rails console

# Migrate all avatars
User.find_each do |user|
  if user.profile&.avatar&.attached?
    user.profile.avatar.blob.open do |file|
      user.profile.avatar.attach(
        io: file,
        filename: user.profile.avatar.filename.to_s
      )
    end
  end
end

# Migrate all post images
Post.find_each do |post|
  post.images.each do |image|
    image.blob.open do |file|
      post.images.attach(
        io: file,
        filename: image.filename.to_s
      )
    end
  end
end
```

## Benefits of Using Cloudinary

1. **CDN Delivery**: Images served from edge locations worldwide
2. **Automatic Optimization**: Images are optimized for web automatically
3. **Transformations**: Resize, crop, format conversion on-the-fly
4. **Scalability**: No storage limits on your server
5. **Bandwidth**: Reduces load on your server

## Check Current Storage Service

```ruby
# In Rails console
Rails.application.config.active_storage.service
# Returns: :local or :cloudinary
```

## Troubleshooting

### Images not uploading to Cloudinary?
- Check `.env` file has `RAILS_STORAGE_SERVICE=cloudinary`
- Verify Cloudinary credentials are correct
- Restart the server after changing `.env`

### Want to switch back to local?
- Remove or comment out `RAILS_STORAGE_SERVICE=cloudinary` from `.env`
- Restart server

---

**Current Status**: Using **Local Storage** in development
**To Enable Cloudinary**: Add `RAILS_STORAGE_SERVICE=cloudinary` to `.env` and restart

