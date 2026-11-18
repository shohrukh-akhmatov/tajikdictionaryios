# Family Profiles, Share Cards & What's Next — Roadmap (Android + iOS)

> Shared plan for `tajikdictionaryandroid` and `tajikdictionaryios`. Keep this file **identical in both repos**.
> Status markers: `[x]` done · `[~]` in progress · `[ ]` planned.

## 0. Goal and constraints

**Scenario:** a parent has a phone, the children don't. Everyone in the family should be able to play the
learning game on the parent's phone, each with **their own** streak, XP, level, saved words and review schedule,
and switch between learners in two taps.

**Constraints**

| Constraint | Decision |
|---|---|
| No (or minimal) Firestore | **No server at all.** Profiles live on the device. Cross-device options use what the OS gives for free (iCloud / Android Auto Backup) plus a file-based export that works across platforms. |
| Children have no accounts | A profile is just a name + avatar on the device. No e-mail, no sign-in, no personal data leaves the phone. Simplifies App Store Kids / Google Play Families compliance. |
| Same behaviour on both apps | One shared spec (this file + `DATA_AND_SEARCH.md`), one shared JSON backup format. |
| Don't break existing users | Existing learning data becomes the first profile automatically. |

## 1. Architecture: one learning store per profile

```
dictionary.sqlite              (read-only, bundled, shared by everyone)
profiles.json / DataStore      (list of profiles + active profile id + parent PIN hash)
learning/<profileId>.store     (per-profile: flashcard progress, daily logs, saved words, history)
```

Why separate store files instead of adding a `profileId` column everywhere:

* Current models use single-column unique keys (`FlashcardProgress.entryId`, `DailyStudyLog.dateKey`).
  Composite uniqueness needs `#Unique` (iOS 18+), but the iOS target is 17. A store per profile keeps
  every model and query **unchanged**.
* Deleting a profile = deleting one file. Exporting a profile = serializing one store.
* Zero risk of one child's reviews leaking into another child's queue through a missed `WHERE`.

| | iOS | Android |
|---|---|---|
| Profile list | `ProfileStore` (`@Observable`, JSON in Application Support) | `ProfileRepository` (Proto/Preferences DataStore) |
| Learning store | `ModelContainer(for: …, configurations: ModelConfiguration(url: learning/<id>.store))` | `Room.databaseBuilder(ctx, LearningDb::class.java, "learning_<id>.db")` |
| Switching | Rebuild the container, inject with `.modelContainer(container)`, and set `.id(profileId)` on the root view | Close the old Room instance, open the new one, and expose it as `StateFlow<LearningDb>` from a `ProfileSession` singleton (Hilt) |
| Per-profile settings | `SettingsStore(defaults: UserDefaults(suiteName: "profile.<id>"))` | DataStore file `settings_<id>.preferences_pb` |
| Device-wide settings | Theme, font size, dictionary mode default, speech speed | same |

**What is per profile:** flashcard progress, daily study logs (streak/XP), placement result, daily goal,
saved words, history, game preferences (deck source, typing vs. choice).
**What stays shared:** the dictionary, theme, font scale, widget (Word of the Day is global).

### Profile model (shared JSON shape)

```json
{
  "id": "6F1C…UUID",
  "name": "Zarina",
  "avatar": "🦊",
  "color": "#087653",
  "kind": "child",          // "adult" | "child"
  "birthYear": null,        // optional, only used to pick kid-mode defaults; never shared
  "createdAt": "2026-11-18T09:00:00Z"
}
```

## 2. Phases

### F0 — Groundwork (both, ~1–2 days)
- [ ] Put all learning-data access behind one seam: iOS `LearningStore` (owns the `ModelContainer`); Android `LearningDb` provided through `ProfileSession`.
- [ ] Move per-profile settings (`dailyGoal`, `placement*`, `studyMode` — one child learns with Russian, another with English) out of the global settings into a per-profile settings object.
- [ ] Freeze the **`ProfileBackup v1`** JSON format (§4) in this doc, with a test fixture `docs/fixtures/profile_backup_v1.json` that both apps must import.

### F1 — Profiles core (MVP, ~3–4 days per platform)
- [ ] First launch after the update: create profile "Me" and **move** the existing store or DB file into `learning/<id>` (no data copying, so it is instant). Unit test: a pre-migration store opens with the same counts.
- [ ] Create / rename / change avatar / delete a profile (delete asks for confirmation, and for the parent PIN if one is set).
- [ ] **Profile switcher:** an avatar chip in the Learn tab header opens a sheet listing the avatars plus "Add learner".
- [ ] **"Who's learning?" picker** when Learn opens and there are 2+ profiles. It is skipped if the last switch was under 10 minutes ago, and can be turned off in Settings.
- [ ] Each game round, placement test and streak is recorded to the active profile. The round summary shows "Great job, Zarina!".
- [ ] Limit of 8 profiles (UI stays simple).

**Done when:** two profiles on one phone have independent streaks, XP, due reviews and saved words; switching takes ≤ 2 taps; existing users see all their old progress under "Me".

