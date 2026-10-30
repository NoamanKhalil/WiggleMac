# Wiggle

Wiggle your mouse to summon an AI assistant right at your cursor. A spinning rainbow ring circles your pointer, and a small menu appears next to it. Pick **Chat**, **Screenshot** or **Voice**. Wiggle again to close it.

## Features

- **Wiggle to open and close**: a few fast back-and-forth strokes (4–6 direction reversals within 0.9 s, depending on sensitivity) toggles the assistant. Small jitter, slow movement and drags are ignored.
- **Rainbow ring**: while Wiggle is open, a spinning rainbow ring circles your pointer. Your normal pointer always stays visible, on every display. The ring spins faster while Wiggle is capturing or answering.
- **Chat**: replies stream in, and follow-up questions continue the same conversation.
- **Screenshot**: captures the whole screen under your cursor and attaches it, so you can ask about what's on screen. Wiggle's own windows and the pointer are left out of the capture.
  - **Vision-capable models** get the image itself: Apple Intelligence, Claude, OpenAI, and Ollama vision models.
  - **Text-only models** get the text recognized in it by on-device OCR.
  - **Save** (the download button next to a screenshot) keeps it as a full-resolution PNG in the folder macOS uses for its own screenshots: the Desktop, unless you've changed it in the Screenshot app. Screenshots aren't saved unless you ask.
- **Voice**: speak your question. It's transcribed on your Mac and sent after a short pause. Saying **"screenshot"** (or "take a screenshot and …") captures the full screen, and anything else you say becomes the question.
- **Models window** (menu bar → Models…):
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
swift test                 # unit tests
WIGGLE_INTEGRATION=1 swift test --filter IntegrationTests   # against local Ollama + Apple models
```

macOS asks for permissions the first time you use each feature:
- **Screen Recording**: Screenshot
- **Microphone and Speech Recognition**: Voice
- **Desktop (or your screenshots folder)**: saving a screenshot

`setup-signing.sh` creates a self-signed certificate in its own keychain (`~/Library/Keychains/wiggle-signing.keychain-db`). It doesn't touch your login keychain. Without it, builds are signed ad-hoc and macOS forgets these permissions after every rebuild.

## Privacy

- **Apple Intelligence and Ollama** run entirely on your Mac.
- **Claude and OpenAI** receive only what you send them: your questions, and any screenshot you attach.

## Project layout

```
Sources/Wiggle/
  main.swift                   app entry (menu bar / accessory app)
  AppDelegate.swift            wires detector → cursor ring → panel; menu bar
  WiggleDetector.swift         shake detection
  ScreenLocator.swift          which display is under the pointer
  Settings.swift               preferences + ModelChoice
  Capture/Screenshot.swift     ScreenCaptureKit capture, JPEG encoding, OCR
  Capture/ScreenshotSaver.swift saves screenshots to the Mac's screenshots folder
  Voice/SpeechListener.swift   on-device speech-to-text with pause detection
  Voice/VoiceCommand.swift     "screenshot" voice command parsing
  LLM/
    ChatSession.swift          backend protocol + selection
    AppleChatSession.swift     FoundationModels (on-device, image input on macOS 27)
    OllamaChatSession.swift    Ollama /api/chat streaming
    OllamaClient.swift         list / download / delete local models + catalog
    AnthropicChatSession.swift Claude Messages API (SSE streaming)
    OpenAIChatSession.swift    OpenAI Chat Completions (SSE streaming)
    Keychain.swift             API key storage
    HTTP.swift                 request + streaming helpers
  UI/
    PromptModel.swift          chooser / chat / screenshot / voice state
    PromptPanel.swift          floating panel views
    ModelsWindow.swift         model manager window
    CursorGlow.swift           rainbow ring around the pointer
    Palette.swift              gradient colors
Resources/Info.plist           bundle metadata + permission strings
scripts/build-app.sh           SwiftPM build → signed .app bundle
scripts/setup-signing.sh       local code-signing identity
```
