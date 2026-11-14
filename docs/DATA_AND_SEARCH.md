# Data & Search Specification (shared by Android and iOS)

> This document is **identical in both repositories** (`tajikdictionaryandroid`, `tajikdictionaryios`).
> If you change it, change it in both places — the two apps must behave the same.

## 1. Dictionary pipeline

```
data/source/dictionary.csv  ──►  tools/build_dictionary.py  ──►  dictionary.sqlite (bundled, read-only)
                                                                   ├─ Android: app/src/main/assets/dictionary.sqlite
                                                                   └─ iOS:     TajikDictionary/Resources/dictionary.sqlite
```

* **Source of truth:** `data/source/dictionary.csv` — one row per Tajik entry.
* Columns: `tg,pos,ru,en,frequency,topic,example_tg,example_ru,example_en`
  * `ru` / `en` — translations separated by `;` in sense order (`дом; комната`).
  * A trailing `(…)` becomes a usage note: `you (singular)` → headword `you`, note `singular`.
  * `pos` ∈ `n v adj adv pron num prep conj intj part phr`.
  * `frequency` 0–100 (higher = more common). Drives result ranking and "Word of the day".
* Russian and English entries are **generated** (deduplicated by headword), and every link is
  written **in both directions** — so `ТJ→RU`, `RU→TJ`, `TJ→EN`, `EN→TJ` all come from one CSV.
* Rebuild after every CSV edit: `python3 tools/build_dictionary.py` (run `--self-test` first).

## 2. SQLite schema (`PRAGMA user_version = 1`)

```sql
CREATE TABLE metadata     (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
CREATE TABLE entries      (id INTEGER PRIMARY KEY NOT NULL,
                           lang TEXT NOT NULL,            -- 'tg' | 'ru' | 'en'
                           headword TEXT NOT NULL,        -- display form
                           search_key TEXT NOT NULL,      -- normalize(headword), see §3
                           pos TEXT, frequency INTEGER NOT NULL DEFAULT 0, topic TEXT);
CREATE INDEX idx_entries_lang_key ON entries(lang, search_key);
CREATE TABLE translations (id INTEGER PRIMARY KEY NOT NULL,
                           from_id INTEGER NOT NULL, to_id INTEGER NOT NULL,
                           position INTEGER NOT NULL DEFAULT 0, note TEXT);
CREATE INDEX idx_translations_from ON translations(from_id, position);
CREATE TABLE examples     (id INTEGER PRIMARY KEY NOT NULL, entry_id INTEGER NOT NULL,
                           tg TEXT NOT NULL, ru TEXT, en TEXT);
```

`metadata` keys: `schema_version`, `data_version`, `built_at`, `source`, `stats` (JSON).

The dictionary DB is **read-only** and replaced wholesale on app/data updates.
User data (favorites, history, flashcards, settings) lives in a **separate** store
(Android: Room + DataStore, iOS: SwiftData + UserDefaults/AppStorage) so it survives dictionary updates.
Favorites/history reference entries by `(lang, headword)` in addition to `id`, so they can be
re-linked if IDs change between data versions.

## 3. Text normalization (MUST be identical on all 3 platforms)

Implemented in `tools/build_dictionary.py::normalize`, `TextNormalizer.kt`, `TextNormalizer.swift`.

1. Lowercase (locale-independent).
2. Unicode **NFD**, drop all combining marks **except U+0306 (breve)**, then **NFC**.
   → `ӣ→и`, `ӯ→у`, `ё→е`, `é→e`, but `й` stays `й`.
3. Fold Tajik letters without decomposition: `ғ→г`, `қ→к`, `ҳ→х`, `ҷ→ч`.
4. Remove apostrophes `' ‘ ’ ʼ` and backtick.
5. Replace every char that is not a letter, digit or space with a space (`кор-бор` → `кор бор`).
6. Collapse whitespace, trim.

`searchKey(text) = normalize(text)`, then if it starts with `"to "` (and is longer than 3 chars) drop that prefix
(`"to go"` → `"go"`).

Test vectors (all three implementations have unit tests for these):

