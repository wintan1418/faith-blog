# Faith Community App UI Redesign Brief for Claude

Use this document as the full design brief for redesigning the Faith Community app UI. The goal is to produce a complete product design direction that can be implemented in a Ruby on Rails app with Tailwind CSS, Hotwire/Turbo, Stimulus, Devise, ActionText, and Active Storage.

## 1. Product Summary

Faith Community is a faith-based community platform. It is not only a blog. It combines:

- A social feed for posts, testimonies, prayer requests, questions, and encouragement.
- Topic-based community rooms.
- Rich text posts with tags, images, comments, mentions, reactions, bookmarks, and reshares.
- User profiles with follow relationships.
- A private connection system called "Can I Know You More?" using Brethren Cards.
- A resource library for articles, videos, audio, PDFs, and books.
- Notifications.
- Search.
- Admin tools for users, rooms, posts, resources, reports, and moderation.

The current UI is inconsistent and over-decorated. Redesign it as a modern, calm, trustworthy community product. It should feel warm and faith-centered without looking like a church flyer, landing page, or template dashboard.

## 2. Core Design Goal

Create a coherent app-wide design system and screen architecture.

The design should feel:

- Calm, clear, and readable.
- Warm but not beige-heavy.
- Faith-centered without excessive religious decoration.
- Social and community-focused.
- Useful for repeat daily use.
- Consistent across public, authenticated, settings, resource, and admin screens.

Avoid:

- Overly large rounded cards everywhere.
- Big decorative heroes on authenticated app pages.
- Fake buttons or controls that look interactive but do nothing.
- Random gradients, blur blobs, decorative orbs, and oversized icon panels.
- One-off colors per page.
- Mixing different UI languages, such as Medium article styling, social feed styling, and marketing landing styling with no shared rules.

## 3. Current UI Problems to Solve

The redesign should explicitly fix these issues:

1. The app has no consistent design system. Feed, post cards, resources, rooms, search, profile, settings, auth, and admin all look like different products.
2. Many UI controls are fake or visual-only. If a button or filter appears in the design, specify what it does or remove it.
3. Authenticated app pages use large marketing-style hero sections. Replace them with compact product headers and useful controls.
4. There are too many card radii, shadows, gradients, and hover animations.
5. The navigation hides important flows. Notifications, bookmarks, connections, profile, and settings need clearer access.
6. The resource library looks like a static mockup instead of a working library.
7. Feed sidebars contain fake trending tags, fake suggested communities, fake prayer CTAs, and static verification marks.
8. Profile and Brethren Card screens are too ornamental and visually heavy.
9. Search uses a different visual language from the rest of the app.
10. Admin screens are not aligned with the user-facing design system.
11. Empty states, loading states, error states, permissions states, and mobile layouts are not consistently designed.

## 4. Technical Context

The app is Ruby on Rails 8 with:

- Tailwind CSS.
- Hotwire/Turbo.
- Stimulus controllers.
- Devise authentication.
- ActionText rich text editor.
- Active Storage image and file uploads.
- Pagy pagination.
- pg_search search.
- FriendlyId slugs.

Design output should be easy to implement in ERB partials and Tailwind classes. Prefer practical components and page structures. Do not require a large frontend rewrite.

## 5. User Roles

### Guest

Can view:

- Landing/home page.
- About page.
- Community guidelines.
- Contact page.
- Public rooms list and room pages.
- Public posts and post detail pages.
- Public user profiles.
- Resource library pages.
- Search.
- Sign in, sign up, confirmation, password reset.

Cannot:

- Create posts.
- Comment.
- React.
- Bookmark.
- Reshare.
- Follow.
- Send connection requests.
- View private Brethren Cards.
- Use settings.
- Use admin.

### Member

Can:

- Create/edit/delete own posts.
- Add images to posts.
- Add tags.
- Comment and reply.
- React to posts and comments.
- Bookmark posts.
- Reshare posts.
- Follow/unfollow users.
- Search posts, people, and resources.
- Submit resources for approval.
- View notifications.
- Manage profile and account.
- Complete Brethren Card.
- Send "Can I Know You More?" connection requests.
- Accept or decline incoming connection requests.
- View Brethren Cards only after accepted connection.

### Moderator

Can:

- Do member actions.
- Feature/unfeature posts.
- Participate in moderation flows where enabled.

### Admin

Can:

- Manage users.
- Manage rooms.
- Manage posts.
- Manage resources.
- Approve or reject resources.
- Review reports.
- View moderation logs.
- Access admin dashboard.

## 6. Main Feature Inventory

### Authentication

