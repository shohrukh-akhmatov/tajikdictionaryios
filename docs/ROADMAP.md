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
- [x] Scale `data/source/dictionary.csv` to **5,000 → 10,000** curated Tajik entries with frequency rankings and examples (currently **8,041** Tajik / **29,893** total entries)

## Phase 2 — Learning & Study Tools
- [x] **Offline Flashcard Quiz (SM-2 Spaced Repetition)** powered by Saved words or Topic packs, with flip cards, streak tracking, and persistent study progress
- [x] **TTS Speed Toggle** (`0.75×` / `1.0×`) + **Entry Font Size** setting (`Small` / `Medium` / `Large`)
- [x] **Tajik Alphabet & Grammar Quick Reference** sheet (letters `ғ ӣ қ ӯ ҳ ҷ`, verb stem patterns, ezafe `-и`)
- [ ] Optional downloadable native Tajik audio pack (Opus/AAC) for top 2,000–3,000 words

## Phase 3 — OS Integrations & Power Features
- [x] **Home Screen Widget** showing Word of the Day (Android AppWidget / iOS WidgetKit)
- [x] **Favorites Export / Import (JSON)** so users can back up or transfer saved words across devices
- [x] **System Quick Lookup** polish (Android `ACTION_PROCESS_TEXT` live intent handling; iOS `CoreSpotlight` indexing / deep links)
- [ ] Offline Camera OCR Lookup (ML Kit on Android / VisionKit on iOS)

## Phase 3.5 — Family Profiles & Sharing (see [`FAMILY_PROFILES_ROADMAP.md`](FAMILY_PROFILES_ROADMAP.md))
- [x] Share cards for round results, placement level, streaks and achievements (iOS; Android in progress) with app link + QR
- [ ] Local multi-learner profiles on one device (one learning store per profile, no server), "Who's learning?" switcher
- [ ] Kid mode + optional parent PIN, local family board, cross-platform profile backup file
- [x] First-launch onboarding; simpler Learn screen with a separate Progress screen
- [ ] Daily reminder (local notifications), CI for both repos, GitHub Pages landing + privacy policy

## Phase 3.6 — Monetization (ads + GDPR consent)
- [x] Google UMP consent (GDPR/TCF) on launch, after onboarding; "Privacy settings" row in Settings where required
- [x] Waterfall on every slot: Yandex Mobile Ads 8.7.0 first, Google Mobile Ads (iOS 13.13 / Android next-gen SDK 1.3.1) when Yandex has no fill
- [x] Placements (same on both apps): pinned bottom banner on Dictionary / Learn / Saved / History (not Settings); separate banner unit on the word detail screen; interstitial at most every 3 finished game rounds and 3 min, only when leaving the game. No ads inside game rounds, flashcards, onboarding or the placement test
- [x] Debug builds use Yandex demo + Google test units; release builds keep ads off until every ID is filled in (iOS `AdConfig.swift`, Android `Config/AdUnits.properties`)
- [ ] Before release: real AdMob app IDs (iOS Info.plist `GADApplicationIdentifier`, Android manifest) + published GDPR message in AdMob, real Yandex and AdMob ad units, store privacy labels / Data safety form updated for advertising data
- [ ] Kid mode must turn ads off (or switch to child-directed, non-personalized ads): COPPA, Google Play Families policy, App Store Kids category rules

## Phase 4 — Store Release & OTA Lexicon Updates
- [ ] Over-the-air lightweight SQLite delta/manifest update check (keeping user data untouched in Room / SwiftData)
- [ ] Community word submission & correction pipeline
- [ ] Google Play, RuStore, and Apple App Store production releases
