# Brethreign AI Moderation and Assistant Plan

This document captures the proposed AI direction for Brethreign so it can be reviewed, refined, and implemented in phases.

## Goals

Brethreign should use AI to protect the community, help moderators move faster, and make the platform feel intelligent without replacing human judgment.

The first priority should be safety and moderation. The second priority should be helpful community features such as suggestions, summaries, and discovery.

## Core Principles

- AI should assist moderation, not secretly punish users without review.
- Serious enforcement actions should have logs, reasons, and an appeal path.
- The system should be conservative around faith discussions because people may share pain, doubt, trauma, prayer requests, or sensitive testimony.
- The AI should flag risk and recommend action; admins/moderators should make final decisions for suspensions and bans.
- Every AI decision should be explainable enough for an admin to understand why something was flagged.
- Private messages need stronger privacy rules than public posts. Any AI review of inbox content should be clearly disclosed in the privacy policy.

## What The AI Should Watch For

### High-Severity Content

These should be flagged immediately and placed in a moderation queue:

- Threats of violence or harm.
- Self-harm or suicide language.
- Sexual exploitation or abuse.
- Hate or dehumanizing attacks against protected groups.
- Harassment, stalking, or repeated targeted abuse.
- Scams, impersonation, phishing, or financial manipulation.
- Explicit adult content.
- Doxxing or sharing private personal data.

### Community-Specific Issues

These are important for Brethreign specifically:

- Spiritual manipulation: using faith language to pressure, shame, exploit, or control someone.
- Predatory “prophecy,” miracle-money, seed-money, or fake deliverance claims.
- Manipulative fundraising.
- Dangerous medical advice presented as spiritual instruction.
- Aggressive theological fights that become personal attacks.
- Fake testimonies used to deceive users.
- Spam accounts posting repetitive religious content, links, or invitations.

### Lower-Severity Content

These should usually be soft-flagged:

- Heated language.
- Off-topic posting.
- Duplicate posts.
- Low-effort spam.
- Misleading claims.
- Content that may need a room change.
- Content that may need a content warning.

## Suggested AI Features

### 1. AI Moderation Queue

Create a moderation queue where flagged posts, comments, reports, and possibly messages appear.

Each queue item should show:

- Content preview.
- Author.
- Risk category.
- Severity score.
- AI explanation.
- Suggested action.
- Existing user history.
- Moderator decision buttons.

Possible moderator actions:

- Approve.
- Hide content.
- Ask user to edit.
- Move to another room.
- Warn user.
- Temporarily restrict posting.
- Suspend account.
- Ban account.

### 2. User Risk Score

Maintain a private moderation risk profile per user.

Inputs:

- Number of flagged posts.
- Number of confirmed violations.
- Number of dismissed flags.
- Reports from other users.
- Spam-like behavior.
- Message abuse reports.
- Account age.

This should not be visible to normal users.

Suggested levels:

- `clear`
- `watch`
- `restricted`
- `suspended`
- `banned`

### 3. Automated Soft Actions

The AI can safely do some low-risk actions automatically:

- Add content warning.
- Temporarily hide obviously spammy posts pending review.
- Rate-limit suspicious new users.
- Prevent duplicate posts.
- Send post to moderation queue before publishing.
- Suggest room/category correction.

Avoid fully automatic permanent bans at the beginning.

### 4. AI Post Pre-Check

Before a user publishes, AI can quietly check the content.

If risky, show a friendly warning:

> This may come across as harsh or unsafe. Please review before posting.

Possible pre-check outcomes:

- Allow.
- Suggest edit.
- Require moderation review.
- Block obvious abuse.

### 5. AI Report Assistant

When a user reports a post, AI can help classify the report:

- Harassment.
- Spam.
- False teaching/manipulation concern.
- Dangerous advice.
- Sexual content.
- Privacy violation.
- Other.

It can also summarize why the report may matter for moderators.

### 6. Moderator Copilot

For admins and moderators:

- Summarize long report threads.
- Compare user history.
- Draft warning messages.
- Suggest fair enforcement level.
- Explain why a post might violate guidelines.
- Find similar previous incidents.

### 7. Community Discovery AI

After moderation is stable, add user-facing AI:

- “Who to follow” based on rooms, interests, and mutual connections.
- Suggested rooms based on post history.
- Related posts and resources.
- Weekly community summary.
- Prayer request digest.
- Scripture/resource suggestions for posts.
- Better search with semantic matching.

### 8. AI Writing Help

Optional user-facing helper:

