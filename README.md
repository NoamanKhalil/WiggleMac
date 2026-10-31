# Wiggle

Wiggle your mouse to summon an AI assistant right at your cursor. A spinning rainbow ring circles your pointer, and a small menu appears next to it. Pick **Chat**, **Screenshot**, **Voice** or **Workflow**. Wiggle again to close it.

## Features

- **Wiggle to open and close**: a few fast back-and-forth strokes (4–6 direction reversals within 0.9 s, depending on sensitivity) toggles the assistant. Small jitter, slow movement and drags are ignored.
- **Rainbow ring**: while Wiggle is open, a spinning rainbow ring circles your pointer. Your normal pointer always stays visible, on every display. The ring spins faster while Wiggle is capturing or answering.
- **Chat**: replies stream in, and follow-up questions continue the same conversation.
- **Screenshot**: captures the whole screen under your cursor and attaches it, so you can ask about what's on screen. Wiggle's own windows and the pointer are left out of the capture.
  - **Vision-capable models** get the image itself: Apple Intelligence, Claude, OpenAI, and Ollama vision models.
  - **Text-only models** get the text recognized in it by on-device OCR.
  - **Save** (the download button next to a screenshot) keeps it as a full-resolution PNG in the folder macOS uses for its own screenshots: the Desktop, unless you've changed it in the Screenshot app. Screenshots aren't saved unless you ask.
- **Voice**: speak your question. It's transcribed on your Mac and sent after a short pause. Saying **"screenshot"** (or "take a screenshot and …") captures the full screen, and anything else you say becomes the question.
- **Workflow**: record clicks, double-clicks, drags, scrolling and typing in any app, then replay them at the same spots on screen, as many times as you like.
  - Press **Record**: the ring turns red while Wiggle records, and a small bar shows how many steps it has. Press **Esc** (or the pause button) to pause, so you can do something without recording it, and again to resume; Esc itself is never recorded. Wiggle again (or press stop, or use the menu bar) to stop, then name the workflow, remove any stray steps, and save it.
  - Hover a workflow to rename it (the pencil, or double-click its name) or delete it.
  - **Change it with chat**: hover a workflow and click the speech bubble, then say what should change ("this one's for Sarah, a recruiter at Stripe", "remove the Esc presses"). The model can rewrite what the workflow types and remove steps, but not change its clicks. You see the full new text first; **Save as edited copy** keeps the original as recorded and saves the changes to "<name> (edited)", replaced each time you save, ready to **Run**. New text is typed with your keyboard layout's keys, at the rhythm you typed when recording.
  - Press play to run it. The ring spins while it runs, and a small bar shows its progress, out of the way of the spots the workflow clicks. Press **Esc** (or the pause button) to pause, and again to resume; the Esc doesn't reach the app you're in. Wiggle (or press stop) to stop.
  - Workflows replay at fixed screen coordinates, so keep windows where they were when you recorded.
  - Needs Accessibility permission. Keystrokes typed into password fields are never recorded (macOS withholds them). Workflows are saved on your Mac in `~/Library/Application Support/Wiggle/workflows.json`.
