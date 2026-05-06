module IconHelper
  def render_icon(name, classes: "w-6 h-6")
    icon_name = name.to_s.downcase.gsub(/[^a-z0-9]/, "")

    case icon_name
    when "heart", "hearthandshake"
      icon_svg("M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z", classes)
    when "sprout"
      icon_svg("M2 22s5-3 9-11 5-11 5-11M16 11s0 5 6 11", classes)
    when "bookopen", "book_open"
      icon_svg("M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z", classes)
    when "users"
      icon_svg("M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2 M16 3.13a4 4 0 0 1 0 7.75 M23 21v-2a4 4 0 0 0-3-3.87", classes)
    when "leaf"
      icon_svg("M11 20A7 7 0 0 1 9.8 6.1C15.5 5 17 4.48 19 2c1 2 2 4.18 2 8 0 5.5-4.78 10-10 10Z M2 21c0-3 1.85-5.36 5.08-6C9.5 14.52 12 13 13 12", classes)
    when "messagecircle", "message_circle", "messagecirclequestion"
      icon_svg("M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z", classes)
    when "lightbulb"
      icon_svg("M15 14c.2-1 .7-1.7 1.5-2.5 1-1 1.5-2.2 1.5-3.5A6 6 0 0 0 6 8c0 1 .2 2.2 1.5 3.5.7.7 1.3 1.5 1.5 2.5", classes) + icon_path("M9 18h6 M10 22h4", classes)
    when "handheart", "hand_heart", "pray", "prayer"
      icon_svg("M11 14h2a2 2 0 1 0 0-4h-2V7h4 M13 14v7 M7 7h10", classes) # Simplified
    when "shield"
      icon_svg("M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z", classes)
    when "baby"
      icon_svg("M9 12h.01 M15 12h.01 M10 16c.5.3 1.2.5 2 .5s1.5-.2 2-.5 M19 6.3a9 9 0 0 1 1.8 3.9 2 2 0 0 1 0 3.6 9 9 0 0 1-17.6 0 2 2 0 0 1 0-3.6A9 9 0 0 1 12 3c2 0 3.6.6 4.9 1.5L19 6.3z", classes)
    when "bookheart", "book_heart"
      icon_svg("M4 19.5A2.5 2.5 0 0 1 6.5 17H20 M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z M12 8a2 2 0 1 1 0 4 2 2 0 0 1 0-4Z", classes)
    when "home"
      icon_svg("M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z M9 22V12h6v10", classes)
    when "coffee"
      icon_svg("M18 8h1a4 4 0 0 1 0 8h-1 M2 8h16v9a4 4 0 0 1-4 4H6a4 4 0 0 1-4-4V8z M6 1v3 M10 1v3 M14 1v3", classes)
    when "graduationcap", "graduation_cap"
      icon_svg("M22 10v6M2 10l10-5 10 5-10 5z M6 12v5c3 3 9 3 12 0v-5", classes)
    when "music"
      icon_svg("M9 18V5l12-2v13 M6 22a3 3 0 0 1-3-3 3 3 0 0 1 3-3c.8 0 1.4.3 1.9.8V4.5L19 2.1v17.4c-.5-.5-1.1-.8-1.9-.8a3 3 0 0 1-3 3 3 3 0 0 1 3 3", classes)
    when "star"
      icon_svg("M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z", classes)
    when "sparkles"
      icon_svg("m12 3-1.912 5.813a2 2 0 0 1-1.275 1.275L3 12l5.813 1.912a2 2 0 0 1 1.275 1.275L12 21l1.912-5.813a2 2 0 0 1 1.275-1.275L21 12l-5.813-1.912a2 2 0 0 1-1.275-1.275L12 3Z", classes)
    when "church"
      icon_svg("m18 7 4 2v11a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9l4-2 M18 22V8.35l-6-3-6 3V22 M12 10v12 M12 4v2", classes)
    when "briefcase"
      icon_svg("M16 21V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16 M2 10h20 M2 21h20", classes)
    when "goal"
      icon_svg("M12 13V2l8 4-8 4 M20.55 10.23A9 9 0 1 1 8 4.94", classes)
    when "route"
      icon_svg("M6 19a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z M18 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z M8.6 14.6 15.4 9.4 M18 11v2a4 4 0 0 1-4 4H9", classes)
    when "globe"
      icon_svg("M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20z M2 12h20 M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z", classes)
    when "send"
      icon_svg("M22 2L11 13 M22 2l-7 20-4-9-9-4 20-7z", classes)
    when "search"
      icon_svg("M21 21l-4.35-4.35 M10.5 18a7.5 7.5 0 1 1 0-15 7.5 7.5 0 0 1 0 15z", classes)
    when "moon"
      icon_svg("M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z", classes)
    when "sun"
      icon_svg("M12 1v2 M12 21v2 M4.22 4.22l1.42 1.42 M18.36 18.36l1.42 1.42 M1 12h2 M21 12h2 M4.22 19.78l1.42-1.42 M18.36 5.64l1.42-1.42 M12 17a5 5 0 1 0 0-10 5 5 0 0 0 0 10z", classes)
    when "mail"
      icon_svg("M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z M22 6l-10 7L2 6", classes)
    when "phone"
      icon_svg("M22 16.92v3a2 2 0 0 1-2.18 2 19.8 19.8 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.11 4.2 2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.12.9.33 1.77.63 2.61a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.47-1.2a2 2 0 0 1 2.11-.45c.84.3 1.71.51 2.61.63A2 2 0 0 1 22 16.92z", classes)
    when "clock"
      icon_svg("M12 6v6l4 2 M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20z", classes)
    when "trendingup", "trending_up"
      icon_svg("M23 6l-9.5 9.5-5-5L1 18 M17 6h6v6", classes)
    when "arrowright", "arrow_right"
      icon_svg("M5 12h14 M12 5l7 7-7 7", classes)
    when "library"
      icon_svg("m16 6 4 14 M12 6v14 M8 8v12 M20 4v16a2 2 0 0 1-2 2h-2a2 2 0 0 1-2-2V6l-3.24-1.2a6.5 6.5 0 0 0-7.52 7 6.56 6.56 0 0 0 2.52 7.8L9 21", classes)
    when "filetext", "file_text"
      icon_svg("M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z M14 2v6h6 M16 13H8 M16 17H8 M10 9H8", classes)
    when "video"
      icon_svg("m22 8-6 4 6 4V8Z M2 6a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6Z", classes)
    when "headphones"
      icon_svg("M3 18v-6a9 9 0 0 1 18 0v6 M21 19a2 2 0 0 1-2 2h-1a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2h3zM3 19a2 2 0 0 0 2 2h1a2 2 0 0 0 2-2v-3a2 2 0 0 0-2-2H3z", classes)
    when "bookmarked", "book_marked"
      icon_svg("M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H20v20H6.5a2.5 2.5 0 0 1 0-5H20 M10 2v8l3-3 3 3V2", classes)
    when "image"
      icon_svg("M19 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2z M21 15l-5-5L5 21 M21 15l-5-5-5 5 M15.5 10a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3z", classes)
    when "download"
      icon_svg("M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4 M7 10l5 5 5-5 M12 15V3", classes)
    when "bookmark"
      icon_svg("m19 21-7-4-7 4V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v16z", classes)
    when "eye"
      icon_svg("M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z", classes)
    when "externallink", "external_link"
      icon_svg("M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6 M15 3h6v6 M10 14 21 3", classes)
    when "pencil"
      icon_svg("M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z M15 5l4 4", classes)
    when "checkmark", "check"
      icon_svg("M20 6 9 17l-5-5", classes)
    when "smile"
      icon_svg("<circle cx='12' cy='12' r='10' /><path d='M8 14s1.5 2 4 2 4-2 4-2' /><line x1='9' y1='9' x2='9.01' y2='9' /><line x1='15' y1='9' x2='15.01' y2='9' />", classes)
    when "x", "close", "xmark"
      icon_svg("M18 6 6 18 M6 6l12 12", classes)
    else
      # Default Sparkles
      icon_svg("m12 3-1.912 5.813a2 2 0 0 1-1.275 1.275L3 12l5.813 1.912a2 2 0 0 1 1.275 1.275L12 21l1.912-5.813a2 2 0 0 1 1.275-1.275L21 12l-5.813-1.912a2 2 0 0 1-1.275-1.275L12 3Z", classes)
    end
  end

  private

  def icon_svg(path, classes)
    content_tag(:svg, class: classes, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", stroke_width: "2", stroke_linecap: "round", stroke_linejoin: "round") do
      raw(if path.include?("<path") then path else "<path d='#{path}' />" end)
    end
  end

  def icon_path(d, classes)
    # helper for multi-path icons
    ""
  end
end
