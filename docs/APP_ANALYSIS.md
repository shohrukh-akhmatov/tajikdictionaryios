# Full App, Logic, UI & UX Analysis (iOS & Android)

> Code-grounded architecture, cross-platform parity, logic, and UI/UX audit covering [`tajikdictionaryios`](https://github.com/shohrukh-akhmatov/tajikdictionaryios) and [`tajikdictionaryandroid`](https://github.com/shohrukh-akhmatov/tajikdictionaryandroid).
> Last audited: **2026-11-28**.

---

## 1. Architecture Overview & Engineering Strengths

Both native apps (SwiftUI + SwiftData on iOS; Jetpack Compose + Room + DataStore on Android) follow a disciplined, offline-first architecture sharing identical algorithms, SQL contracts, and a single byte-identical `dictionary.sqlite` bundle (`63,984` entries, `209,230` translations, `136` examples):

- **Strict Read-Only / Mutable Separation & Safe Rebuild Relinking**:
  - `dictionary.sqlite` is read-only and shipped verbatim on both platforms.
  - User data (Favorites, History max 200 items, Flashcards, DailyStudyLog, Profiles) lives in a separate per-profile store (per-profile SwiftData `.store` files in `SettingsStore.swift`; Room + DataStore in `UserDatabase.kt` / `SettingsRepository.kt`).
  - Whenever `metadata.data_version` increments on dictionary updates, `relinkUserDataIfNeeded` + `resolveEntryId` remap saved items by `(lang, headword)` and `TextNormalizer.searchKey` — including an explicit 1998 post-Soviet Tajik orthography fallback (`ц, щ, ы, ь` → `тс/с, ш, и`) so user progress never breaks across DB updates.
- **Thoughtful Tajik-Specific Search Engineering**:
  - `TextNormalizer` folds `ғ→г`, `қ→к`, `ҳ→х`, `ҷ→ч`, `ӣ→и`, `ӯ→у` (while preserving `й` via `U+0306` breve during NFD stripping) so Tajik users typing on standard Russian keyboards still match `хӯрдан` via `хурдан`.
  - Multi-stage search pipeline in `DictionaryRepository`: `prefixSearch` → `WordStemmer` morphological affixes & irregular Tajik present-stem table (`ме-`, `на-`, `би-`, `-ҳо`, `-ам/-ат/-аш`, `рав→рафтан`, `кун→кардан`) → bounded Levenshtein `fuzzySearch` (with long-prefix 1-edit rescue for cases like `салам` → `салом`) → `wordByWordSearch` phrase breakdown.
- **Lingvist/ACT-R Spaced Repetition & Family Profiles**:
  - `WordGameEngine` models forgetting curves (`retrievalProbability = 0.9^(elapsed/stability)`), Zipf text-recognition percentages, stratified 4-tier CEFR placement tests (`A0`–`B2`), and up to 3 local learner profiles per device with cross-platform `ProfileBackup v1` JSON export/import.
  - **Kid Mode**: 6-word rounds, Multiple Choice & Word Builder only (typing converted to tiles), hides `"Already know"`, and suppresses all ads (`isChild`) for COPPA / Google Play Families / App Store Kids compliance.
- **Resilient Ad Waterfall & Consent Gate**:
  - `AdsManager` gates behind Google UMP GDPR/TCF consent, runs a Yandex-first / AdMob-fallback waterfall with explicit per-leg timeouts and a circuit breaker (`AdsAvailability`), suppresses banners while the IME keyboard is up, and strictly paces interstitials (at most once per 3 completed rounds and 3 minutes, only on game exit).

---

## 2. Critical & High-Priority Bugs / Logic Gaps

### [P0 — iOS Compile Blocker] Missing `looksLatin` and `fromLatin` in `TajikTransliterator.swift`
- **Where**:
  - Calls: `TajikDictionary/Domain/WordGameEngine.swift` (lines 554, 562, 693, 694).
  - Definition: `TajikDictionary/Core/Text/TajikTransliterator.swift` (lines 4–65 — only `toLatin(_:)` exists).
  - Android parity: `core/text/TajikTransliterator.kt` (lines 85–105) implements both `fromLatin` and `looksLatin`.
- **Impact**: Xcode builds for `tajikdictionaryios` will fail to compile `WordGameEngine.swift` until `looksLatin(_:)` and `fromLatin(_:)` are ported from `TajikTransliterator.kt` to `TajikTransliterator.swift`.

### [P1 — Cross-Platform Feature Drift] Missing Latin-Script Tajik Search & Caret Insertion on iOS
- **Where**:
  - Android: `DictionaryRepository.kt` (lines 42–78) & `SearchScreen.kt` (lines 144–148, 308–334).
  - iOS: `DictionaryRepository.swift` (lines 35–45) & `SearchView.swift` (lines 64–66, 123–156).
- **What Happens**:
  - On Android, typing `"salom"`, `"khona"`, or `"man"` finds Cyrillic Tajik entries (`салом`, `хона`, and merges EN `man` + TJ `ман`), displaying a `"Latin reading → ..."` banner (`SearchMatchType.TRANSLIT`). Tapping the Tajik letter bar inserts `ғ ӣ қ ӯ ҳ ҷ` at the text caret (`insertAtCaret`).
  - On iOS, typing Latin while in `TJK ⇄ RUS` triggers `"Different language detected"` instead of checking Latin-to-Tajik transliteration, and typing `"salom"` in `TJK ⇄ ENG` finds nothing. `TajikLettersBar` also appends letters unconditionally (`query += letter`) rather than at the cursor position.

### [P1 — Data / UI Logic Bug] False Cross-Language "Sense N" Grouping in Entry Detail
- **Where**: `EntryDetailView.swift` (lines 83–91, 218–304) and `EntryDetailScreen.kt` (lines 196–206, 320–360).
- **What Happens**:
  - `EntryDetail` takes `detail.translations.values.flatten()` and groups Russian and English entries together by raw list `position` (`0, 1, 2...`), rendering headers labeled `"Sense 1"`, `"Sense 2"`, `"Sense 3"`.
  - Because `ru` and `en` columns in `dictionary.csv` are independent `;`-lists (`13,653` multi-sense rows; `201` with major count imbalances), `ru[i]` and `en[i]` frequently do **not** correspond to the same sense (e.g., `рафтан` pairs `пойти` with `to ride` under Sense 3). On reverse RU/EN entries, each Tajik synonym at `position = 0, 1, 2...` receives its own bloated `"Sense N"` banner.
- **Fix**: Group translations **by language** (partner language first, matching `docs/DATA_AND_SEARCH.md §4.3` and `docs/FEATURES_AND_UI.md`) until `dictionary.csv` enforces aligned sense IDs.

### [P1 — Pedagogical & Dead-Code Logic Gap] Unidirectional Word Game (`Tajik → Partner` Only)
- **Where**: `WordGameEngine.swift` / `WordGameEngine.kt` + `WordGameView.swift` / `WordGameScreen.kt`.
- **What Happens**:
  - Every card in `WordGameView` / `WordGameScreen` prompts in Tajik (`item.card.headword`) and tests `buildTarget = primaryTargetWord(card.preview)` (Russian or English).
  - Consequently:
    1. Learners practice passive recognition (`TJ → EN/RU`) even at Mastery Stages `1–4` (Word Builder / Typing), never active production/spelling of Tajik (`EN/RU → TJ`).
    2. `AnswerCheckResult.tajikLetterNearMiss` (`"Almost! Watch the Tajik letter..."` when typing `хурдан` for `хӯрдан`) and Android's `TajikLettersRow` in typing mode are dead code for all standard Tajik deck entries.
- **Fix**: Keep Stage `0–1` as `Tajik → Partner`, and introduce `Partner → Tajik` at Mastery Stage `2+` (Typing / active recall) so users actually spell Tajik words and trigger the `ғ ӣ қ ӯ ҳ ҷ` near-miss coaching flow.

### [P1 — Scrolling & Memory Performance Cliff on Large Topics]
- **Where**: `TopicEntriesView.swift` (lines 12–40) on iOS and `TopicEntriesScreen.kt` (lines 93–112) on Android.
- **What Happens**:
  - Android wraps `entries.forEachIndexed` inside a **single** `LazyColumn` `item(key = "topic_card")`, and iOS places `ForEach` inside a plain `ScrollView` + `VStack` (`AppCard`).
  - Opening `adjectives` (`4,536` rows) or `verbs` (`1,965` rows) eagerly materializes every row widget at once, causing frame drops and slow navigation transitions.
- **Fix**: Use `LazyVStack` (iOS) and `itemsIndexed(entries)` (Android) with top/bottom rounded-corner card styling per row or chunked rendering.

### [P2 — Residual Search Mode vs. Study Mode Mental Model Friction]
- **Where**: `SearchView.swift` / `SearchViewModel.kt` vs. `LearnView.swift` / `LearnScreen.kt`.
- **What Remains**: Although launching Practice from Topics/Favorites now syncs `studyMode = mode` and Settings shows both pickers, toggling `TJK ⇄ ENG` on the Search screen still leaves `Learn` on the profile's prior `studyMode`. Consider a subtle toast or `"Sync with Dictionary"` convenience toggle for users who do not intend to study a different language than they search.

### [P2 — Progress Estimation, Stale Fallback Stats & Startup Safety]
- **Stale `LexiconStats.fallback` & Stats Refresh**:
  - `WordGameEngine.swift` (lines 71–77) and `WordGameEngine.kt` (lines 44–50) hardcode `totalTajik = 18_447`, `tier90Count = 307`, `tier80Count = 1_534`, `tier70Count = 4_555`, whereas the live DB has `totalTajik = 18,487`, `tier90Count = 297`, `tier80Count = 641`, `tier70Count = 4,258`, `tier<70 = 13,291`. `SettingsStore.refreshStats` (`SettingsStore.swift` line 654) passes `.fallback` instead of querying live `repository.lexiconStats()`.
- **Waterfall Tier Attribution**:
  - `WordGameEngine.computeSummary` allocates `estimatedKnownWords` top-down (`t90 → t80 → t70 → t40`) rather than counting words learned per actual frequency tier, and labels all `13,291` words below 70 (including `173` words `<40` never served in rounds) as `"Advanced (40–69)"`.
- **Force-Unwrap Risk on iOS Startup**:
  - `TajikDictionaryApp.swift` (`try! DictionaryRepository()`, line 259) and `SettingsStore.swift` (`try! ModelContainer(for: schema)`, lines 515, 520) will crash without recovery UI if a store migration or bundle load fails.

---

## 3. UI & UX Audit & Recommendations

### A. Search Screen (`SearchView` / `SearchScreen`)
1. **Misleading "Listen" Audio on Word of the Day**:
   - In `SearchView.swift` (line 326) and `SearchScreen.kt` (line 186), when a Tajik word lacks native `tg-TJ` TTS, the speaker button on the Tajik Word of the Day silently speaks the **Russian or English translation** (`firstMeaning`). Beginners clicking the speaker icon beside a Tajik headword often assume they are hearing Tajik pronunciation.
   - *Recommendation*: Move the speaker button onto the translation preview line or label it explicitly (e.g., `🔊 EN` / `🔊 RU`) whenever `tg` TTS is unavailable.
2. **Topics Discovery vs. Grammatical Lists**:
   - `dictionaryRepository.topics()` sorts by `COUNT(*) DESC`. As a result, the first two pills in the horizontal Topics bar are massive grammatical buckets (`adjectives` 4,536; `verbs` 1,965), while practical beginner topics (`greetings` 23; `basics` 9; `health` 15; `work` 28) are pushed off-screen to the right.
   - *Recommendation*: Pin beginner-friendly thematic topics first, and visually separate/badge `Adjectives` and `Verbs` (or move them into a dedicated "Parts of Speech" filter).
3. **Inline Search Keyboard Ergonomics**:
   - Adding `TajikLettersBar` (`ғ ӣ қ ӯ ҳ ҷ`) and Latin-script Tajik search (`salom → салом`, once synced to iOS) gives best-in-class ergonomics for users on Russian/English keyboards. Fixing `insertAtCaret` on iOS will bring iOS to full parity with Android.

### B. Word Detail Screen (`EntryDetailView` / `EntryDetailScreen`)
1. **Translation Clarity**:
   - Replacing the false cross-language `"Sense N"` headers with clean **Language Sections** (`RUSSIAN` / `ENGLISH`, partner language first) immediately eliminates misaligned synonym pairings and cleans up reverse RU/EN pages.
2. **Pronunciation & Audio Transparency**:
   - The `/latin/` transliteration aid below Tajik headwords and examples is clear and helpful (`TajikTransliterator.toLatin`), compensating well for missing native Tajik TTS.
3. **Word Trainer Integration**:
   - The in-detail "Word Trainer" mastery bar + `"Add to Learning Queue"` / `"Mark as Known"` controls connect lookup directly to spaced repetition — great UX loop.

### C. Learn, Flashcards & Word Game (`LearnView`, `WordGameView`, `StudyView`)
1. **Alphabetical Bias Within Frequency Ties**:
   - Because `60.5%` of words sit on 5 identical frequency integers (`58, 70, 63, 56, 55`) and `frontierOrdered` breaks ties by `entryId ASC`, Smart Mix feeds batches of alphabetical neighbors (`а-`, `б-`) within each tier.
   - *Recommendation*: Inside `WordGameEngine.buildRoundQueue`, break equal-frequency ties deterministically with a pseudo-random mix (or vary topics across a 10-word round) rather than `entryId ASC`.
2. **Ambiguity on Polysemous Words in Typing Challenges**:
   - On `EntryDetail` and `WordGameView`, parenthetical usage notes `(gram.)`, `(of fruit)` are stripped by `stripParentheticalNotes` (`WordGameEngine.swift` line 441) and are **not** displayed in the prompt card. When multiple Tajik homographs or polysemous words share a prompt, showing `pos` + primary `(note)` helps prevent frustrating false negatives.
3. **Discoverability of `GrammarGuideView`**:
   - The Tajik Alphabet (`ғ ӣ қ ӯ ҳ ҷ`), Ezafe (`-и`), and Verb Stem guide currently lives inside `Settings` (`SettingsView` / `SettingsScreen`). Moving or duplicating an entry point onto the `Learn` tab puts reference grammar right where learners study.
4. **Cloze Context Utilization**:
   - The game UI already renders `clozeSentence` + `clozeTranslation` cleanly (`WordGameView.swift` lines 191–205), but `99.26%` of cards lack examples. Completing **Task D** in `docs/DATABASE_ANALYSIS.md` will immediately light up this existing UI feature across all core vocabulary.

### D. Navigation & Tab Architecture
- Currently 5 bottom tabs: **Dictionary**, **Learn**, **Saved**, **History**, **Settings**.
- *Observation*: `Recent searches` (History) already appears prominently on the **Dictionary** home screen (`recent.prefix(15)`), making a full dedicated **History** bottom tab redundant for many users. Merging **Saved + History** into a two-tab **Library** (`Saved | History`) would simplify top-level navigation to 4 tabs (**Dictionary · Learn · Library · Settings**), giving more breathing room to localized Tajik/Russian tab labels.

---

## 4. Prioritized Engineering Action Plan

| Priority | Platform | Item | Target File(s) |
| :--- | :--- | :--- | :--- |
| **P0** | iOS | Port `looksLatin` & `fromLatin` to `TajikTransliterator` so `WordGameEngine.swift` compiles cleanly | `TajikDictionary/Core/Text/TajikTransliterator.swift` |
| **P1** | iOS | Port Latin-script Tajik search (`TRANSLIT` match type) & cursor-aware `TajikLettersBar` (`insertAtCaret`) to match Android | `DictionaryRepository.swift`, `SearchView.swift` |
| **P1** | Both | Replace `position`-based `"Sense N"` cross-language grouping with language-grouped sections | `EntryDetailView.swift`, `EntryDetailScreen.kt` |
| **P1** | Both | Enable lazy list rendering on `TopicEntries` so `adjectives` (4,536) and `verbs` (1,965) scroll at 60/120fps | `TopicEntriesView.swift`, `TopicEntriesScreen.kt` |
| **P1** | Both | Add bidirectional `Partner → Tajik` prompts at Mastery Stage `2+` in `WordGameEngine` & `WordGame` screens | `WordGameEngine.*`, `WordGameView.swift`, `WordGameScreen.kt` |
| **P2** | Both | Update `LexiconStats.fallback`, tie-break `frontierOrdered` with deterministic variety, and move `Grammar Guide` link to `Learn` | `WordGameEngine.*`, `SettingsStore.swift`, `LearnView.swift`, `LearnScreen.kt` |
