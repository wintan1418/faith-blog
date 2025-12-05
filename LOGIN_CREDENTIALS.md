# Faith Community - Login Credentials

> **Password for all accounts:** `password123`

## Development Environment

All accounts use the password: `password123`

---

### 👑 Admin Account
| Field | Value |
|-------|-------|
| **Email** | `admin@faithcommunity.com` |
| **Password** | `password123` |
| **Username** | admin |
| **Role** | Administrator |

**Capabilities:** Full access to admin dashboard, user management, content moderation, reports, and all platform features.

---

### 🛡️ Moderator Accounts

#### Pastor James
| Field | Value |
|-------|-------|
| **Email** | `pastor.james@faithcommunity.com` |
| **Password** | `password123` |
| **Username** | PastorJames |
| **Role** | Moderator |

#### Sarah Worship
| Field | Value |
|-------|-------|
| **Email** | `sarah.worship@faithcommunity.com` |
| **Password** | `password123` |
| **Username** | SarahWorship |
| **Role** | Moderator |

**Capabilities:** Can moderate content, manage rooms, review reports, and feature posts.

---

### 👤 Member Accounts

| Username | Email | Location |
|----------|-------|----------|
| JohnGrace | `john.grace@example.com` | Chicago, IL |
| MariaHope | `maria.hope@example.com` | Miami, FL |
| DavidWarrior | `david.warrior@example.com` | San Antonio, TX |
| RachelLight | `rachel.light@example.com` | Boston, MA |
| MichaelRestored | `michael.restored@example.com` | Phoenix, AZ |
| EmilyPrayer | `emily.prayer@example.com` | Seattle, WA |
| DanielSeeker | `daniel.seeker@example.com` | San Francisco, CA |
| GraceRenewed | `grace.renewed@example.com` | Atlanta, GA |
| PeterBuilder | `peter.builder@example.com` | Denver, CO |
| AnnaMissionary | `anna.missionary@example.com` | Orlando, FL |
| DrLukeHeal | `luke.physician@example.com` | Houston, TX |
| RuthFaithful | `ruth.faithful@example.com` | Nashville, TN |
| TimothyYoung | `timothy.young@example.com` | Portland, OR |
| EstherBrave | `esther.brave@example.com` | New York, NY |
| PaulTransformed | `paul.transformed@example.com` | Los Angeles, CA |

**All member passwords:** `password123`

---

## Quick Start

1. Start the development server:
   ```bash
   cd /home/wintan/faith_blog
   bin/dev
   ```

2. Visit http://localhost:3000

3. Click "Sign In" and use any credentials above

---

## Features to Explore

- **Feed** - Browse posts from all users
- **Rooms** - 7 different themed discussion rooms
- **Resources** - Library of faith-based materials
- **Dark Mode** - Click the moon/sun icon in navbar
- **Profile** - View and edit your profile
- **Bookmarks** - Save posts for later
- **Notifications** - Activity alerts
- **Admin Dashboard** - (Admin only) Platform management
- **Brethren Card** - Your contact card for connecting with other believers
- **Can I Know You More?** - Send connection requests to exchange Brethren Cards

---

## 🤝 Testing "Can I Know You More?" Feature

### Users with Complete Brethren Cards
These users have completed their Brethren Card and can send/receive connection requests:
- JohnGrace, MariaHope, DavidWarrior, RachelLight, MichaelRestored
- EmilyPrayer, DanielSeeker, GraceRenewed, RuthFaithful, TimothyYoung
- PaulTransformed, PastorJames, SarahWorship, admin

### Pre-existing Connections (can view each other's cards)
| User 1 | User 2 |
|--------|--------|
| JohnGrace | MariaHope |
| JohnGrace | MichaelRestored |
| JohnGrace | PastorJames |
| DavidWarrior | MichaelRestored |
| RachelLight | DanielSeeker |
| EmilyPrayer | GraceRenewed |
| PastorJames | MichaelRestored |
| SarahWorship | EmilyPrayer |
| RuthFaithful | TimothyYoung |
| PaulTransformed | MichaelRestored |

### Pending Requests
| From | To |
|------|-----|
| RachelLight | EmilyPrayer |
| DanielSeeker | GraceRenewed |
| TimothyYoung | PaulTransformed |

### How to Test
1. Login as **JohnGrace** - go to another user's profile, you'll see "Can I Know You More?" button
2. Login as **EmilyPrayer** - check notifications or "My Connections" to see pending request from RachelLight
3. Go to **Settings > Brethren Card** to edit your card
4. Visit a connected user's profile and click "View Brethren Card"

---

## Notes

- These credentials are for **development only**
- Never use these passwords in production
- All users have been pre-seeded with profiles, posts, comments, and interactions