- Sign up with username and email.
- Sign in.
- Sign out.
- Email confirmation.
- Password reset.
- Account edit.

### Profiles

- Avatar.
- Username.
- Bio.
- Location.
- Faith background.
- Website.
- Public/private profile setting exists in the data model.
- User posts list.
- Followers/following counts.
- Follow/unfollow.
- Admin/moderator role badges.

### Feed

- Recent posts.
- Trending posts.
- Following feed.
- Post composer entry point.
- Post cards.
- Tags.
- Room badges.
- Reactions.
- Comments count.
- Reshares.
- Bookmarks.

### Rooms

- Room index.
- Room detail.
- Join/leave room.
- Room posts.
- Room metadata: name, description, icon, color, rules, member count, post count.

### Posts

- New post.
- Edit post.
- Post detail.
- Rich text content.
- Up to 5 images.
- Anonymous posting.
- Allow or disable comments.
- Tags.
- Related/linked posts.
- Featured state.
- Reading time.
- Views count.

### Comments

- Root comments.
- Replies.
- Edit/delete own comments.
- Soft delete display.
- Comment reactions.
- Mentions.

### Reactions

Faith-based reaction types:

- Amen.
- Praying.
- Be Encouraged.
- Love.
- Inspired.

### Bookmarks

- Bookmark/unbookmark posts.
- Bookmarks index.

### Reshares

- Reshare/unreshare posts.
- Reshare count.
- Cannot reshare own post.

### Mentions

- Typeahead user mention support using `@username`.
- Mention notifications.
- Mentions should render as profile links.

### Notifications

Types include:

- New comment.
- Reply to comment.
- New follower.
- Post featured.
- New post in room.
- Resource approved.
- Resource rejected.
- Mentioned.
- Post liked.
- Comment liked.
- Connection request.
- Connection accepted.
- Post reshared.

### Resource Library

Resource types:

- Link.
- Video.
- PDF.
- Audio.
- Book.

Resource fields:

- Title.
- Description.
- Type.
- URL or uploaded file.
- Category.
- Approved status.
- Featured status.
- Views count.
- Downloads count.

Screens needed:

- Library home/index.
- Resource detail.
- Submit resource.
- Edit resource.
- Category index.
- Category detail.

### Brethren Card and Connections

Brethren Card fields:

- Church or assembly.
- Bio.
- Occupation.
- WhatsApp number.
- Email.
- Completion state.

Connection flows:

- Profile button: "Can I Know You More?"
- Requires sender to complete card.
- Pending sent state.
- Incoming request accept/decline.
- Accepted connection unlocks Brethren Card viewing.
- My connections list.

### Search

Search result types:

- Posts.
- People.
- Resources.

Needs:

- Query input.
- Result tabs.
- Empty state.
- Result counts.
- Mobile-friendly layout.

### Admin

Admin areas:

- Dashboard.
- Users.
- Rooms.
- Posts.
- Resources.
- Reports.
- Moderation logs.

Admin needs:

- Compact table views.
- Search/filter controls.
- Status badges.
- Clear destructive actions.
- Approval/rejection flows.
- Moderation audit history.

## 7. Full Page and Screen Map

Design all relevant screens below. It is acceptable to group similar screens, but each route/page should have a clear layout direction.

### Public Pages

1. Landing page: `/`
   - For guests only.
   - Explain the community clearly.
   - Show a real preview of rooms, featured posts, and resource value.
   - Primary CTA: Join.
   - Secondary CTA: Explore rooms or learn more.
   - Should be warmer than app screens but still use the same design system.

2. About: `/about`
   - Mission, values, what members can do.
   - Keep readable and simple.

3. Guidelines: `/guidelines`
   - Community standards.
   - Needs scannable sections and clear rules.

4. Contact: `/contact`
   - Simple contact form or contact info.
   - Current form is visual only unless wired. Design should indicate expected behavior.

### Auth Pages

5. Sign in: `/users/sign_in`
   - Email/password.
   - Remember me.
   - Links to sign up and reset password.

6. Sign up: `/users/sign_up`
   - Username, email, password, confirmation.
   - Friendly but compact.

7. Password reset: `/users/password/new`
   - Email input.

8. Confirmation: `/users/confirmation/new`
   - Resend confirmation instructions.

9. Account edit: `/users/edit` and `/settings/account/edit`
   - Account identity and password changes.

### App Shell

10. Primary authenticated layout
   - Top navigation or app shell.
   - Must expose: Feed, Rooms, Resources, Search, Notifications, Connections, Bookmarks, Profile, Settings.
   - Use notification unread indicator.
   - Mobile needs bottom navigation or compact menu.
   - Avoid hiding too much in avatar dropdown.

