### Hi, I'm Jon 👋

I'm building **[Moby](https://github.com/MobyReader)** — an AI-native ebook
reader for iOS, currently in open beta on TestFlight.

**What it does**
- 📖 Imports epubs and presents them as tap-to-advance, sentence-sized reading units
- 🤖 A Claude-powered companion you can chat with about the book — spoiler-gated
  to exactly where you've read
- 🎧 Word-synced TTS narration with a reading dot that follows the audio
- 🔄 Two-way reading-position sync with KOReader e-readers
  ([public plugin](https://github.com/MobyReader/moby-koreader))
- 🧠 On-device AI (Apple Foundation Models) for zero-cost library descriptions

**How it's built**
SwiftUI · `@Observable` architecture · a pure, golden-tested pagination and
chunking core · BM25 retrieval on-device · cache-optimized Claude prompting ·
AVFoundation gapless audio · 40+ Swift Testing suites

📫 jonluongo2@gmail.com
