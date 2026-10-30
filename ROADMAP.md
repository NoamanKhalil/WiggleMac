# Wiggle roadmap

Last updated: October 30, 2026

**Where we are.** The Mac app works: wiggle to open, the rainbow ring around the pointer, Chat, Screenshot and Voice, four ways to run models (Apple Intelligence, Ollama, Claude, OpenAI), and saving screenshots. The landing page is written (`site/index.html`) and pricing is set: Free, Pro at $19 once, and Teams at $15 per Mac. Nobody can download or pay yet.

**The plan.** Get a signed beta to testers, launch v1.0 with Free and Pro in January, make Pro worth more, open more sales channels, then decide whether a hosted-AI subscription and team plans are worth building.

## At a glance

| Phase | When | Goal | Ships |
|---|---|---|---|
| 0. Foundation | Oct 19 – Oct 30, 2026 | A build anyone can install safely | Signed, notarized beta with automatic updates |
| 1. Private beta | Nov 2 – Nov 27 | Learn what people actually use | 20–50 testers, first-run guide, top fixes |
| 2. Launch v1.0 | Nov 30 – Jan 15, 2027 | First paying customers | Licensing, Pro trial, payments, public launch |
| 3. Make Pro worth more | Jan – Feb 2027 | More people buy Pro | Quick actions, history, partial screenshots |
| 4. More channels | Mar – Apr 2027 | Reach beyond our own site | Setapp, Mac App Store |
| 5. Wiggle Cloud | Decide in May, build May – Jul 2027 | Recurring revenue | Optional hosted-model subscription |
| 6. Teams | Aug – Oct 2027 | Larger deals | Volume licenses, settings IT can manage |

Dates assume steady part-time work. Move them once we know the team's real capacity.

## Phase 0: Foundation (Oct 19 – Oct 30)

**Goal:** a build people can install without security warnings, and that updates itself.

**Status, Oct 30: the engineering is done. Four setup steps remain, and only the team can do them.**

Done:
- Git works on the dev Mac (Homebrew's git), and all work is committed on the `phase-0-foundation` branch.
- `make dmg` packages the app as a DMG. `make release` signs with a Developer ID and the hardened runtime, notarizes and staples the app and the DMG, and writes the update feed.
- Sparkle 2.10.1 is built in for automatic updates, with a "Check for Updates…" menu item. The update-signing key is in the login Keychain (`wiggle`).

Waiting on the team:
- [ ] Join the Apple Developer Program ($99 a year) and create a Developer ID Application certificate.
- [ ] Save notarization credentials (README › Releasing). Notarizing uploads each build to Apple.
- [ ] Back up the update-signing key somewhere safe and private.
- [ ] Choose where the DMG and update feed live (for example, wigglemac.com/updates/), then run `make release` and upload them.
- [ ] Set up email for support@wigglemac.com: the domain has no mail records, so the landing page's "Get the beta" emails bounce.

**Done when:** a fresh Mac installs the beta with no warnings, and a new version installs itself.

## Phase 1: Private beta (Nov 2 – Nov 27)

**Goal:** find out which modes people use, whether Wiggle opens by accident, and what breaks.

- First-run window: how to wiggle, which permissions Wiggle asks for and why, and which model it will use. Suggest turning off macOS's "Shake mouse pointer to locate", which balloons the pointer on every wiggle.
- Send builds to 20–50 people from the waitlist, with a short survey after their first week.
- Finish the remaining audit items:
  - Show an error when saving an API key fails.
  - Hide reasoning models' "thinking" text from answers.
  - Stop resending old screenshots with every follow-up question.
- Test on multiple displays, full-screen apps, and Macs without Apple Intelligence.

**Done when:** a week with no crashes, accidental opens are rare, and we know the top three requests.

## Phase 2: Launch v1.0 (Nov 30 – Jan 15, 2027)

**Goal:** people can find, try and buy Wiggle without talking to us.

- Licensing that needs no server: license keys signed with our private key and checked offline by the app, so "no servers" stays true.
- The Free and Pro split: Apple Intelligence stays free. Ollama, Claude and OpenAI become Pro.
- A 14-day Pro trial. The landing page already promises one.
- Payments through a merchant of record such as Paddle or Lemon Squeezy, which emails the license key and handles sales tax worldwide.
- Landing page: a real download link, working buy buttons, a privacy policy, terms and a refund policy.
- Launch the week of January 11, after the holidays: Product Hunt, Show HN, r/macapps, and Mac newsletters and blogs.

**Done when:** the first customers have paid, and refunds stay low.

## Phase 3: Make Pro worth more (Jan – Feb 2027, v1.1 to v1.3)

**Goal:** more active users buy Pro with each release. Pick from this list based on beta requests:

- Quick actions in the menu: Explain, Translate, Summarize, Fix grammar, and custom prompts.
- A searchable history of past answers, stored on the Mac.
- Screenshot part of the screen, or a chosen display.
- A keyboard shortcut as an alternative to wiggling.
- Copy or paste an answer straight into the app you're in.

**Done when:** the share of users who buy Pro rises release over release.

## Phase 4: More channels (Mar – Apr 2027)

**Goal:** sell beyond our own site.

- **Setapp:** apply. It pays based on how much people use the app and doesn't stop us selling directly.
- **Mac App Store:** now possible, since the private cursor trick is gone. It needs sandboxing (saving screenshots to a folder the user picks) and App Store purchases instead of license keys. Apple takes 15% under its Small Business Program.
- Translate the app and site into the top languages from beta and sales data.

**Done when:** Wiggle is on sale in at least one place besides our site.

## Phase 5: Wiggle Cloud (decide in May, build May – Jul 2027)

**Decide in May.** Build this only if launch data shows many users have no API key and want better answers than Apple Intelligence gives.

If yes:

- A subscription, roughly $6–10 a month, with strong hosted models and no keys or setup.
- A small server that passes requests to the model providers and keeps nothing, plus Sign in with Apple, usage metering and fair-use limits.
- Clearly opt-in. Free and Pro stay fully on the Mac.
- Before setting the price, measure what each question costs us (screenshots cost the most) and keep a healthy margin after AI costs.

**Done when:** subscribers stay past their second month and margins hold.

## Phase 6: Teams (Aug – Oct 2027)

**Goal:** larger deals with companies that need private AI.

- Volume licenses ($15 per Mac from 5 Macs), one invoice, and moving licenses between people.
- Settings IT can push to every Mac: allow only on-device models, or turn off cloud models or screenshots.
- A one-page security overview for IT reviews: what leaves the Mac, and what never does.

**Done when:** the first company buys 25 or more seats.

## How we measure, without tracking anyone

Wiggle has no analytics, and it stays that way. We use:

- Downloads, from wherever the DMG is hosted.
- Sales, trials and refunds, from the payment provider.
- Beta surveys and support email.
- An opt-in "Send feedback" button that attaches logs only when the user chooses.

## Risks

| Risk | What we do about it |
|---|---|
| Apple builds the same thing into macOS | Lean on what Apple won't do: the gesture, choice of models, and privacy |
| A macOS update breaks mouse monitoring or screen capture | Test every macOS beta, and keep a fix release ready |
| App Store review rejects the screen recording | Direct sales stay the main channel |
| Hosted AI costs outgrow subscription revenue | Track cost per question, and set fair-use limits |
| People open Wiggle by accident and switch it off | Sensitivity settings, the first-run guide, and beta data |