### Feed Pages

11. Main feed: `/feed`
   - Recent posts.
   - Composer entry point.
   - Filter tabs: Recent, Trending, Following.
   - Optional room/category filter, but only if wired.
   - Post cards should be the canonical reusable card.
   - Right/left sidebars should contain real data only.
   - Remove fake suggested communities and fake stats unless designed as empty placeholders.

12. Trending feed: `/feed/trending`
   - Same feed layout with active Trending tab.
   - Explain trend basis subtly if needed.

13. Following feed: `/feed/following`
   - Same feed layout with active Following tab.
   - Empty state if user follows nobody.

### Rooms

14. Rooms index: `/rooms`
   - Product list page, not a landing page.
   - Compact header with title, short description, search, filters.
   - Room cards should be consistent and not overly colorful.
   - Each room card: icon, name, description, member count, post count, public/private, join/view action.
   - Include empty state.

15. Room detail: `/rooms/:id`
   - Header: room name, description, stats, join/leave, rules.
   - Tabs or sections: Posts, About/Rules, Members if available.
   - Room posts use same post card as feed.

16. Room posts: `/rooms/:room_id/posts`
   - Can reuse room detail posts section or redirect-style design.

### Posts

17. New post: `/posts/new`
   - Rich text writing interface.
   - Room selector.
   - Title.
   - Body editor.
   - Image upload with previews and max 5 note.
   - Tags input.
   - Anonymous checkbox.
   - Allow comments checkbox.
   - Related posts selector if kept.
   - Primary action: Publish.
   - Secondary: Cancel.
   - Needs validation/error design.

18. Edit post: `/posts/:id/edit`
   - Same as new post, with existing content and images.
   - Clarify whether old images can be removed.

19. Post detail: `/posts/:id`
   - Article-like but still aligned with app design.
   - Header: author, room, date, reading time, featured badge.
   - Content.
   - Image gallery.
   - Tags.
   - Related posts.
   - Actions: react, comment, reshare, bookmark, edit/delete when permitted, feature/unfeature for mods/admins.
   - Comments section with composer and threaded replies.
   - Comments disabled state.
   - Guest sign-in prompt.

20. Reusable post card
   - Must work in feed, user profile, search, room pages, bookmarks.
   - Include:
     - Author/avatar or anonymous state.
     - Room badge.
     - Title.
     - Excerpt.
     - Optional image thumbnail.
     - Tags.
     - Reaction count/action.
     - Comment count.
     - Reshare action/count.
     - Bookmark action.
   - Avoid having separate competing card designs.

### Comments

21. Comment component
   - Avatar.
   - Author.
   - Timestamp.
   - Body with mentions.
   - Reaction action.
   - Reply action.
   - Edit/delete if permitted.
   - Deleted state.
   - Nested replies with clear indentation but no cramped layout on mobile.

22. Comment form
   - Compact rich text or text area.
   - Mention support.
   - Submit/cancel.

### Reactions

23. Reaction picker
   - Works for posts and comments.
   - Should be accessible and clear.
   - Should show selected state.
   - Should not rely only on emoji.

### Bookmarks

24. Bookmarks index: `/bookmarks`
   - List saved posts.
   - Empty state with CTA to browse feed.

### Notifications

25. Notifications index: `/notifications`
   - List notifications grouped by read/unread or date.
   - Mark one read.
   - Mark all read.
   - Empty state.
   - Each notification should include icon/type, actor, message, time, read state.

### Search

26. Search page: `/search`
   - Query input.
   - Type tabs: Posts, People, Resources.
   - Results list with consistent cards.
   - Empty state before search.
   - No-results state after search.
   - Result count.
   - Mobile tabs should not overflow awkwardly.

### Users and Social Graph

27. User profile: `/u/:username`
   - Profile header.
   - Avatar, username, bio, role badge.
   - Location, join date, faith background, website if available.
   - Follow/unfollow button.
   - Connection request button and state.
   - Counts: posts, followers, following.
   - User posts list.
   - If profile privacy is relevant, include private profile state.

28. User posts: `/u/:username/posts`
   - Reuses profile posts list or separate tab.

29. Followers: `/u/:username/followers`
   - User list.
   - Follow buttons.
   - Empty state.

30. Following: `/u/:username/following`
   - User list.
   - Follow buttons.
   - Empty state.

### Brethren Card and Connections

