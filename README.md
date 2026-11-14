# Tajik Dictionary — iOS (TJK ⇄ RUS / TJK ⇄ ENG)

An **offline-first** Tajik–Russian–Tajik and Tajik–English–Tajik dictionary app built with **Swift 6, SwiftUI, SQLite3, SwiftData, and `@Observable`**.

## Key Features
* **100% Offline SQLite3 Lexicon:** Instant prefix & exact-match search with zero internet required.
* **Two Bidirectional Modes (`TJK ⇄ RUS` & `TJK ⇄ ENG`):** Type in either language of the active mode; every result row displays a colored `[TJ]`, `[RU]`, or `[EN]` badge.
* **Tajik Keyboard Folding:** Typing `хурдан` on a Russian keyboard finds `хӯрдан` (`ғ→г`, `қ→к`, `ҳ→х`, `ҷ→ч`, `ӣ→и`, `ӯ→у`).
* **On-Screen Tajik Letter Bar:** One-tap `ғ ӣ қ ӯ ҳ ҷ` buttons right under the search bar.
* **Cross-Mode Detection:** Typing English while in `TJK ⇄ RUS` offers a one-tap switch to `TJK ⇄ ENG`.
* **Entry Detail:** Tappable cross-linked translations, usage notes, trilingual examples, Copy, Share, Favorite, and offline Russian/English `AVSpeechSynthesizer` pronunciation.
* **Saved & History + Word of the Day:** Stored in SwiftData separately from the read-only `dictionary.sqlite` bundle so user data survives dictionary updates.

## Updating the Word Database (5k / 10k Words)
All words live in [`data/source/dictionary.csv`](data/source/dictionary.csv). After editing or expanding it:

```bash
python3 tools/build_dictionary.py --self-test
python3 tools/build_dictionary.py
```

This regenerates `TajikDictionary/Resources/dictionary.sqlite` automatically.

## Docs
* [`docs/DATA_AND_SEARCH.md`](docs/DATA_AND_SEARCH.md) — SQLite schema, normalization spec, and search queries
* [`docs/FEATURES_AND_UI.md`](docs/FEATURES_AND_UI.md) — UI wireframes, color palette, and feature matrix
* [`docs/ROADMAP.md`](docs/ROADMAP.md) — Detailed multi-phase roadmap

## Build & Test

```bash
xcodebuild -project TajikDictionary.xcodeproj -scheme TajikDictionary \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```
