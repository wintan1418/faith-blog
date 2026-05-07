# frozen_string_literal: true

# Pre-baked rich-text bodies for admin broadcasts. Returned as raw HTML so
# Trix loads them straight into the editor — admin can then tweak before
# sending.
module BroadcastTemplates
  module_function

  # rubocop:disable Layout/LineLength
  def launch_announcement_html
    <<~HTML.html_safe
      <p><strong>Friends,</strong></p>
      <p>Brethreign has grown a lot in the last few weeks. Here's everything you can do now &mdash; with a few sketches of how it looks so you know what to look for.</p>

      <h2>🪶 Just breathe &mdash; titles are optional</h2>
      <p>You no longer need a title to share a thought. Open the composer, type, hit <em>Breathe</em>. The card now reads like a Twitter post when there's no title:</p>
      <pre>┌──────────────────────────────────────────────┐
│ wintan · @wintan · 2m · Sermons · Prayer 🙏 │
│                                              │
│ Resting in grace today, brothers. The Lord   │
│ has been so faithful through this week.      │
│                                              │
│ 🤍 12   💬 4   🔁 2   🙏 Join chain · 6     │
└──────────────────────────────────────────────┘</pre>
      <p>If you <em>do</em> want a title (for a thread, a sermon note, etc.), the title field is still there &mdash; it just doesn't block you anymore.</p>

      <h2>📝 Drafts</h2>
      <p>Click <strong>Save draft</strong> in the composer to park a half-finished breath. Find them later under <strong>Drafts</strong> in the side menu. Edit, finish, publish whenever you're ready.</p>

      <h2>📖 Inline scripture &mdash; just type the reference</h2>
      <p>Type any Bible reference inside a breath or comment and it auto-links. Hover (or tap on mobile) to read the verse without leaving the page:</p>
      <pre>"... and we know that all things work together for good
 to them that love God" &mdash; Romans 8:28
                                  ↑
                          hover this  →  ┌────────────────────────┐
                                          │ Romans 8:28 (KJV)      │
                                          │                        │
                                          │ And we know that all   │
                                          │ things work together   │
                                          │ for good to them that  │
                                          │ love God ...           │
                                          └────────────────────────┘</pre>
      <p>Works for Old Testament, New Testament, and ranges (e.g. <em>Psalm 23:1-3</em>).</p>

      <h2>🔥 Streaks &mdash; daily breath rhythm</h2>
      <p>Breathe at least one published post a day and your streak ticks up. Skip a day and it resets. Your current streak shows under your username in the feed. The longest streak you ever held is also tracked.</p>

      <h2>🙏 Prayer chains &amp; "Answered" status</h2>
      <p>When you compose, tick <strong>🙏 Prayer request</strong>. Your breath shows up with a Prayer chip and a <em>Join chain</em> button anyone can tap:</p>
      <pre>┌──────────────────────────────────────────────┐
│ Prayer 🙏  · 12 praying                      │
│                                              │
│ Pray for my mum's surgery on Friday morning. │
│                                              │
│ [ 🙏 Join chain · 12 ]   [ 🌟 Mark answered ]│  ← author-only button
└──────────────────────────────────────────────┘</pre>
      <p>When the prayer is answered, hit <strong>🌟 Mark answered</strong> &mdash; the card flips gold, everyone in the chain gets a notification:</p>
      <p><em>"A prayer you joined was just marked answered 🌟"</em></p>

      <h2>📚 Reading plans</h2>
      <p>We've added three short plans you can start any day:</p>
      <ul>
        <li><strong>30 Days in the Psalms</strong> &mdash; one psalm a day for a month.</li>
        <li><strong>21 Days through John</strong> &mdash; one chapter a day, three weeks.</li>
        <li><strong>Proverbs 31</strong> &mdash; a chapter a day for a month.</li>
      </ul>
      <p>Visit <strong>Reading plans</strong> in the menu, pick one, and a daily check-in card lands in your feed sidebar each morning. Tap <strong>Mark today done</strong> to advance. Hover any reference to read it inline (same scripture popup as above).</p>

      <h2>🕊️ AI gentleness check</h2>
      <p>While composing, click <strong>🕊️ Check tone</strong>. We read your draft and give you a single line of feedback &mdash; never blocking, just a nudge:</p>
      <pre>┌──────────────────────────────────────────────┐
│ 🕊️ Reads gently                              │
│ Tone is patient and personal. Send it.       │
└──────────────────────────────────────────────┘

(or, if it's heated:)

┌──────────────────────────────────────────────┐
│ ⚠️ Could land hard                           │
│ This may read as contempt. Would softer      │
│ wording carry the same truth?                │
│                                              │
│ SOFTER REFRAME                               │
│ ┃ "I disagree with that approach because..." │
└──────────────────────────────────────────────┘</pre>
      <p>You can ignore the suggestion and post anyway &mdash; the check is for you, not over you.</p>

      <h2>✨ AI scripture suggester</h2>
      <p>Click <strong>📖 Suggest scripture</strong> in the composer. Based on what you wrote, you'll get up to 3 verses with a one-line reason:</p>
      <pre>📖 Suggested scripture
 • Philippians 4:6-7  &mdash; trade anxiety for peace through prayer
 • Psalm 34:4         &mdash; God answers when we seek Him in fear</pre>
      <p>Hover any reference to read it before you fold it in.</p>

      <h2>📲 Install Brethreign as an app (PWA)</h2>
      <p>On phone or laptop, open <strong>Settings &rarr; Notifications</strong> and tap <strong>Install Brethreign as an app</strong>. It pins to your home screen / dock with the icon, opens full-screen, and works in flaky network conditions.</p>

      <h2>🔔 Browser push notifications</h2>
      <p>Same panel, the button right next to it: <strong>🔔 Turn on push</strong>. Allow the browser prompt and you'll get a tap-on-the-shoulder when:</p>
      <ul>
        <li>Someone replies, reacts, or mentions you.</li>
        <li>Someone joins or answers your prayer chain.</li>
        <li>A connection request lands.</li>
        <li>A DM arrives.</li>
      </ul>
      <p>Per-device. Turn it on once on your phone and once on your laptop &mdash; or just on the device you actually want pinging you.</p>

      <h2>📬 Sunday morning digest</h2>
      <p>Every Sunday at 8 a.m., we send you a clean little summary of:</p>
      <ul>
        <li>Top breaths from people you follow this week.</li>
        <li>Your own breath count + current streak.</li>
        <li>Any prayer chains you joined that are still pending.</li>
      </ul>
      <p>Don't want it? One-click unsubscribe in every email.</p>

      <h2>🖼️ DM images &amp; 🎙️ voice notes</h2>
      <p>In any conversation:</p>
      <ul>
        <li>Click the <strong>image icon</strong> to send up to 4 photos. Inline thumbnails preview before you hit send. The recipient sees them as a tidy grid.</li>
        <li>Click the <strong>🎙️ microphone</strong> to record a voice note. Tap once to start (button pulses red), tap again to stop. A "Voice note ready · 7s" pill shows up &mdash; you can discard or send. The recipient sees a built-in audio player in the bubble.</li>
      </ul>

      <h2>A small word</h2>
      <p>Brethreign is meant to be a quiet, sturdy room for the body of Christ. Most of these features (gentleness check, prayer chains, scripture inline) exist to make conversation gentler and more rooted in the Word. None of them are mandatory &mdash; they're just available.</p>

      <p>Breathe whenever you can.</p>
      <p>&mdash; The Brethreign team</p>
    HTML
  end
  # rubocop:enable Layout/LineLength
end