31. Brethren Card public/accepted view: `/brethren_cards/:username`
   - Only for accepted connections or owner.
   - Present contact information respectfully.
   - Avoid making it look like a flashy badge or business card toy.
   - Show church/assembly, bio, occupation, WhatsApp, email.
   - Clear privacy note.

32. Edit Brethren Card: `/settings/brethren_card/edit`
   - Form with completion progress.
   - Preview panel optional, but keep compact.
   - Explain that card is shared only after accepted connection.

33. Connection requests: `/connection_requests`
   - Incoming pending requests.
   - Sent requests.
   - Accept/decline actions.
   - Status badges.
   - Empty states.

34. My connections: `/my-connections`
   - List accepted connections.
   - Access each Brethren Card.
   - Empty state encouraging meaningful connection.

### Resources

35. Resource library home: `/resources`
   - Should be a real library page.
   - Header: title, description, search.
   - Filters: type, category, featured, recent/popular if wired.
   - Featured resources.
   - Recent resources.
   - Category navigation.
   - Submit resource CTA.
   - No fake static counts.

36. Resource item index: `/resources`
   - Current routes conflict with the library home. Design should recommend one clear route strategy.
   - Preferred: `/resources` as searchable index/library.
   - Resource detail can be `/resources/:id`.
   - New/edit can be `/resources/new` and `/resources/:id/edit`.

37. Resource detail: `/resources/:id`
   - Title, type, category, description.
   - Submitted by.
   - Approved/featured state.
   - Open link/download action.
   - Views/downloads.
   - Related resources if available.

38. Submit resource: `/resources/new`
   - Title, description, type, category, URL or file.
   - Approval pending message.

39. Edit resource: `/resources/:id/edit`
   - Same as submit.

40. Resource categories: `/resource_categories`
   - Category list with resource counts.

41. Resource category detail: `/resource_categories/:id`
   - Resources in category.
   - Filters/sort.

### Settings

42. Profile settings: `/settings/profile/edit`
   - Avatar.
   - Bio.
   - Location.
   - Faith background.
   - Website.
   - Public profile toggle.

43. Account settings: `/settings/account/edit`
   - Email.
   - Username.
   - Password.
   - Password confirmation.

44. Notification settings: `/settings/notifications/edit`
   - Route exists but screen/controller may not be implemented.
   - Design expected notification preferences.

45. Privacy settings: `/settings/privacy/edit`
   - Route exists but screen/controller may not be implemented.
   - Design expected privacy controls, especially profile visibility and Brethren Card privacy.

### Admin

46. Admin layout
   - Separate but visually related app shell.
   - Sidebar: Dashboard, Users, Rooms, Posts, Resources, Reports, Moderation Logs.
   - Dense, utilitarian, low decoration.

47. Admin dashboard: `/admin`
   - Metrics: users, new users today, posts, posts today, pending reports, pending resources.
   - Recent posts.
   - Recent users.
   - Action links.

48. Admin users: `/admin/users`
   - Table/list with search/filter.
   - Role, active state, joined date.
   - Actions: suspend, activate, make moderator, make admin, edit, delete.

49. Admin rooms: `/admin/rooms`
   - Table/list.
   - Create/edit/delete room.
   - Room stats and public/private state.

50. Admin posts: `/admin/posts`
   - Table/list.
   - Status, room, author, featured.
   - Feature/unfeature, edit, delete.

51. Admin resources: `/admin/resources`
   - Table/list.
   - Pending/approved.
   - Approve/reject.
   - Create/edit/delete.

52. Admin reports: `/admin/reports`
   - Table/list.
   - Reportable item, reporter, reason, status.
   - Resolve/dismiss.
   - Show detail.

53. Admin moderation logs: `/admin/moderation_logs`
   - Audit log list.
   - Filter by action/moderator/date if useful.

## 8. Navigation Requirements

### Desktop

Create a clear app shell. Suggested navigation:

- Logo.
- Feed.
- Rooms.
- Resources.
- Search.
- Create/Share button.
- Notifications icon with unread badge.
- Connections icon or menu item.
- User menu with Profile, Bookmarks, Settings, Admin if permitted, Sign out.

For authenticated users, avoid a marketing nav. It should feel like an app.

### Mobile

Use either:

- Bottom navigation with Feed, Rooms, Create, Resources, Profile.
- Top compact bar with search and notifications.

Important mobile flows:

- Create post must be easy to reach.
- Notifications must be visible.
- Search must not be hidden behind too many taps.
- Long tab rows should become horizontal scroll with clear affordance.

## 9. Component System to Design

Claude should produce a component system before page designs.

Required components:

