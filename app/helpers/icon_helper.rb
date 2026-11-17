module IconHelper
  # One outline icon set for the whole app (Lucide shapes, 24px grid, bold
  # 2.25 stroke). These win over the older shapes further down.
  ICONS = {
    "home" => "M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z",
    "feed" => "M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z",
    "users" => "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75",
    "user" => "M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8z",
    "userplus" => "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM19 8v6M22 11h-6",
    "usersearch" => "M10 13a5 5 0 1 0 0-10 5 5 0 0 0 0 10zM2 21a8 8 0 0 1 10.4-7.6M18 20a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM22 22l-1.9-1.9",
    "bookopen" => "M2 4h6a4 4 0 0 1 4 4v13a3 3 0 0 0-3-3H2zM22 4h-6a4 4 0 0 0-4 4v13a3 3 0 0 1 3-3h7z",
    "bible" => "M2 4h6a4 4 0 0 1 4 4v13a3 3 0 0 0-3-3H2zM22 4h-6a4 4 0 0 0-4 4v13a3 3 0 0 1 3-3h7z",
    "messagecircle" => "M7.9 20A9 9 0 1 0 4 16.1L2 22z",
    "chat" => "M7.9 20A9 9 0 1 0 4 16.1L2 22z",
    "comment" => "M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z",
    "bell" => "M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9M10.3 21a1.94 1.94 0 0 0 3.4 0",
    # pages
    "x" => "M18 6 6 18M6 6l12 12",
    "close" => "M18 6 6 18M6 6l12 12",
    "check" => "M20 6 9 17l-5-5",
    "reply" => "M9 17 4 12l5-5M20 18v-2a4 4 0 0 0-4-4H4",
    "mail" => "M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2zM22 6l-10 7L2 6",
    "star" => "M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01z",
    "leaf" => "M11 20A7 7 0 0 1 9.8 6.1C15.5 5 17 4.5 19 2c1 2 2 4.2 2 8 0 5.5-4.8 10-10 10zM2 21c0-3 1.9-5.4 5.1-6C9.5 14.5 12 13 13 12",
    "thumbsup" => "M7 10v12M15 5.9 14 10h5.8a2 2 0 0 1 1.9 2.6l-2.3 8a2 2 0 0 1-1.9 1.4H4a2 2 0 0 1-2-2v-8a2 2 0 0 1 2-2h2.8a2 2 0 0 0 1.8-1.1L12 2a3.1 3.1 0 0 1 3 3.9z",
    "link" => "M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7",
    "externallink" => "M15 3h6v6M10 14 21 3M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6",
    "mappin" => "M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0zM12 13a3 3 0 1 0 0-6 3 3 0 0 0 0 6z",
    "dove" => "M16 7h.01M3.4 18H12a8 8 0 0 0 8-8V7a4 4 0 0 0-7.3-2.3L2 20M20 7l2 .5-2 .5M10 18v3M14 17.8V21M7 18a6 6 0 0 0 3.8-10.6",
    "handshake" => "M11 17l2 2a1 1 0 1 0 3-3M14 14l2.5 2.5a1 1 0 1 0 3-3l-3.9-3.9a3 3 0 0 0-4.2 0l-.9.9a1 1 0 1 1-3-3l2.8-2.8a5.8 5.8 0 0 1 7.1-.9l.5.3a2 2 0 0 0 1.4.3L21 4M21 3l1 11h-2M3 3 2 14l6.5 6.5a1 1 0 1 0 3-3M3 4h8",
    "target" => "M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM12 18a6 6 0 1 0 0-12 6 6 0 0 0 0 12zM12 14a2 2 0 1 0 0-4 2 2 0 0 0 0 4z",
    "filetext" => "M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7zM14 2v4a2 2 0 0 0 2 2h4M16 13H8M16 17H8M10 9H8",
    "belloff" => "M8.7 3A6 6 0 0 1 18 8a21.3 21.3 0 0 0 .6 5M17 17H3s3-2 3-9a4.7 4.7 0 0 1 .3-1.7M10.3 21a1.94 1.94 0 0 0 3.4 0M2 2l20 20",
    "volumeoff" => "M11 5 6 9H2v6h4l5 4zM22 9l-6 6M16 9l6 6",
    "volume" => "M11 5 6 9H2v6h4l5 4zM15.5 8.5a5 5 0 0 1 0 7M19 5a10 10 0 0 1 0 14",
    "ban" => "M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM4.9 4.9l14.2 14.2",
    "download" => "M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M7 10l5 5 5-5M12 15V3",
    "wifioff" => "M12 20h.01M8.5 16.4a5 5 0 0 1 7 0M2 8.8a15 15 0 0 1 4.2-2.8M22 8.8a15 15 0 0 0-11.3-3.8M16.9 12.6a10 10 0 0 1 2.1 1.4M5 12.9a10 10 0 0 1 5.2-2.4M2 2l20 20",
    "inbox" => "M22 12h-6l-2 3h-4l-2-3H2M5.5 5.1 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.5-6.9A2 2 0 0 0 16.8 4H7.2a2 2 0 0 0-1.7 1.1z",
    "pen" => "M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z",
    "camera" => "M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3zM12 17a4 4 0 1 0 0-8 4 4 0 0 0 0 8z",
    "film" => "M3 3h18v18H3zM7 3v18M17 3v18M3 7.5h4M3 12h18M3 16.5h4M17 7.5h4M17 16.5h4",
    "building" => "M6 22V4a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v18zM6 12H4a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2h2M18 9h2a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-2M10 6h4M10 10h4M10 14h4M10 18h4",
    "wrench" => "M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.8-3.8a6 6 0 0 1-7.9 7.9l-6.9 6.9a2.1 2.1 0 0 1-3-3l6.9-6.9a6 6 0 0 1 7.9-7.9z",
    "flask" => "M10 2v7.5L4 20a1 1 0 0 0 .9 1.5h14.2A1 1 0 0 0 20 20l-6-10.5V2M8.5 2h7M7 16h10",
    "rocket" => "M4.5 16.5c-1.5 1.3-2 5-2 5s3.7-.5 5-2c.7-.8.7-2.1-.1-2.9a2.2 2.2 0 0 0-2.9-.1zM12 15l-3-3a22 22 0 0 1 2-4A12.9 12.9 0 0 1 22 2c0 2.7-.8 7.5-6 11a22.4 22.4 0 0 1-4 2zM9 12H4s.6-3 2-4c1.6-1.1 5 0 5 0M12 15v5s3-.6 4-2c1.1-1.6 0-5 0-5",
    "stethoscope" => "M11 2v2M5 2v2M5 3H4a2 2 0 0 0-2 2v4a6 6 0 0 0 12 0V5a2 2 0 0 0-2-2h-1M8 15a6 6 0 0 0 12 0v-3M20 12a2 2 0 1 0 0-4 2 2 0 0 0 0 4z",
    "shirt" => "M20.4 3.5 16 2a4 4 0 0 1-8 0L3.6 3.5a2 2 0 0 0-1.3 2.2l.6 3.5a1 1 0 0 0 1 .8H6v10a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V10h2.2a1 1 0 0 0 1-.8l.6-3.5a2 2 0 0 0-1.3-2.2z",
    "brush" => "M9.1 11.2 3.3 17a2.1 2.1 0 1 0 3 3l5.8-5.8M14 13.5l7.4-7.4a2.1 2.1 0 0 0-3-3l-7.4 7.4M9.5 12.5l2 2",
    "arrowup" => "M12 19V5M5 12l7-7 7 7",
    "arrowdown" => "M12 5v14M19 12l-7 7-7-7",
    "copy" => "M10 8h10a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H10a2 2 0 0 1-2-2V10a2 2 0 0 1 2-2zM4 16a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2",
    "notifications" => "M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9M10.3 21a1.94 1.94 0 0 0 3.4 0",
    "pray" => "M11 14h2a2 2 0 1 0 0-4h-3c-.6 0-1.1.2-1.4.6L3 16M7 20l1.6-1.4c.3-.4.8-.6 1.4-.6h4c1.1 0 2.1-.4 2.8-1.2l4.6-4.4a2 2 0 0 0-2.75-2.91l-4.2 3.9M2 15l6 6M19.5 8.5c.7-.7 1.5-1.6 1.5-2.7A2.73 2.73 0 0 0 16 4a2.78 2.78 0 0 0-5 1.8c0 1.2.8 2 1.5 2.8L16 12z",
    "answered" => "M22 11.1V12a10 10 0 1 1-5.9-9.1M22 4 12 14l-3-3",
    "checkcircle" => "M22 11.1V12a10 10 0 1 1-5.9-9.1M22 4 12 14l-3-3",
    "checkcheck" => "M18 7l-8 8-4-4M22 7l-8 8",
    "badgecheck" => "M3.85 8.62a4 4 0 0 1 4.78-4.77 4 4 0 0 1 6.74 0 4 4 0 0 1 4.78 4.78 4 4 0 0 1 0 6.74 4 4 0 0 1-4.77 4.78 4 4 0 0 1-6.75 0 4 4 0 0 1-4.78-4.77 4 4 0 0 1 0-6.76zM9 12l2 2 4-4",
    "games" => "M6 11h4M8 9v4M15 12h.01M18 10h.01M17.3 5H6.7a4 4 0 0 0-4 3.6l-.9 7.4a3 3 0 0 0 3 3.3c1.2 0 2-.6 2.6-1.5L8.5 16h7l1.1 1.8c.6.9 1.4 1.5 2.6 1.5a3 3 0 0 0 3-3.3l-.9-7.4a4 4 0 0 0-4-3.6z",
    "gamepad" => "M6 11h4M8 9v4M15 12h.01M18 10h.01M17.3 5H6.7a4 4 0 0 0-4 3.6l-.9 7.4a3 3 0 0 0 3 3.3c1.2 0 2-.6 2.6-1.5L8.5 16h7l1.1 1.8c.6.9 1.4 1.5 2.6 1.5a3 3 0 0 0 3-3.3l-.9-7.4a4 4 0 0 0-4-3.6z",
    "quiz" => "M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3M12 17h.01",
    "chess" => "M6 21h12M7.5 17.5h9M9 17.5c.3-2.6 1.6-4 1.6-6.3-2.4.5-4 0-4.6-1.7L10 5l.5-2.5 1.8 1.6C16.6 4.6 19 8 18.6 13c-.2 2-.7 3.3-1.1 4.5M11.5 8.5h.01",
    "church" => "M10 9h4M12 7v5M14 22v-4a2 2 0 0 0-4 0v4M18 22V5.6l-6-3-6 3V22M18 9l4 2v11H2V11l4-2",
    "quote" => "M3 21c3 0 7-1 7-8V5c0-1.25-.76-2-2-2H4c-1.25 0-2 .75-2 2v6c0 1.25.75 2 2 2 1 0 1 0 1 1v1c0 1-1 2-2 2s-1 0-1 1v3c0 1 0 1 1 1zM15 21c3 0 7-1 7-8V5c0-1.25-.76-2-2-2h-4c-1.25 0-2 .75-2 2v6c0 1.25.75 2 2 2h.75c0 2.25.25 4-2.75 4v3c0 1 0 1 1 1z",
    "shuffle" => "M2 18h1.4c1.3 0 2.5-.6 3.3-1.7l6.1-8.6c.7-1.1 2-1.7 3.3-1.7H22M18 2l4 4-4 4M2 6h1.9c1.5 0 2.9.9 3.6 2.2M22 18h-5.9c-1.3 0-2.6-.7-3.3-1.8l-.5-.8M18 14l4 4-4 4",
    "grid" => "M4 3h5a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM15 3h5a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1h-5a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM15 14h5a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1h-5a1 1 0 0 1-1-1v-5a1 1 0 0 1 1-1zM4 14h5a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-5a1 1 0 0 1 1-1z",
    "trophy" => "M6 9H4.5a2.5 2.5 0 0 1 0-5H6M18 9h1.5a2.5 2.5 0 0 0 0-5H18M4 22h16M10 14.7V17c0 .6-.5 1-1 1.2C7.9 18.8 7 20.2 7 22M14 14.7V17c0 .6.5 1 1 1.2 1.1.6 2 2 2 3.8M18 2H6v7a6 6 0 0 0 12 0z",
    "flame" => "M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.4-.5-2-1-3-1.1-2.1-.2-4 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.2.4-2.3 1-3a2.5 2.5 0 0 0 2.5 2.5z",
    "breathe" => "M3.5 13c2.2-4.5 4.8-4.5 7 0s4.8 4.5 7 0c.8-1.6 1.7-2.6 3-3",
    "wave" => "M3.5 13c2.2-4.5 4.8-4.5 7 0s4.8 4.5 7 0c.8-1.6 1.7-2.6 3-3",
    "newspaper" => "M4 22h16a2 2 0 0 0 2-2V4a2 2 0 0 0-2-2H8a2 2 0 0 0-2 2v16a2 2 0 0 1-2 2zm0 0a2 2 0 0 1-2-2v-9c0-1.1.9-2 2-2h2M18 14h-8M15 18h-5M10 6h8v4h-8z",
    "blog" => "M4 22h16a2 2 0 0 0 2-2V4a2 2 0 0 0-2-2H8a2 2 0 0 0-2 2v16a2 2 0 0 1-2 2zm0 0a2 2 0 0 1-2-2v-9c0-1.1.9-2 2-2h2M18 14h-8M15 18h-5M10 6h8v4h-8z",
    "cake" => "M20 21v-8a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8M4 16s.5-1 2-1 2.5 2 4 2 2.5-2 4-2 2.5 2 4 2 2-1 2-1M2 21h20M7 8v3M12 8v3M17 8v3M7 4h.01M12 4h.01M17 4h.01",
    "calendar" => "M8 2v4M16 2v4M5 4h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2zM3 10h18",
    "bookmark" => "M19 21l-7-4-7 4V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z",
    "image" => "M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2zM9 11a2 2 0 1 0 0-4 2 2 0 0 0 0 4zM21 15l-3.1-3.1a2 2 0 0 0-2.8 0L6 21",
    "mic" => "M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3zM19 10v2a7 7 0 0 1-14 0v-2M12 19v3",
    "heart" => "M19 14c1.5-1.5 3-3.2 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.8 0-3 .5-4.5 2-1.5-1.5-2.7-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4 3 5.5l7 7z",
    "praise" => "M18 11V6a2 2 0 0 0-4 0M14 10V4a2 2 0 0 0-4 0v2M10 10.5V6a2 2 0 0 0-4 0v8M18 8a2 2 0 1 1 4 0v6a8 8 0 0 1-8 8h-2c-2.8 0-4.5-.9-6-2.3l-3.6-3.6a2 2 0 0 1 2.8-2.8L7 15",
    "lightbulb" => "M15 14c.2-1 .7-1.7 1.5-2.5 1-.9 1.5-2.2 1.5-3.5A6 6 0 0 0 6 8c0 1 .2 2.2 1.5 3.5.7.7 1.3 1.5 1.5 2.5M9 18h6M10 22h4",
    "repost" => "M17 2l4 4-4 4M3 11v-1a4 4 0 0 1 4-4h14M7 22l-4-4 4-4M21 13v1a4 4 0 0 1-4 4H3",
    "send" => "M22 2 11 13M22 2l-7 20-4-9-9-4z",
    "pin" => "M12 17v5M9 10.8a2 2 0 0 1-1.1 1.8l-1.8.9A2 2 0 0 0 5 15.2V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.8a2 2 0 0 0-1.1-1.8l-1.8-.9a2 2 0 0 1-1.1-1.8V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z",
    "sparkles" => "M9.9 14.1 12 21l2.1-6.9L21 12l-6.9-2.1L12 3 9.9 9.9 3 12z",
    "search" => "M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16zM21 21l-4.3-4.3",
    "plus" => "M12 5v14M5 12h14",
    "chevrondown" => "m6 9 6 6 6-6",
    "chevronright" => "m9 18 6-6-6-6",
    "chevronleft" => "m15 18-6-6 6-6",
    "back" => "m15 18-6-6 6-6",
    "eyeoff" => "M9.9 4.2A10 10 0 0 1 12 4c7 0 10 8 10 8a13 13 0 0 1-1.7 2.7M6.6 6.6A13.5 13.5 0 0 0 2 12s3 8 10 8a9.7 9.7 0 0 0 5.4-1.6M2 2l20 20M14.1 14.1a3 3 0 1 1-4.2-4.2",
    "clock" => "M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM12 6v6l4 2",
    "thread" => "M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01",
    "play" => "M7 4.5v15a1 1 0 0 0 1.5.86l12.5-7.5a1 1 0 0 0 0-1.72L8.5 3.64A1 1 0 0 0 7 4.5z",
    "settings" => "M12.2 2h-.4a2 2 0 0 0-2 2v.2a2 2 0 0 1-1 1.7l-.4.3a2 2 0 0 1-2 0l-.2-.1a2 2 0 0 0-2.7.7l-.2.4a2 2 0 0 0 .7 2.7l.2.1a2 2 0 0 1 1 1.7v.5a2 2 0 0 1-1 1.8l-.2.1a2 2 0 0 0-.7 2.7l.2.4a2 2 0 0 0 2.7.7l.2-.1a2 2 0 0 1 2 0l.4.3a2 2 0 0 1 1 1.7v.2a2 2 0 0 0 2 2h.4a2 2 0 0 0 2-2v-.2a2 2 0 0 1 1-1.7l.4-.3a2 2 0 0 1 2 0l.2.1a2 2 0 0 0 2.7-.7l.2-.4a2 2 0 0 0-.7-2.7l-.2-.1a2 2 0 0 1-1-1.7v-.5a2 2 0 0 1 1-1.8l.2-.1a2 2 0 0 0 .7-2.7l-.2-.4a2 2 0 0 0-2.7-.7l-.2.1a2 2 0 0 1-2 0l-.4-.3a2 2 0 0 1-1-1.7V4a2 2 0 0 0-2-2zM12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z",
    "megaphone" => "m3 11 18-5v12L3 14v-3zM11.6 16.8a3 3 0 1 1-5.8-1.6",
    "dashboard" => "M3 3h7v9H3zM14 3h7v5h-7zM14 12h7v9h-7zM3 16h7v5H3z",
    "smartphone" => "M7 2h10a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2zM12 18h.01",
    "shield" => "M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z",
    "shieldcheck" => "M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10zM9 12l2 2 4-4",
    "flag" => "M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1zM4 22v-7",
    "sword" => "M14.5 17.5 3 6V3h3l11.5 11.5M13 19l6-6M16 16l4 4M19 21l2-2",
    "dumbbell" => "M6.5 6.5h11M6.5 17.5h11M6 20V4M18 20V4M3 15V9M21 15V9",
    "laptop" => "M4 5h16a1 1 0 0 1 1 1v10H3V6a1 1 0 0 1 1-1zM2 20h20",
    "sunrise" => "M12 2v8M4.9 10.9l1.4 1.4M2 18h2M20 18h2M19.1 10.9l-1.4 1.4M22 22H2M8 6l4-4 4 4M16 18a4 4 0 0 0-8 0",
    "utensils" => "M3 2v7c0 1.1.9 2 2 2h4a2 2 0 0 0 2-2V2M7 2v20M21 15V2a5 5 0 0 0-5 5v6c0 1.1.9 2 2 2h3zm0 0v7",
    "palette" => "M12 22a10 10 0 1 1 10-10c0 2.2-1.8 3-3.5 3H16a2 2 0 0 0-1.6 3.2A2 2 0 0 1 12 22zM7.5 10.5h.01M10.5 7.5h.01M15.5 8.5h.01",
    "sprout" => "M7 20h10M10 20c5.5-2.5.8-6.4 3-10M9.5 9.4c1.1.8 1.8 2.2 2.3 3.7-2 .4-3.5.4-4.8-.3-1.2-.6-2.3-1.9-3-4.2 2.8-.5 4.4 0 5.5.8zM14.1 6a7 7 0 0 0-1.1 4c1.9-.1 3.3-.6 4.3-1.4 1-1 1.6-2.3 1.7-4.6-2.7.1-4 1-4.9 2z",
    "globe" => "M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM2 12h20M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z",
    "graduationcap" => "M22 10v6M2 10l10-5 10 5-10 5zM6 12v5c3 3 9 3 12 0v-5",
    "briefcase" => "M16 20V4a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16M4 6h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2z",
    "music" => "M9 18V5l12-2v13M6 21a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM18 19a3 3 0 1 0 0-6 3 3 0 0 0 0 6z",
    "library" => "M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H20v20H6.5a2.5 2.5 0 0 1 0-5H20",
    "dot" => "M12 13a1 1 0 1 0 0-2 1 1 0 0 0 0 2z"
  }.freeze

  ALIASES = {
    "book_open" => "bookopen", "message_circle" => "messagecircle", "prayer" => "pray", "handheart" => "pray",
    "hand_heart" => "pray", "game" => "games", "chesspuzzle" => "chess", "answeredprayers" => "answered",
    "reshare" => "repost", "retweet" => "repost", "repeat" => "repost", "like" => "heart", "amen" => "pray",
    "microphone" => "mic", "profile" => "user", "connections" => "users", "rooms" => "users",
    "verse" => "bookopen", "streak" => "flame", "leaderboard" => "trophy", "birthday" => "cake",
    "report" => "flag", "moderation" => "shieldcheck", "announcements" => "megaphone", "appversions" => "smartphone"
  }.freeze

  # Rooms (and a few older records) store an emoji as their icon. Map each one
  # to a real icon, so nothing falls back to a generic mark.
  EMOJI_ICONS = {
    "⚔️" => "sword", "⚔" => "sword", "💪" => "dumbbell", "👨" => "user", "👩" => "user", "👴" => "user",
    "🎵" => "music", "💻" => "laptop", "❓" => "quiz", "📖" => "bookopen", "🎓" => "graduationcap",
    "🌅" => "sunrise", "🍳" => "utensils", "💼" => "briefcase", "🙏" => "pray", "🌟" => "answered",
    "📚" => "library", "💑" => "heart", "👨‍👩‍👧‍👦" => "users", "🎨" => "palette", "🌍" => "globe",
    "🌱" => "sprout", "✨" => "sparkles", "⛪" => "church", "🎯" => "games", "🔥" => "flame",
    "📰" => "newspaper", "🏆" => "trophy", "🎂" => "cake", "🕊️" => "dove", "🕊" => "dove", "🤝" => "handshake",
    "🛡" => "shield", "🛡️" => "shield", "📣" => "megaphone", "🔔" => "bell", "💬" => "comment", "📍" => "mappin",
    "🔗" => "link", "📲" => "smartphone", "🎉" => "sparkles", "⭐" => "star", "❤️" => "heart", "👤" => "user",
    "📷" => "camera", "🎙️" => "mic", "🎙" => "mic", "📌" => "pin", "🔍" => "search", "🎮" => "games",
    "📸" => "camera", "🗓️" => "calendar", "📅" => "calendar", "💡" => "lightbulb", "🙌" => "praise", "🔒" => "shield"
  }.freeze

  # The icon name a room should show: its emoji mapped, else its name, else a group.
  def room_icon_name(room)
    raw = room.respond_to?(:icon) ? room.icon.to_s.strip : ""
    EMOJI_ICONS[raw] || (raw.match?(/\A[a-z_]+\z/i) ? raw : "users")
  end

  # An icon for an emoji stored in data (announcement slides and the like),
  # with a fallback when the emoji has no match.
  def emoji_icon_name(emoji, fallback: "sparkles")
    raw = emoji.to_s.strip
    EMOJI_ICONS[raw] || EMOJI_ICONS[raw.delete("\uFE0F")] || fallback
  end

  def render_icon(name, classes: "w-6 h-6")
    raw_name = name.to_s.strip
    if (mapped = EMOJI_ICONS[raw_name])
      raw_name = mapped
    end
    icon_name = raw_name.downcase.gsub(/[^a-z0-9_]/, "")
    icon_name = ALIASES[icon_name] || icon_name
    icon_name = icon_name.delete("_")
    if (path = ICONS[icon_name] || ICONS[ALIASES[icon_name].to_s])
      return icon_svg(path, classes)
    end

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
    when "reply"
      icon_svg("M9 17 4 12l5-5 M20 18v-2a4 4 0 0 0-4-4H4", classes)
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
    when "pencil", "edit"
      icon_svg("M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z M15 5l4 4", classes)
    when "trash", "trash_2"
      icon_svg("M3 6h18 M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6 M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2", classes)
    when "checkmark", "check"
      icon_svg("M20 6 9 17l-5-5", classes)
    when "smile"
      icon_svg("<circle cx='12' cy='12' r='10' /><path d='M8 14s1.5 2 4 2 4-2 4-2' /><line x1='9' y1='9' x2='9.01' y2='9' /><line x1='15' y1='9' x2='15.01' y2='9' />", classes)
    when "repeat", "reshare", "retweet"
      icon_svg("<polyline points='17 1 21 5 17 9' /><path d='M3 11V9a4 4 0 0 1 4-4h14' /><polyline points='7 23 3 19 7 15' /><path d='M21 13v2a4 4 0 0 1-4 4H3' />", classes)
    when "x", "close", "xmark"
      icon_svg("M18 6 6 18 M6 6l12 12", classes)
    when "flag", "report"
      icon_svg("M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z M4 22V15", classes)
    when "more", "morehorizontal", "more_horizontal", "ellipsis", "dots"
      icon_svg("<circle cx='5' cy='12' r='1' /><circle cx='12' cy='12' r='1' /><circle cx='19' cy='12' r='1' />", classes)
    when "thumbsup", "thumbs_up", "like"
      icon_svg("M7 10v12 M15 5.88 14 10h5.83a2 2 0 0 1 1.92 2.56l-2.33 8A2 2 0 0 1 17.5 22H4a2 2 0 0 1-2-2v-8a2 2 0 0 1 2-2h2.76a2 2 0 0 0 1.79-1.11L12 2a3.13 3.13 0 0 1 3 3.88Z", classes)
    when "mic", "microphone"
      icon_svg("<path d='M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z' /><path d='M19 10v2a7 7 0 0 1-14 0v-2' /><path d='M12 19v3' />", classes)
    when "compose", "squarepen", "newmessage"
      icon_svg("<path d='M12 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7' /><path d='M18.4 2.6a2.1 2.1 0 0 1 3 3L12.5 14.5 8.5 15.5l1-4Z' />", classes)
    when "lock", "password"
      icon_svg("<rect x='4' y='11' width='16' height='10' rx='2' /><path d='M8 11V7a4 4 0 0 1 8 0v4' />", classes)
    when "share", "shareup"
      icon_svg("<path d='M4 12v7a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-7' /><path d='M16 6l-4-4-4 4' /><path d='M12 2v13' />", classes)
    when "paperclip", "attach"
      icon_svg("m21.44 11.05-9.19 9.19a6 6 0 0 1-8.49-8.49l8.57-8.57A4 4 0 1 1 18 8.84l-8.59 8.57a2 2 0 0 1-2.83-2.83l8.49-8.48", classes)
    when "cross"
      icon_svg("<path d='M12 3v18' /><path d='M7 8h10' />", classes)
    when "forward"
      icon_svg("<polyline points='15 17 20 12 15 7' /><path d='M4 18v-2a4 4 0 0 1 4-4h12' />", classes)
    when "chevronleft", "back"
      icon_svg("M15 18l-6-6 6-6", classes)
    else
      # Unknown name: a quiet dot rather than a sparkle that pretends to mean something.
      icon_svg(ICONS["dot"], classes)
    end
  end

  private

  def icon_svg(path, classes)
    content_tag(:svg, class: classes, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", "stroke-width": "2.25", "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": "true") do
      raw(if path.include?("<") then path else "<path d='#{path}' />" end)
    end
  end

  def icon_path(d, classes)
    # helper for multi-path icons
    ""
  end
end