| input | searchKey |
|---|---|
| `Ҳафта` | `хафта` |
| `хӯрдан` | `хурдан` |
| `ҶАВОБ` | `чавоб` |
| `ғамгин` | `гамгин` |
| `қалам` | `калам` |
| `бинӣ` | `бини` |
| `ёрӣ` | `ери` |
| `Чёрный` | `черный` |
| `мой` | `мой` |
| `␠␠кор␠␠␠кардан␠` | `кор кардан` |
| `кор-бор` | `кор бор` |
| `Don't` | `dont` |
| `café` | `cafe` |
| `To Go` | `go` |

**Why folding matters:** most Tajik users type on a Russian keyboard without `ғ ӣ қ ӯ ҳ ҷ`.
Typing `хурдан` must find `хӯрдан`; typing `хона` must find `хона`.

## 4. Modes and mixed-language search

Two modes, switched by a segmented control at the top of the Search screen:

| Mode | Languages searched | Result tags |
|---|---|---|
| `TJK ⇄ RUS` (default) | `tg` + `ru` | **TJ** / **RU** |
| `TJK ⇄ ENG` | `tg` + `en` | **TJ** / **EN** |

There is **no direction switch**: the search box accepts both languages of the active mode at once,
and every result row carries a language tag. Example (`TJK ⇄ RUS`, query `дар`):

```
[TJ] дар        prep   в, на
[TJ] дар        n      дверь
[RU] дар        n      тӯҳфа, ҳадя
[TJ] дарс       n      урок, занятие
[TJ] дарахт     n      дерево
...
```

### 4.1 Query language detection (pre-filter, on the RAW query before normalization)

| Raw query contains | Candidate languages |
|---|---|
| Latin letters `a–z` | `en` |
| any of `ғ ӣ қ ӯ ҳ ҷ` (either case) | `tg` only |
| any of `ц щ ы ь` (either case) | `ru` only |
| other Cyrillic | `tg` + `ru` (ambiguous) |

`searched = candidates ∩ mode.languages`. If the intersection is empty (e.g. Latin typed in `TJK ⇄ RUS`),
search returns no results and the UI shows a hint chip: *"Looks like English — switch to TJK ⇄ ENG?"*.

### 4.2 Search query (prefix match, ranked)

```sql
SELECT e.id, e.lang, e.headword, e.pos,
       (SELECT group_concat(h, ', ') FROM (
            SELECT t2.headword AS h
            FROM translations t JOIN entries t2 ON t2.id = t.to_id
            WHERE t.from_id = e.id
              AND t2.lang = CASE WHEN e.lang = 'tg' THEN :partner ELSE 'tg' END
            ORDER BY t.position LIMIT 4)) AS preview
FROM entries e
WHERE e.lang IN (:langs)                       -- from §4.1
  AND e.search_key >= :key
  AND e.search_key <  :key || char(65535)      -- prefix range, uses idx_entries_lang_key
ORDER BY (e.search_key = :key) DESC,           -- exact matches first
         e.frequency DESC,
         length(e.headword) ASC,
         e.headword ASC
LIMIT 50;
```

* `:partner` = `ru` in `TJK ⇄ RUS`, `en` in `TJK ⇄ ENG`.
* Debounce input by **150 ms**; empty query → show Home (word of the day + recent searches).
* Performance budget: < 16 ms per query on a mid-range device for 10k entries (prefix B-tree scan).

### 4.3 Entry detail

```sql
SELECT id, lang, headword, pos, frequency, topic FROM entries WHERE id = :id;

SELECT t2.id, t2.lang, t2.headword, t2.pos, t.note
FROM translations t JOIN entries t2 ON t2.id = t.to_id
WHERE t.from_id = :id ORDER BY t2.lang, t.position;

SELECT tg, ru, en FROM examples WHERE entry_id = :id;   -- Tajik entries only
```

Detail shows translations **grouped by language** (active mode's partner language first),
each translation is tappable (opens that entry), plus examples, favorite toggle, copy, share and
TTS (Russian/English system voices; Tajik audio is a roadmap item).

### 4.4 Word of the day

Deterministic, offline: among `tg` entries with `frequency >= 50` ordered by `id`,
pick index `daysSinceEpoch(localDate) % count`. Same word on Android and iOS on the same day.
