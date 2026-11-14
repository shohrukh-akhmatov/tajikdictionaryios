# Development Roadmap (Tajik–Russian–English Offline Dictionary)

> Shared product roadmap for both native apps (`tajikdictionaryandroid` and `tajikdictionaryios`).

## Phase 0 — Core Foundation & Seed Dictionary (MVP)
- [x] Shared CSV → SQLite build pipeline (`tools/build_dictionary.py`) with 200+ core seed entries
- [x] Cross-platform `TextNormalizer` (14 test vectors) and `LanguageDetector`
- [x] Bidirectional `TJK ⇄ RUS` / `TJK ⇄ ENG` modes with mixed-language inline search & `[TJ]`/`[RU]`/`[EN]` badges
- [x] On-screen Tajik quick-insert letter bar (`ғ ӣ қ ӯ ҳ ҷ`)
- [x] Entry Detail with grouped tappable translations, examples, Copy, Share, Favorite, and offline RU/EN TTS
- [x] Word of the Day (deterministic offline), Favorites, History (max 200), Settings, Light/Dark theme, `en`/`ru`/`tg` UI localization

## Phase 1 — Smart Search, Topics & 5k–10k Lexicon Readiness
- [x] CSV quality linter & statistics validator in `tools/build_dictionary.py --check` (duplicate detection, POS validation, sense formatting, coverage report)
- [x] **Tajik & Russian Stemming / Inflection Hints** (recognizes `ме-`, `на-`, `би-`, `-ҳо`, `-он`, `-ро`, `-ам/-ат/-аш` so searching `меравам` finds `рафтан`)
- [x] **Fuzzy / Typo Fallback** (edit-distance-1 + phonetic similarity when exact/prefix search returns no direct hits)
- [x] **Topic / Category Browser** (`greetings`, `food`, `family`, `home`, `nature`, `travel`, `health`, `education`, `verbs`, `numbers`, etc.)
- [ ] Scale `data/source/dictionary.csv` to **5,000 → 10,000** curated Tajik entries with frequency rankings and examples

## Phase 2 — Learning & Study Tools
- [ ] **Offline Flashcard Quiz (SM-2 Spaced Repetition)** powered by Saved words or Topic packs, with flip cards, streak tracking, and persistent study progress
- [ ] **TTS Speed Toggle** (`0.75×` / `1.0×`) + **Entry Font Size** setting (`Small` / `Medium` / `Large`)
- [ ] **Tajik Alphabet & Grammar Quick Reference** sheet (letters `ғ ӣ қ ӯ ҳ ҷ`, verb stem patterns, ezafe `-и`)
- [ ] Optional downloadable native Tajik audio pack (Opus/AAC) for top 2,000–3,000 words

## Phase 3 — OS Integrations & Power Features
- [ ] **Home Screen Widget** showing Word of the Day (Android AppWidget / iOS WidgetKit)
- [ ] **Favorites Export / Import (JSON)** so users can back up or transfer saved words across devices
- [ ] **System Quick Lookup** polish (Android `ACTION_PROCESS_TEXT` live intent handling; iOS `CoreSpotlight` indexing / Share Extension)
- [ ] Offline Camera OCR Lookup (ML Kit on Android / VisionKit on iOS)

## Phase 4 — Store Release & OTA Lexicon Updates
- [ ] Over-the-air lightweight SQLite delta/manifest update check (keeping user data untouched in Room / SwiftData)
- [ ] Community word submission & correction pipeline
- [ ] Google Play, RuStore, and Apple App Store production releases
