namespace :avatars do
  desc "Attach avatars to all users who don't have one"
  task attach_all: :environment do
    require 'open-uri'
    require 'net/http'
    
    puts "🖼️  Attaching avatars to all users..."
    
    def attach_avatar_from_url(profile, url, filename)
      begin
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true if uri.scheme == 'https'
        http.read_timeout = 10
        http.open_timeout = 10
        
        request = Net::HTTP::Get.new(uri.request_uri)
        response = http.request(request)
        
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
          content_type = response['content-type'] || 'image/png'
          
          profile.avatar.attach(
            io: io,
            filename: filename,
            content_type: content_type
          )
          true
        else
          false
        end
      rescue => e
        puts "    ⚠️  Error: #{e.message}"
        false
      end
    end
    
    User.includes(:profile).find_each do |user|
      next unless user.profile
      
      if user.profile.avatar.attached?
        puts "  ✓ #{user.username} already has an avatar"
        next
      end
      
      # Generate avatar URL based on username
      avatar_url = "https://api.dicebear.com/7.x/avataaars/png?seed=#{user.username}&size=200&backgroundColor=b6e3f4,c0aede,d1d4f9,ffd5dc,ffdfbf"
      
      puts "  📷 Attaching avatar to #{user.username}..."
      if attach_avatar_from_url(user.profile, avatar_url, "avatar_#{user.username}.png")
        puts "    ✓ Success!"
      else
        puts "    ✗ Failed"
      end
    end
    
    puts "\n✅ Done!"
  end
  
  desc "Re-attach avatars to all users (force update)"
  task reattach_all: :environment do
    require 'open-uri'
    require 'net/http'
    
    puts "🖼️  Re-attaching avatars to all users..."
    
    def attach_avatar_from_url(profile, url, filename)
      begin
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true if uri.scheme == 'https'
        http.read_timeout = 10
        http.open_timeout = 10
        
        request = Net::HTTP::Get.new(uri.request_uri)
        response = http.request(request)
        
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
          content_type = response['content-type'] || 'image/png'
          
          # Purge existing avatar if any
          profile.avatar.purge if profile.avatar.attached?
          
          profile.avatar.attach(
            io: io,
            filename: filename,
            content_type: content_type
          )
          true
        else
          false
        end
      rescue => e
        puts "    ⚠️  Error: #{e.message}"
        false
      end
    end
    
    User.includes(:profile).find_each do |user|
      next unless user.profile
      
      # Generate avatar URL based on username
      avatar_url = "https://api.dicebear.com/7.x/avataaars/png?seed=#{user.username}&size=200&backgroundColor=b6e3f4,c0aede,d1d4f9,ffd5dc,ffdfbf"
      
      puts "  📷 Re-attaching avatar to #{user.username}..."
      if attach_avatar_from_url(user.profile, avatar_url, "avatar_#{user.username}.png")
        puts "    ✓ Success!"
      else
        puts "    ✗ Failed"
      end
    end
    
    puts "\n✅ Done!"
  end
end

