# frozen_string_literal: true

# Renders the shapes PostOgCard stamps onto link-preview cards (the
# Brethreign "B", heart, speech bubble, verified badge, anonymous person) to
# grayscale PNG masks in vendor/og/. The app can't draw SVG itself: Active
# Storage blocks libvips' SVG loader in the app process, on purpose.
#
#   ruby script/render_og_masks.rb    (needs libvips with librsvg)
require "vips"

root = File.expand_path("..", __dir__)
logo = File.read(File.join(root, "app/views/shared/_logomark.html.erb"))[/<path fill="#3cdb9d" d="([^"]+)"/, 1]
out = File.join(root, "vendor/og")
Dir.mkdir(out) unless Dir.exist?(out)

shapes = {
  "logomark" => [ 30, 46, %(<svg xmlns="http://www.w3.org/2000/svg" width="30" height="46" viewBox="0 0 670.46 1024"><path fill="#fff" d="#{logo}"/></svg>) ],
  "heart" => [ 28, 28, %(<svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24"><path d="M12 20.5s-7.2-4.4-9.2-8.8C1.4 8.4 3.4 4.8 6.9 4.8c2 0 3.6 1.1 5.1 2.9 1.5-1.8 3.1-2.9 5.1-2.9 3.5 0 5.5 3.6 4.1 6.9-2 4.4-9.2 8.8-9.2 8.8z" fill="none" stroke="#fff" stroke-width="2.1" stroke-linejoin="round"/></svg>) ],
  "bubble" => [ 28, 28, %(<svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24"><path d="M4.5 5h15A1.5 1.5 0 0 1 21 6.5v9a1.5 1.5 0 0 1-1.5 1.5H10l-4.5 3.6V17h-1A1.5 1.5 0 0 1 3 15.5v-9A1.5 1.5 0 0 1 4.5 5z" fill="none" stroke="#fff" stroke-width="2.1" stroke-linejoin="round"/></svg>) ],
  "verified" => [ 30, 30, %(<svg xmlns="http://www.w3.org/2000/svg" width="30" height="30" viewBox="0 0 30 30"><defs><mask id="m"><rect width="30" height="30" fill="#fff"/><path d="M9 15.5l4 4 8.5-9" fill="none" stroke="#000" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/></mask></defs><circle cx="15" cy="15" r="15" fill="#fff" mask="url(#m)"/></svg>) ],
  "person" => [ 40, 40, %(<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 24 24"><g fill="none" stroke="#fff" stroke-width="1.9" stroke-linecap="round"><circle cx="12" cy="8.5" r="4"/><path d="M4.5 20.5c0-4.1 3.4-7.3 7.5-7.3s7.5 3.2 7.5 7.3"/></g></svg>) ]
}

shapes.each do |name, (_w, _h, svg)|
  image = Vips::Image.svgload_buffer(svg)
  image.extract_band(3).pngsave(File.join(out, "#{name}.png"))
  puts "vendor/og/#{name}.png"
end