### F2 — Kid-friendly mode (~3 days per platform)
- [ ] `kind = child` defaults: multiple choice and letter tiles instead of free typing, larger tap targets, a shorter round (6 words), a lower daily goal (5), no "skip as known".
- [ ] Optional **parent PIN** (4 digits). It protects Settings, deleting profiles, resetting progress and import. It is stored hashed and salted (iOS Keychain; Android EncryptedSharedPreferences). The PIN can't be recovered: if it is forgotten, the parent reinstalls the app or uses an export.
- [ ] Optional daily time reminder / soft limit per child ("You played 20 minutes today — great job!").
- [ ] Picture topics for young children (animals, colours, family, numbers). This needs an image set (see §6.4).

### F3 — Family features, all local (~2–3 days per platform)
- [ ] **Family board** (Learn → Family): this week's XP, streak and words mastered for each profile, ranked. It is friendly: everyone who played gets a star, not only the winner.
- [ ] **Parent overview:** per child, minutes this week, due reviews, weak words, and last played.
- [ ] **Family streak:** the day counts if anyone in the family practised.
- [ ] Family share card: "Our family learned 120 Tajik words this week" (uses §3).

### F4 — Backup & moving between devices, no server (~3 days per platform)
- [ ] **Export / import a profile** (or all profiles) as one `ProfileBackup v1` file through the share sheet (AirDrop, Telegram, Files, Nearby Share). It is **cross-platform**: a child moving from the parent's Android to their own iPhone keeps their progress. Merge rule: per word, keep the record with the later `lastReviewedAt`; per day log, keep the larger values.
- [ ] **iOS: iCloud backup** comes for free through device backup. The optional *live* sync through CloudKit requires removing `@Attribute(.unique)`, because CloudKit doesn't support unique constraints, and adding dedupe-on-read. That is a separate decision; it is not needed for the family scenario.
- [ ] **Android: Auto Backup** (`android:fullBackupContent` / `dataExtractionRules`) includes `learning_*.db` and the profile DataStore files. It is free, goes to the user's Google Drive, and needs no code beyond the rules file.
- [ ] Migrate the existing `FavoritesBackup` JSON into `ProfileBackup v1` (keep importing the old format).

### F5 — Optional cloud sync (only if users ask for it)
Not recommended for now. If cross-platform *live* sync is ever required, use the **smallest possible Firestore footprint**:
anonymous auth, one document per profile `families/{familyCode}/profiles/{profileId}` holding a compressed
`ProfileBackup v1` blob plus `updatedAt`, and last-write-wins merge with the same rules as F4. The family code is shared as a QR code.
That costs about 1 read and 1 write per session per profile, which stays within the free tier. Everything else in this roadmap works without it.

## 3. Share cards (results & achievements, single player too)

**Status:** `[x]` iOS (`Features/Share/ShareCard.swift`) · `[~]` Android (in progress)

| Where | Card |
|---|---|
| Word-game round summary | "Round complete!" + XP, accuracy, new words, streak + CEFR level |
| Placement test result | "My Tajik level: A2" + known words, text recognized, score |
| Learn → streak card (share icon) | "12-day streak!" (or "My Tajik progress") + XP, mastered, known words, level |
| Learn → each **unlocked** achievement (share icon) | "Achievement unlocked" + badge title + XP, best streak |

**Card spec (identical on both platforms)**
* 1080 × 1350 PNG (4:5, works in Instagram, Telegram, WhatsApp and Facebook feeds), with a fixed light palette and a green gradient (`#087653 → #04392A`).
* Header: app icon mark, "Tajik Dictionary" / "Луғати тоҷикӣ", and the date. Body: emoji/symbol, headline, subtitle, and 2–4 stat tiles.
  Footer: «Забони тоҷикиро меомӯзам!», "Learn Tajik for free, even offline", the app link as text **and as a QR code**.
* Share text (sent with the image, because some apps drop one of the two): headline, stats, CTA, `#LearnTajik`, and the link.
* **Link:** one constant. iOS `AppLinks.shareURL`, Android `AppLinks.SHARE_URL`. It is currently a placeholder
  `https://shohrukh-akhmatov.github.io/tajikdictionary/`; replace it when the GitHub Pages site is live (see §6.2).
* Rendering happens only when the user taps Share (preview sheet → system share sheet), never in lists.
* Privacy: cards never contain the profile name **unless** the user turns on "Show name on share cards" (per profile, off by default for child profiles). There is no analytics and no tracking parameter in the link.

**Next for share cards**
- [ ] Android parity (same layout, `FileProvider` + `ACTION_SEND`)
- [ ] Profile-aware cards (avatar + optional name) after F1
- [ ] Weekly recap card (Sunday): words mastered, minutes, best day
- [ ] Switch the link to App Store / Play / RuStore badges on the landing page once the apps are published; consider Universal Links / App Links so the QR opens the app if it is installed

## 4. `ProfileBackup v1` format (shared)