- Make this post clearer.
- Make this gentler.
- Turn this testimony into a better title.
- Suggest tags.
- Suggest room.
- Summarize long posts.

This should never fake spirituality or write manipulative religious content.

## Recommended Architecture

### Phase 1: Store Moderation Signals

Add database tables:

- `ai_moderation_reviews`
- `moderation_actions`
- `user_risk_profiles`

`ai_moderation_reviews` fields:

- `reviewable_type`
- `reviewable_id`
- `user_id`
- `status`
- `severity`
- `category`
- `score`
- `summary`
- `raw_response`
- `model`
- `reviewed_at`

`moderation_actions` fields:

- `user_id`
- `moderator_id`
- `action_type`
- `reason`
- `source`
- `expires_at`

`user_risk_profiles` fields:

- `user_id`
- `risk_level`
- `risk_score`
- `confirmed_violations_count`
- `dismissed_flags_count`
- `last_flagged_at`

### Phase 2: Async AI Review Job

Use background jobs:

- `AiModerationReviewJob`
- `AiUserRiskRefreshJob`
- `AiDigestJob`

Trigger AI reviews after:

- Post creation.
- Comment creation.
- Report creation.
- Message report.
- Profile bio update.

Do not block normal posting unless the user is new, restricted, or the content looks highly risky.

### Phase 3: Admin Moderation UI

Add admin pages:

- `/admin/moderation`
- `/admin/moderation/:id`
- `/admin/users/:id/risk`

The UI should show AI flags clearly but not make them look like final truth.

### Phase 4: Enforcement Rules

Start with these rules:

- High-severity content: hide pending review.
- Medium-severity content: publish but queue for review.
- Low-severity content: publish and log.
- Repeated confirmed violations: restrict or suspend.
- Spam confidence above threshold: auto-hide pending review.

### Phase 5: User-Facing AI

Only after moderation is stable:

- Who to follow.
- Related posts.
- Suggested resources.
- Better search.
- Writing help.

## LangChain / AI Layer Suggestion

Use a clean service layer so the app is not locked into one AI provider.

Suggested Ruby structure:

- `app/services/ai/moderation/client.rb`
- `app/services/ai/moderation/policy.rb`
- `app/services/ai/moderation/reviewer.rb`
- `app/services/ai/moderation/risk_scorer.rb`
- `app/jobs/ai_moderation_review_job.rb`

The service should return structured JSON:

```json
{
  "safe": true,
  "severity": "low",
  "categories": ["heated_language"],
  "score": 0.21,
  "summary": "The post is emotionally intense but does not appear abusive.",
  "recommended_action": "allow"
}
```

LangChain can be useful later if we add:

- Retrieval over community guidelines.
- Retrieval over previous moderation decisions.
- Semantic search over posts/resources.
- Multi-step agent flows for admin summaries.

For the first moderation version, a simpler structured AI call is probably better than a full agent.

## Important Product Decisions

Before implementation, decide:

- Should AI review private messages by default, only reported messages, or never?
- Should high-risk posts be hidden before a human sees them?
- What should users see when their post is held for review?
- How long should warnings/restrictions last?
- Can users appeal moderation actions?
- Should moderators see raw AI output or only the summary?
- Should the AI use Christian community-specific policy language or neutral platform-safety language?

## Suggested First Build

Build the smallest useful version:

1. Add moderation review model/table.
2. Add AI review job for posts and comments.
3. Add admin moderation queue.
4. Show severity, category, summary, and recommended action.
5. Allow admin to approve, hide, warn, or suspend.
6. Log every moderator decision.
7. Add tests around queue creation and moderator actions.

## Later Enhancements

- AI “who to follow.”
- AI post tag suggestions.
- AI room suggestions.
- AI weekly community digest.
- AI resource recommendations.
- AI duplicate/spam clustering.
- AI toxicity trend dashboard.
- AI-assisted onboarding for new users.
- AI-generated moderator summaries.

## Risk Notes

- False positives can damage trust, especially around sensitive testimony and prayer requests.
- False negatives can allow abuse, scams, or manipulation to spread.
- AI costs can rise quickly if every message/post is reviewed synchronously.
- Privacy expectations must be clear.
- Human moderators still need strong tools, not just AI labels.

## Recommendation

Start with AI-assisted moderation, not AI-controlled moderation.

The first version should flag and organize risk for admins. Once we trust the review quality, we can add soft automatic actions like holding spam or hiding extremely high-risk posts pending review.

After the moderation foundation is stable, then build the community intelligence features: who to follow, related posts, suggested rooms, better search, and writing support.
