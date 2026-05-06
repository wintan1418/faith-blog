# Cloudinary & SMTP Setup Guide

This guide will help you set up Cloudinary for file storage and SMTP for email delivery.

## 📦 Cloudinary Setup

### Step 1: Create a Cloudinary Account

1. Go to [https://cloudinary.com](https://cloudinary.com)
2. Sign up for a free account (includes 25GB storage and 25GB bandwidth)
3. Once logged in, go to your **Dashboard**

### Step 2: Get Your Cloudinary Credentials

From your Cloudinary dashboard, you'll need:
- **Cloud Name** (e.g., `your-cloud-name`)
- **API Key** (e.g., `123456789012345`)
- **API Secret** (e.g., `abcdefghijklmnopqrstuvwxyz123456`)

### Step 3: Configure Rails Credentials

Add Cloudinary credentials to your Rails encrypted credentials:

```bash
EDITOR="code --wait" rails credentials:edit
```

Add the following structure:

```yaml
cloudinary:
  cloud_name: your-cloud-name
  api_key: your-api-key
  api_secret: your-api-secret
```

Or use environment variables (recommended for production):

```bash
export CLOUDINARY_CLOUD_NAME=your-cloud-name
export CLOUDINARY_API_KEY=your-api-key
export CLOUDINARY_API_SECRET=your-api-secret
```

### Step 4: Install the Gem

The gem is already added to your `Gemfile`. Run:

```bash
bundle install
```

### Step 5: Configure Active Storage

The configuration is already set up in `config/storage.yml`. 

**For Development:**
- Uses local storage by default
- To test Cloudinary in development, set: `RAILS_STORAGE_SERVICE=cloudinary`

**For Production:**
- Set environment variable: `RAILS_STORAGE_SERVICE=cloudinary`
- Or update `config/environments/production.rb`:
  ```ruby
  config.active_storage.service = :cloudinary
  ```

### Step 6: Run Migration

```bash
rails db:migrate
```

### Step 7: Test Cloudinary

1. Start your Rails server
2. Upload an image (avatar or post image)
3. Check your Cloudinary dashboard → Media Library to see uploaded files

---

## 📧 SMTP Setup

### Option 1: Gmail SMTP (Recommended for Testing)

#### Step 1: Enable App Passwords

1. Go to your Google Account settings
2. Enable **2-Step Verification** (required for app passwords)
3. Go to **Security** → **App passwords**
4. Generate a new app password for "Mail"
5. Copy the 16-character password

#### Step 2: Configure Rails Credentials

```bash
EDITOR="code --wait" rails credentials:edit
```

Add:

```yaml
smtp:
  address: smtp.gmail.com
  port: 587
  domain: gmail.com
  user_name: your-email@gmail.com
  password: your-16-char-app-password
  authentication: plain
  from: "Faith Community <your-email@gmail.com>"
```

#### Step 3: Update Production Environment

The configuration is already in `config/environments/production.rb`. 

**Update the host:**
```ruby
config.action_mailer.default_url_options = { 
  host: "yourdomain.com",  # Change this!
  protocol: "https"
}
```

**Or use environment variables:**
```bash
export RAILS_HOST=yourdomain.com
export SMTP_ADDRESS=smtp.gmail.com
export SMTP_PORT=587
export SMTP_DOMAIN=gmail.com
export SMTP_USER_NAME=your-email@gmail.com
export SMTP_PASSWORD=your-app-password
export SMTP_AUTH=plain
export MAILER_FROM="Faith Community <your-email@gmail.com>"
```

---

### Option 2: SendGrid (Recommended for Production)

#### Step 1: Create SendGrid Account

1. Go to [https://sendgrid.com](https://sendgrid.com)
2. Sign up for a free account (100 emails/day)
3. Verify your email address

#### Step 2: Create API Key

1. Go to **Settings** → **API Keys**
2. Click **Create API Key**
3. Name it (e.g., "Rails App")
4. Choose **Full Access** or **Restricted Access** (Mail Send)
5. Copy the API key (you'll only see it once!)

#### Step 3: Verify Sender

1. Go to **Settings** → **Sender Authentication**
2. Verify a Single Sender or Domain
3. Use the verified email as your `from` address

#### Step 4: Configure Rails Credentials

```bash
EDITOR="code --wait" rails credentials:edit
```

Add:

```yaml
smtp:
  address: smtp.sendgrid.net
  port: 587
  domain: yourdomain.com
  user_name: apikey
  password: your-sendgrid-api-key
  authentication: plain
  from: "Faith Community <noreply@yourdomain.com>"
```

---

### Option 3: Mailgun

#### Step 1: Create Mailgun Account

1. Go to [https://mailgun.com](https://mailgun.com)
2. Sign up (free tier: 5,000 emails/month for 3 months)
3. Verify your domain or use sandbox domain for testing

#### Step 2: Get SMTP Credentials

1. Go to **Sending** → **Domain Settings**
2. Click on your domain
3. Go to **SMTP credentials** section
4. Note your SMTP username and password

#### Step 3: Configure Rails Credentials

```bash
EDITOR="code --wait" rails credentials:edit
```

Add:

```yaml
smtp:
  address: smtp.mailgun.org
  port: 587
  domain: yourdomain.com
  user_name: postmaster@yourdomain.mailgun.org
  password: your-mailgun-password
  authentication: plain
  from: "Faith Community <noreply@yourdomain.com>"
```

---

## 🧪 Testing Email Configuration

### Test in Rails Console

```ruby
# Start Rails console
rails console

# Test email delivery
user = User.first
UserMailer.welcome_email(user).deliver_now
```

### Test Email Templates

Create a test mailer:

```ruby
# app/mailers/test_mailer.rb
class TestMailer < ApplicationMailer
  def test_email
    mail(
      to: "your-email@example.com",
      subject: "Test Email from Faith Community"
    ) do |format|
      format.html { render html: "<h1>Email is working!</h1>".html_safe }
      format.text { render plain: "Email is working!" }
    end
  end
end
```

Then in console:

```ruby
TestMailer.test_email.deliver_now
```

---

## 🔒 Security Best Practices

1. **Never commit credentials to git**
   - Use Rails credentials or environment variables
   - Add `.env` to `.gitignore` if using dotenv

2. **Use different credentials for each environment**
   - Development: Local or test SMTP
   - Production: Production SMTP service

3. **Rotate credentials regularly**
   - Update passwords/API keys every 90 days
   - Revoke old credentials when updating

4. **Use environment variables in production**
   - Set via your hosting platform (Heroku, AWS, etc.)
   - Never hardcode in code

---

## 🚀 Production Checklist

- [ ] Cloudinary account created and configured
- [ ] Cloudinary credentials added to Rails credentials or environment variables
- [ ] SMTP service chosen and account created
- [ ] SMTP credentials added to Rails credentials or environment variables
- [ ] `RAILS_HOST` environment variable set to your domain
- [ ] `RAILS_STORAGE_SERVICE=cloudinary` set in production
- [ ] Email delivery tested in production environment
- [ ] Cloudinary uploads tested
- [ ] Email notifications working (user confirmations, password resets, etc.)

---

## 📝 Environment Variables Summary

For production, set these environment variables:

```bash
# Cloudinary
CLOUDINARY_CLOUD_NAME=your-cloud-name
CLOUDINARY_API_KEY=your-api-key
CLOUDINARY_API_SECRET=your-api-secret

# SMTP
RAILS_HOST=yourdomain.com
SMTP_ADDRESS=smtp.gmail.com  # or smtp.sendgrid.net, smtp.mailgun.org
SMTP_PORT=587
SMTP_DOMAIN=yourdomain.com
SMTP_USER_NAME=your-email@gmail.com  # or apikey for SendGrid
SMTP_PASSWORD=your-password
SMTP_AUTH=plain
MAILER_FROM="Faith Community <noreply@yourdomain.com>"

# Storage
RAILS_STORAGE_SERVICE=cloudinary
```

---

## 🆘 Troubleshooting

### Cloudinary Issues

**Problem:** Images not uploading
- **Solution:** Check credentials are correct
- **Solution:** Verify `RAILS_STORAGE_SERVICE=cloudinary` is set
- **Solution:** Check Cloudinary dashboard for errors

**Problem:** "Invalid cloud name"
- **Solution:** Verify cloud name in credentials matches dashboard

### SMTP Issues

**Problem:** "Authentication failed"
- **Solution:** Check username/password are correct
- **Solution:** For Gmail, ensure you're using an App Password, not your regular password
- **Solution:** Verify 2FA is enabled for Gmail

**Problem:** "Connection timeout"
- **Solution:** Check firewall isn't blocking port 587
- **Solution:** Verify SMTP address is correct
- **Solution:** Try port 465 with SSL instead

**Problem:** Emails going to spam
- **Solution:** Set up SPF/DKIM records for your domain
- **Solution:** Use a verified sender address
- **Solution:** Warm up your sending domain gradually

---

## 📚 Additional Resources

- [Cloudinary Documentation](https://cloudinary.com/documentation)
- [Rails Active Storage with Cloudinary](https://cloudinary.com/documentation/rails_integration)
- [SendGrid Documentation](https://docs.sendgrid.com/)
- [Mailgun Documentation](https://documentation.mailgun.com/)
- [Rails Action Mailer Guide](https://guides.rubyonrails.org/action_mailer_basics.html)

---

**Need Help?** Check the logs:
- Rails logs: `tail -f log/development.log` or `log/production.log`
- Cloudinary logs: Check your Cloudinary dashboard
- SMTP logs: Check your email service dashboard

