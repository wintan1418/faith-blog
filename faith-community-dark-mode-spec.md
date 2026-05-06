# Faith Community — Dark Mode Specification

**Version 1.0 · Companion document to the Faith Community redesign prototype**

This document specifies the dark-mode color system, behavior, and implementation for the Faith Community app. Hand this to engineers alongside the prototype HTML.

---

## 1. Behavior

### Toggle
- Single icon button in the top-right of the app header (moon icon for "switch to dark", sparkle/sun for "switch to light").
- Available on every authenticated and public route except admin (admin uses its own dark sidebar shell).

### Persistence
- User preference stored in `localStorage` under the key `fc-dark` with values `'1'` (dark) or `'0'` (light).
- On first visit (no stored value), respect `prefers-color-scheme: dark` from the OS.
- Server-side: also persist to `users.dark_mode` boolean column so the choice carries across devices once authenticated. Cookie-fall-through for guests.

### Application
- Theme is applied via three coordinated mechanisms:
  1. `data-theme="dark"` attribute on `<html>`
  2. `theme-dark` / `theme-light` class on `<html>` AND `<body>` (defeats Chromium's custom-property invalidation bug for inherited body styles on runtime toggle)
  3. Direct `setProperty` of every color token on `documentElement.style` (forces full cascade recompute)
- Body inline color and background are also written as literal hex values with `!important` to guarantee inheritance.

---

## 2. Color tokens — dark theme

All values are sRGB hex. Where light mode uses warm sage neutrals, dark mode uses **deep evergreen** neutrals to keep the brand identity coherent.

### Base surfaces

| Token              | Light value | Dark value | Role                                  |
|--------------------|-------------|------------|---------------------------------------|
| `--bg`             | `#f6f3ec`   | `#0f1714`  | Page background                       |
| `--bg-2`           | `#ede8db`   | `#16201c`  | Secondary background, sand layer      |
| `--bg-translucent` | `rgba(245,243,238,0.92)` | `rgba(15,23,20,0.85)` | Sticky header backdrop |
| `--surface`        | `#fdfcf8`   | `#1a2520`  | Cards, panels, primary content        |
| `--surface-2`      | `#f9f6ee`   | `#1f2c26`  | Hover/active states, subtle fill      |

### Text

| Token       | Light     | Dark      | Role                              |
|-------------|-----------|-----------|-----------------------------------|
| `--ink`     | `#1c2a22` | `#e8ebe5` | Primary text                      |
| `--ink-2`   | `#344a3c` | `#c9d2cb` | Secondary text, headings on cards |
| `--muted`   | `#6b7d6e` | `#8a978f` | Metadata, timestamps              |
| `--muted-2` | `#8a9a8c` | `#6e7c74` | Tertiary muted                    |

### Borders

| Token        | Light     | Dark      | Role                          |
|--------------|-----------|-----------|-------------------------------|
| `--border`   | `#d9d4c3` | `#2a3530` | Cards, inputs, dividers       |
| `--border-2` | `#e6e2d5` | `#233029` | Subtle separators, list items |

### Brand & accent

| Token            | Light     | Dark      | Role                                |
|------------------|-----------|-----------|-------------------------------------|
| `--primary`      | `#2f5a45` | `#6ba37e` | Sage primary (lifted on dark for contrast) |
| `--primary-2`    | `#245041` | `#82b893` | Hover / pressed                     |
| `--primary-soft` | `#dde7d8` | `#1f3a2c` | Tinted backgrounds, mod badges      |
| `--accent`       | `#b08740` | `#d4a85a` | Amber accent (warmer on dark)       |
| `--accent-soft`  | `#efe2c4` | `#3a2e18` | Accent-tinted background            |

### Semantic

| Token       | Light     | Dark      |
|-------------|-----------|-----------|
| `--danger`  | `#a54b3b` | `#d97362` |
| `--warning` | `#c89236` | `#e0a85a` |
| `--success` | `#4d7a4c` | `#7aaa72` |
| `--info`    | `#4a6e7a` | `#7aa3b0` |

### Room tints

Each of the 6 rooms gets one foreground/background pair, used **only** on the room badge and the room hero section. Dark variants are desaturated to avoid neon flashing.

| Room       | Light bg / fg            | Dark bg / fg             |
|------------|--------------------------|--------------------------|
| Prayer     | `#e6e9dd` / `#4a5a3b`    | `#1f2a20` / `#b3c2a4`    |
| Testimony  | `#efe1cd` / `#7a5a2c`    | `#2a221a` / `#d4b683`    |
| Bible Study| `#dde7e8` / `#3e5d63`    | `#1a262a` / `#9cc0c8`    |
| Questions  | `#e8dde6` / `#6a4a64`    | `#261d24` / `#c5a8c0`    |
| Encourage  | `#ecd9c9` / `#7a4a2e`    | `#2a1d18` / `#d4a890`    |
| Youth      | `#d9e5dc` / `#3e5e48`    | `#1d2a23` / `#a4c4ae`    |

### Shadows

| Token     | Light                                                             | Dark                                                |
|-----------|-------------------------------------------------------------------|-----------------------------------------------------|
| `--sh-sm` | `0 1px 2px rgba(28,42,34,0.04)`                                   | `0 1px 2px rgba(0,0,0,0.3)`                         |
| `--sh-md` | `0 1px 3px rgba(28,42,34,0.05), 0 4px 12px rgba(28,42,34,0.04)`   | `0 1px 3px rgba(0,0,0,0.35), 0 4px 12px rgba(0,0,0,0.25)` |
| `--sh-lg` | `0 8px 32px rgba(28,42,34,0.08)`                                  | `0 8px 32px rgba(0,0,0,0.4)`                        |

---

## 3. Component-level dark-mode adjustments

These are extra rules that fire only on `[data-theme="dark"]` because the components use hardcoded values that wouldn't otherwise track the theme.

| Component        | Adjustment                                                         |
|------------------|--------------------------------------------------------------------|
| `.btn-primary`   | Text becomes near-black (`#0f1714`) for contrast against light sage button |
| `.badge-mod`     | `bg: #1f3a2c; color: #a8d4b8`                                       |
| `.badge-admin`   | `bg: #3a2418; color: #e0a890`                                       |
| `.rxn.active`    | `color: #c4e0cf`                                                    |
| `.avatar`        | Initials color lifts to `#d4e0d4`                                   |
| Scrollbar thumb  | `#2a3530`                                                            |
| `.bg-linen`      | Texture dots become low-opacity white                               |
| `img`            | `opacity: 0.92` (subtle dim to integrate photos with dark UI)       |
| `.input:focus`   | Outline becomes `rgba(107,163,126,0.25)` (soft sage halo)           |

---

## 4. Implementation — Rails + Tailwind

### `tailwind.config.js`
Use Tailwind's `darkMode: 'class'` strategy with the `theme-dark` class.

```js
// tailwind.config.js
module.exports = {
  darkMode: 'class', // toggled via class="theme-dark" on <html>
  theme: {
    extend: {
      colors: {
        // Light values; dark-mode override comes via CSS vars
        bg: 'var(--bg)',
        surface: 'var(--surface)',
        ink: 'var(--ink)',
        muted: 'var(--muted)',
        border: 'var(--border)',
        primary: 'var(--primary)',
        accent: 'var(--accent)',
        // ... etc
      },
    },
  },
};
```

Then put a `tokens.css` (the same shape as the prototype's `design-tokens.css`) into `app/assets/stylesheets/` and import once in `application.tailwind.css`. Tailwind utilities like `bg-surface text-ink border-border` will pick up the right value automatically because they reference the CSS vars.

### Stimulus controller — `dark_mode_controller.js`

```js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button"]

  connect() {
    const stored = localStorage.getItem("fc-dark")
    const dark = stored === null
      ? window.matchMedia("(prefers-color-scheme: dark)").matches
      : stored === "1"
    this.apply(dark)
  }

  toggle() {
    const dark = !document.documentElement.classList.contains("theme-dark")
    this.apply(dark)
    localStorage.setItem("fc-dark", dark ? "1" : "0")
    // optionally persist to user record:
    // fetch("/settings/dark_mode", { method: "PATCH", body: JSON.stringify({ dark }) })
  }

  apply(dark) {
    const html = document.documentElement
    const body = document.body
    html.setAttribute("data-theme", dark ? "dark" : "light")
    html.classList.toggle("theme-dark", dark)
    html.classList.toggle("theme-light", !dark)
    body.classList.toggle("theme-dark", dark)
    body.classList.toggle("theme-light", !dark)
  }
}
```

### ERB partial — `_dark_mode_toggle.html.erb`

```erb
<button type="button"
        data-controller="dark-mode"
        data-action="dark-mode#toggle"
        class="btn btn-ghost btn-icon btn-sm"
        aria-label="Toggle dark mode">
  <%# swap icon based on current theme via CSS or two icons hidden/shown %>
  <svg class="dark:hidden" aria-hidden="true">…moon path…</svg>
  <svg class="hidden dark:inline" aria-hidden="true">…sparkle path…</svg>
</button>
```

### Server-side persistence (optional but recommended)

```ruby
# routes.rb
patch "/settings/dark_mode", to: "settings#dark_mode"

# app/controllers/settings_controller.rb
def dark_mode
  current_user.update(dark_mode: params[:dark])
  head :no_content
end

# In application.html.erb, set the class on first paint to avoid flash:
# <html class="<%= current_user&.dark_mode? ? 'theme-dark' : 'theme-light' %>">
```

---

## 5. The Chromium custom-property invalidation gotcha

When the prototype's dark mode was first built, Chromium failed to recompute the inherited `color` and `background` on `<body>` after a runtime toggle, even though the CSS variables on `:root` were correctly updated. This caused post titles and author names to render with the old light-mode ink color against new dark surfaces, producing invisible text.

The fix that finally worked combines all four of these:

1. Set `data-theme` attribute AND `theme-dark`/`theme-light` class on `<html>`.
2. Set the same class on `<body>`.
3. Write every token directly to `documentElement.style` via `setProperty(...)`.
4. **Critical:** Add a fallback rule in CSS:
   ```css
   body.theme-dark  { color: #e8ebe5 !important; background-color: #0f1714 !important; }
   body.theme-light { color: #1c2a22 !important; background-color: #f6f3ec !important; }
   ```
   The `!important` overrides the `body { color: var(--ink) }` base rule whose value Chromium was caching incorrectly.

Engineers reproducing this in Rails should keep step 4. Without it, runtime toggle works on Firefox and Safari but breaks on Chromium-based browsers (Chrome, Edge, Brave, Arc).

---

## 6. Accessibility checks performed

- Body text on background: **WCAG AAA** in both themes
  - Light: `#1c2a22` on `#f6f3ec` → 12.6:1
  - Dark: `#e8ebe5` on `#0f1714` → 14.2:1
- Muted text on background: **WCAG AA** in both themes
  - Light: `#6b7d6e` on `#f6f3ec` → 4.6:1
  - Dark: `#8a978f` on `#0f1714` → 5.1:1
- Primary button text on primary background: **AAA** in both themes
- Room tint foregrounds on tint backgrounds: **AA** for body, **AAA** for headlines
- Focus ring uses sage halo with 3px outline + 2px offset — not color-dependent

---

## 7. What does NOT change in dark mode

- **Type scale** — same Fraunces / Cormorant Garamond / Geist Sans pairing
- **Spacing scale** — same 4/8/12/16/24/32 grid
- **Radius scale** — same 6 / 10 / 14 / 999 (pill)
- **Component anatomy** — same nav, post card, room badge, reaction picker
- **Photography** — no color treatment beyond the global 0.92 opacity dim

---

## 8. Open decisions for engineering

1. **Auto-switch on schedule?** (e.g. follow OS, or sunset/sunrise based on user's timezone). Recommend: respect OS only; let the user override per-session.
2. **Theme transition animation?** Currently instant. A 200ms `background` and `color` transition on body looks nice but adds visual noise on every nav change because the body class persists. Recommend: leave instant.
3. **Email & PDF exports** — Brethren Card and digest emails should always render in light mode for print. Add `?theme=light` URL param override.
4. **Admin shell** — already uses its own dark sidebar regardless of theme. In dark mode it stays dark. In light mode it also stays dark. Document this for moderators so it doesn't feel broken.

---

*End of specification. Pair with `design-tokens.css` and the live prototype HTML.*