```json
{
  "format": "tajikdictionary.profile-backup",
  "version": 1,
  "exportedAt": "2026-11-18T09:00:00Z",
  "app": { "platform": "ios", "version": "1.4" },
  "profiles": [{
    "profile": { "id": "…", "name": "Zarina", "avatar": "🦊", "color": "#087653", "kind": "child" },
    "settings": { "dailyGoal": 5, "placementLevel": "A1", "placementBaselineWords": 300 },
    "favorites": [{ "lang": "tg", "headword": "хона", "entryId": 123, "addedAt": "…" }],
    "progress":  [{ "lang": "tg", "headword": "хона", "entryId": 123, "masteryStage": 3,
                    "stabilityDays": 6.2, "repetitions": 4, "lapses": 1, "easeFactor": 2.5,
                    "intervalDays": 6, "lastReviewedAt": "…", "nextReviewAt": "…", "isKnownSkipped": false }],
    "dailyLogs": [{ "dateKey": "2026-11-17", "wordsReviewed": 30, "wordsLearned": 6, "xpEarned": 140,
                    "roundsCompleted": 2, "studySeconds": 610, "correctReviews": 26 }]
  }]
}
```
Entries are matched by `(lang, headword)` first and by `entryId` second, the same rule as favorites in `DATA_AND_SEARCH.md` §2, so backups survive dictionary rebuilds.

## 5. Platform parity checklist

| Feature | iOS | Android |
|---|---|---|
| Keyboard closes on tap/scroll | [x] | [x] |
| Phrase word-by-word fallback | [x] | [x] |
| Deduped translation previews | [x] | [x] |
| Share cards | [x] | [x] |
| Learning language switch (Tajik ⇄ Russian / English) on Learn card + in-game menu, separate from dictionary mode | [x] | [x] |
| First-launch onboarding (welcome → language → daily goal → level test / beginner); skipped for existing users | [x] | [~] |
| Learn screen: today's goal + trainer first; stats, vocabulary and badges on a separate Progress screen | [x] | [~] |
| Profiles F1–F4 | [ ] | [ ] |

## 6. What else the app needs (prioritized)

### 6.1 Content: the biggest learning gap
* **Example sentences:** only **120 of 16,293** Tajik entries have one. Cloze exercises, the "Examples" section and
  context learning all depend on them. Target: examples for the top 2,000 words first. Sources: hand-written
  examples, CC-licensed corpora (check licences, e.g. Tatoeba CC-BY), and LLM-drafted sentences that a native speaker reviews before they ship.
* **Tajik audio:** neither OS has a Tajik TTS voice, so Tajik words are silent or read with a Russian voice. Record the top 2,000–3,000 words
  (Opus, ~1.5 MB per 1,000 words) as a downloadable pack. This is already Phase 2 in `ROADMAP.md`.
* Images for kid topics (F2): about 300 simple illustrations or emoji-based cards.

### 6.2 Release blockers
* **GitHub Pages landing page.** It is needed for the share-card link anyway, and it should hold store badges, screenshots and a **privacy policy** (required by both stores; "no data collected" is easy to state truthfully).
* Store assets: icons, screenshots in 3 languages, descriptions. Age rating; Families/Kids-category questionnaires once profiles ship.
* **CI on GitHub Actions:** a `macos` runner for `xcodebuild test` (iOS can't be built on the current Windows dev machine) and `ubuntu` for `./gradlew test assembleDebug`. Both apps currently ship without automated builds.

### 6.3 Retention
* **Daily reminder** (local notifications, no server): "Keep your 5-day streak 🔥". It can be set per profile, and the time is chosen during onboarding. This is not implemented on iOS today.
* **Streak freeze**: 1 free missed day per week, earned with XP. It avoids discouraging kids.
* ~~A short **onboarding**~~ shipped (4 steps: welcome → TJ⇄RU / TJ⇄EN → daily goal → placement test or "I'm a beginner"). Add the reminder-time step when the daily reminder lands.

### 6.4 Learning features
* An alphabet and reading game for children and beginners (Cyrillic letters + `ғ ӣ қ ӯ ҳ ҷ`, with sounds).
* Verb conjugation tables on verb entries (present/past/future, generated from stems — `WordStemmer` already knows the affixes).
* A listening exercise once audio exists: "hear it → pick the word".
* Phrasebook packs (greetings, at the doctor, at the market) built from existing `phr` entries.

### 6.5 Quality
* OTA dictionary updates (Phase 4 in `ROADMAP.md`) so content fixes don't need an app release.
* An in-app "Report a mistake" button on entries (opens a pre-filled GitHub issue or e-mail; no backend).
* Accessibility pass: Dynamic Type at the largest sizes, VoiceOver/TalkBack labels on game tiles, and colour contrast.
* Crash and performance data only from the platforms' built-in tools (Xcode Organizer / MetricKit, Play Console vitals), with no third-party SDKs. This keeps Kids-category eligibility.

## 7. Suggested order

1. Android parity + share cards (in progress) → 2. CI for both repos → 3. Landing page + privacy policy (gives the real share link)
→ 4. **Profiles F0–F1** → 5. daily reminder + onboarding → 6. F2 kid mode → 7. example sentences (ongoing, content work)
→ 8. F3 family board → 9. F4 backup/transfer → 10. store releases → 11. audio pack, OCR, OTA.
