# Cloudinary Active Storage Setup

Production uses Cloudinary for Active Storage by default. Add these Hatchbox environment variables before deploying:

```bash
RAILS_STORAGE_SERVICE=cloudinary
CLOUDINARY_URL=cloudinary://API_KEY:API_SECRET@CLOUD_NAME
CLOUDINARY_FOLDER=brethreign/production
```

Replace all three placeholder parts. For example, if Cloudinary shows cloud name `brethreign-app`,
API key `123456789`, and API secret `abcxyz`, set:

```bash
CLOUDINARY_URL=cloudinary://123456789:abcxyz@brethreign-app
```

Do not leave `API_KEY`, `API_SECRET`, or `CLOUD_NAME` in the value.

You can also use separate variables instead of `CLOUDINARY_URL`:

```bash
CLOUDINARY_CLOUD_NAME=your_cloud_name
CLOUDINARY_API_KEY=your_api_key
CLOUDINARY_API_SECRET=your_api_secret
CLOUDINARY_FOLDER=brethreign/production
```

After setting the variables, redeploy or restart the app. Verify the active service on the server:

```bash
bin/rails runner 'puts Rails.application.config.active_storage.service; puts ActiveStorage::Blob.service.class.name'
```

Expected output:

```text
cloudinary
ActiveStorage::Service::CloudinaryService
```

Test by uploading a profile photo, post image, or resource file, then confirm the file appears in the Cloudinary media library under the configured folder.

Existing files already uploaded to local disk are not moved automatically. They can be migrated separately if production already has local attachments.