- App shell.
- Public shell.
- Admin shell.
- Page header.
- Section header.
- Button: primary, secondary, ghost, danger, icon.
- Icon button.
- Avatar.
- User mini card.
- Badge/status pill.
- Tabs/segmented control.
- Search input.
- Filter chip.
- Dropdown menu.
- Card base.
- Post card.
- Room card.
- Resource card.
- Notification row.
- Comment component.
- Reaction picker.
- Empty state.
- Form field.
- Rich text editor container.
- Image upload preview.
- Modal/dialog.
- Table/list pattern for admin.

Component rules:

- Cards should generally use 8px to 12px radius for product surfaces.
- Use larger radius only for avatars, pills, and intentionally soft CTAs.
- Keep shadows subtle.
- Use icons consistently.
- Avoid nested cards unless necessary.
- Do not place cards inside decorative cards.
- Avoid huge hover movement. Use color/border changes instead.

## 10. Visual Direction

### Palette

Use a restrained palette:

- Base background: warm off-white or very light neutral.
- Surface: white.
- Primary: deep/sage green.
- Secondary/accent: muted amber/gold.
- Text: dark green-gray or near-black.
- Muted text: gray-green.
- Borders: soft neutral/green-gray.
- Success: green.
- Warning: amber.
- Danger: muted red.
- Info: blue or teal, used sparingly.

Avoid:

- Purple-heavy sections.
- Too many room colors.
- Hardcoded random hex colors per screen.
- Beige/cream dominance.
- Dark slate dominance.
- Gradient-heavy UI.

### Typography

Use one primary sans font for app UI.

Use serif only sparingly:

- Landing page headline.
- A few public/brand moments.

Do not use serif for every card heading or dense app screen.

Hierarchy:

- App page titles: compact, clear.
- Feed/post card titles: readable but not huge.
- Body text: comfortable line height.
- Metadata: smaller and muted.

### Layout

Authenticated app pages should prioritize scanning and action:

- Compact page headers.
- Clear filters.
- Useful lists.
- Consistent spacing.
- Responsive behavior.

Public pages may be more expressive, but should still use the same system.

## 11. Screen State Requirements

For each major screen, design these states where applicable:

- Default with data.
- Empty state.
- Loading state or skeleton.
- Error/validation state.
- Signed-out state.
- Permission denied state.
- Mobile layout.

Key empty states:

- Feed with no posts.
- Following feed with no follows.
- Room with no posts.
- Bookmarks empty.
- Notifications empty.
- Search before query.
- Search no results.
- Resource library empty.
- Connection requests empty.
- My connections empty.
- User has no posts.

## 12. Specific Redesign Decisions Needed

Claude should answer these decisions explicitly:

1. What is the canonical post card layout?
2. Should authenticated pages use a left sidebar, top nav only, or hybrid?
3. What are the primary navigation items on desktop and mobile?
4. What visual language should distinguish public pages from app pages?
5. What is the final palette and token list?
6. What radius, shadow, border, and spacing scale should be used?
7. How should rooms use icons/colors without becoming chaotic?
8. How should reactions appear on cards and detail pages?
9. How should the Brethren Card flow communicate privacy and trust?
10. How should admin screens look while staying connected to the brand?

## 13. Output Requested from Claude

Please produce:

1. A design system specification:
   - Color tokens.
   - Typography tokens.
   - Spacing scale.
   - Radius scale.
   - Shadow rules.
   - Component styles.

2. A redesigned information architecture:
   - Desktop navigation.
   - Mobile navigation.
   - User menu.
   - Admin navigation.

3. Screen-by-screen redesign:
   - Give layout, sections, components, states, and behavior for every page group listed above.
   - Include desktop and mobile notes.
   - Identify which current fake UI should be removed or converted into real controls.

4. Implementation guidance:
   - Reusable Rails partial/component suggestions.
   - Tailwind class patterns or token names.
   - Migration plan from current UI to redesigned UI.

5. Prioritized rollout plan:
   - Phase 1: app shell and design tokens.
   - Phase 2: feed/post cards/post detail/comments.
   - Phase 3: rooms/resources/search.
   - Phase 4: profile/connections/settings.
   - Phase 5: admin.

## 14. Design Quality Bar

The final design should be production-grade, not just visually pleasant.

It must:

- Make the app easier to use.
- Remove fake interactions.
- Reduce visual noise.
- Improve consistency.
- Work well on mobile.
- Make primary actions obvious.
- Preserve warmth and faith/community identity.
- Be realistic to implement in Rails ERB and Tailwind.

Do not return a vague brand moodboard only. Return a practical design system and page-level product design spec that an engineer can implement.