- **Text Wiggle** (iMessage through [Photon](https://photon.codes)): chat with Wiggle, change workflows and run them from your phone. See [Texting Wiggle](#texting-wiggle).
- **Settings** (menu bar → Settings…, or ⌘,): **General** (wiggle on or off, sensitivity, open at login, updates), **Models** and **Texting**. Models:
  - **Apple Intelligence**: Apple's on-device model.
  - **Local models through Ollama**: download from a list of small Mac-friendly models (Qwen, Gemma, Llama, Phi, DeepSeek R1, and vision models like Qwen VL and Moondream) or any model by name. Use or delete installed models from the same window.
  - **Your own API keys**: Claude (Anthropic) or OpenAI. Keys are stored in your Keychain.

## Requirements

- macOS 26 or later on Apple silicon. Screenshot questions with Apple Intelligence need macOS 27.
- Xcode 26 or later (Swift 6.2)
- For local models: [Ollama](https://ollama.com)

## Build & run

```sh
scripts/setup-signing.sh   # once: local signing identity so macOS remembers permissions across rebuilds
make run                   # builds build/Wiggle.app and opens it
make dmg                   # build/release/Wiggle-<version>.dmg to try on this Mac
swift test                 # unit tests
WIGGLE_INTEGRATION=1 swift test --filter IntegrationTests   # against local Ollama + Apple models
```

macOS asks for permissions the first time you use each feature:
- **Screen Recording**: Screenshot
- **Microphone and Speech Recognition**: Voice
- **Desktop (or your screenshots folder)**: saving a screenshot
- **Accessibility**: recording and running workflows

`setup-signing.sh` creates a self-signed certificate in its own keychain (`~/Library/Keychains/wiggle-signing.keychain-db`). It doesn't touch your login keychain. Without it, builds are signed ad-hoc and macOS forgets these permissions after every rebuild.

## Releasing

Other Macs only open Wiggle if it's signed with a Developer ID and notarized by Apple. One-time setup:

1. Join the [Apple Developer Program](https://developer.apple.com/programs/), then create a **Developer ID Application** certificate (Xcode › Settings › Accounts › Manage Certificates).
2. Save notarization credentials, using an [app-specific password](https://support.apple.com/102654):
   ```sh
   xcrun notarytool store-credentials wiggle-notary --apple-id YOU@example.com --team-id TEAMID
   ```
3. Back up the update-signing key. It's in your login Keychain as `wiggle`; without it, existing installs can never update again:
   ```sh
   .build/artifacts/sparkle/Sparkle/bin/generate_keys --account wiggle -x wiggle-sparkle-private.key
   ```
   Keep that file somewhere safe and private, not in this repo.

Then, for each release, raise `CFBundleShortVersionString` in `Resources/Info.plist`, commit, and run:

```sh
WIGGLE_FEED_URL=https://example.com/updates/appcast.xml make release
```

This builds `build/release/Wiggle-<version>.dmg`, notarizes the app and the DMG (which uploads them to Apple), and writes `build/release/updates/appcast.xml`. Upload both files next to each other at the feed URL's address yourself. The build number is the commit count, so it rises with every commit. Without `WIGGLE_FEED_URL`, the app has no update feed and never checks for updates.

## Privacy

- **Apple Intelligence and Ollama** run entirely on your Mac.
- **Updates**: release builds check the update feed for new versions. Dev builds never do.
- **Claude and OpenAI** receive only what you send them: your questions, and any screenshot you attach.

## Texting Wiggle

Settings → **Texting**: turn it on, and enter your Photon project ID, its secret (from your project's Settings at app.photon.codes) or, for Photon 2.0 projects at app.beta.photon.codes (IDs starting `pho_prj_`), a project API key (`pho_sk_…`, from the project's API keys page, allowed to read and send messages), and the number you'll text from. Photon 2.0 projects are checked for new texts every two seconds, so no public webhook address is needed. Wiggle runs the Photon bridge itself with your Mac's Node (22 or later; `brew install node`), shows whether it's connected, and stops it when you turn texting off or quit. The secret is kept in your Keychain and handed to the bridge directly, never written to a file.

Wiggle listens on 127.0.0.1 only, with a token it writes to `~/Library/Application Support/Wiggle/remote.json` (readable by you only, new on every start). Only texts from your number get through; others are ignored.

The bridge is `photon-bridge/`, bundled into the app by `make app` (after `npm install` there). To run it by hand instead, copy `.env.example` to `.env`, fill it in, and `npm start`; `npm run terminal` tries it by typing, with no Photon account.

What you can text:
- Anything: chat with the model chosen in Settings → Models.
- `workflows`: list them. `change <name or number>`, then what to change ("this one's for Sarah at Stripe"): the reply shows the exact new text. `save` keeps it as "<name> (edited)". `done` stops changing.
- `run <name or number>` (or just `run` after `save`): Wiggle lists what it will type and waits for `yes`, the very next message, within two minutes. It won't start without Accessibility permission or on a locked screen, and texts you when the run is over.
- `pause`, `resume`, `stop`, `status`, `help`.

Texts, and Wiggle's replies, go through Photon's servers. Runs still click at the recorded spots, so leave the windows where they were when you recorded.

## Project layout

```
Sources/Wiggle/
  main.swift                   app entry (menu bar / accessory app)
  AppDelegate.swift            wires detector → cursor ring → panel; menu bar
  Updater.swift                automatic updates (Sparkle)
  WiggleDetector.swift         shake detection
  ScreenLocator.swift          which display is under the pointer
  Settings.swift               preferences + ModelChoice
  Capture/Screenshot.swift     ScreenCaptureKit capture, JPEG encoding, OCR
  Capture/ScreenshotSaver.swift saves screenshots to the Mac's screenshots folder
  Voice/SpeechListener.swift   on-device speech-to-text with pause detection
  Voice/VoiceCommand.swift     "screenshot" voice command parsing
  Workflow/
    Workflow.swift             workflow model, recording → steps, step descriptions
    WorkflowRecorder.swift     records input in other apps; Accessibility check
    WorkflowPlayer.swift       replays a workflow by posting input
    WorkflowEditing.swift      chat changes: reading them from a reply, typing new text
    WorkflowStore.swift        saved workflows (JSON on disk)
  LLM/
    ChatSession.swift          backend protocol + selection
    AppleChatSession.swift     FoundationModels (on-device, image input on macOS 27)
    OllamaChatSession.swift    Ollama /api/chat streaming
    OllamaClient.swift         list / download / delete local models + catalog
    AnthropicChatSession.swift Claude Messages API (SSE streaming)
    OpenAIChatSession.swift    OpenAI Chat Completions (SSE streaming)
    Keychain.swift             API key storage
    HTTP.swift                 request + streaming helpers
  Remote/
    RemoteServer.swift         127.0.0.1-only server for the Photon bridge
    RemoteChat.swift           texting commands: list, change, save and run workflows
    PhotonBridge.swift         runs the bundled Photon bridge with the Mac's Node
    Texting.swift              texting on/off and Photon details
  UI/
    PromptModel.swift          chooser / chat / screenshot / voice state
    PromptPanel.swift          floating panel views
    ModelsWindow.swift         Models tab: Apple, Ollama, Claude, OpenAI
    CursorGlow.swift           rainbow ring around the pointer
    SettingsWindow.swift       Settings window: General, Models and Texting tabs
    TextingWindow.swift        Texting tab
    WorkflowControls.swift     pause / resume / stop bar while a workflow runs
    Palette.swift              gradient colors
Resources/Info.plist           bundle metadata + permission strings
Resources/Wiggle.entitlements  hardened-runtime entitlements (microphone)
scripts/build-app.sh           SwiftPM build → signed .app bundle with Sparkle
scripts/release.sh             DMG, notarization and update feed
scripts/setup-signing.sh       local code-signing identity
```
