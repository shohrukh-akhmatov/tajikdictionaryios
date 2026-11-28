# Database Analysis & Free-Model Book Cross-Check Playbook

> Shared reference document for [`tajikdictionaryios`](https://github.com/shohrukh-akhmatov/tajikdictionaryios) and [`tajikdictionaryandroid`](https://github.com/shohrukh-akhmatov/tajikdictionaryandroid), paired with local academic sources in `D:\Projects\booksofdictionary`.
> Last audited: **2026-11-28** against `data_version = 2026.11.23.1138`.

---

## 1. Pipeline & Current Database Snapshot

Both native apps bundle an identical, read-only SQLite database compiled from a single CSV source via `tools/build_dictionary.py`:

| Artifact | Value / Metric |
| :--- | :--- |
| Source CSV (`data/source/dictionary.csv`) | `18,487` Tajik rows · `2,212,857` bytes · SHA-256 `020C11FD2E7E458BFEFCE2E90FBC49FA761B099471125E33656FF1B9C5D086E5` |
| Bundled SQLite (`TajikDictionary/Resources/dictionary.sqlite` & `app/src/main/assets/dictionary.sqlite`) | `11,509,760` bytes · SHA-256 `0C9A158DFCA016A247862AEC17E1E878436E29D740EBB7DE192D852C16CD48B9` |
| Total `entries` rows | **`63,984`** (`tg`: `18,487` · `ru`: `24,232` · `en`: `21,265`) |
| Total `translations` rows | **`209,230`** bidirectional edges (`TJ ↔ RU`, `TJ ↔ EN`) |
| Total `examples` rows | **`136`** (`0.74%` of Tajik entries; `18,351` entries lack examples) |
| Linter (`build_dictionary.py --check`) | **`0` warnings** |
| Normalization self-test (`--self-test`) | **`14 / 14` vectors pass** |
| Homograph headwords (shared spelling, distinct `pos`) | **`190`** headwords |
| Multi-word Tajik entries | **`2,008`** entries (`10.9%`) |
| Entries with `(note)` disambiguators | `969` RU rows (`5.2%`) · `867` EN rows (`4.7%`) |

### Part-of-Speech (`pos`) Distribution (`tg`)

| `pos` | Count | Share |
| :--- | ---: | ---: |
| `n` (noun) | 10,541 | 57.0% |
| `adj` (adjective) | 4,925 | 26.6% |
| `v` (verb) | 1,981 | 10.7% |
| `adv` (adverb) | 761 | 4.1% |
| `pron` (pronoun) | 58 | 0.3% |
| `num` (numeral) | 57 | 0.3% |
| `conj` (conjunction) | 49 | 0.3% |
| `prep` (preposition) | 45 | 0.2% |
| `part` (particle) | 38 | 0.2% |
| `intj` (interjection) | 28 | 0.2% |
| `phr` (phrase) | 4 | <0.1% |

---

## 2. Structural & Data Quality Findings

1. **Severe Example Scarcity (`0.74%` coverage)**
   - Only `136 / 18,487` Tajik entries have `example_tg` / `example_ru` / `example_en`.
   - Impact: Both `EntryDetail` ("Examples" section) and `WordGameEngine.makeClozeSentence` (fill-in-the-blank sentence context inside the Word Game) are empty for **99.26%** of vocabulary.

2. **Topic Coverage Imbalance & Generic POS Bucket Pollution**
   - **`9,577` entries (`51.8%`)** have no `topic`.
   - **`6,501` entries (`35.2%`)** are placed inside generic grammatical buckets (`adjectives`: `4,536`; `verbs`: `1,965`) instead of semantic themes.
   - Only **`2,409` entries (`13.0%`)** occupy the 23 real thematic categories: `nature` (290), `education` (272), `time` (243), `food` (216), `animals` (212), `body` (185), `family` (159), `home` (146), `travel` (142), `grammar` (112), `colors` (109), `numbers` (58), `pronouns` (49), `abstract` (32), `people` (30), `work` (28), `places` (27), `feelings` (25), `greetings` (23), `language` (18), `health` (15), `basics` (9), `questions` (9).
   - Opening `adjectives` renders 4,536 rows inside a single non-lazy container (see `docs/APP_ANALYSIS.md`), while practical categories like `health` (15) and `work` (28) are severely underpopulated.

3. **Heavy Frequency Clustering & Unreachable Tail (`< 40`)**
   - Tiers: `90–100` (`297`), `80–89` (`641`), `70–79` (`4,258`), `40–69` (`13,118`), `< 40` (`173`, range `22..39`).
   - **`60.5%` (`11,190` entries)** collide on just **5 exact integer values**: `58` (`3,164`), `70` (`3,035`), `63` (`2,461`), `56` (`1,433`), `55` (`1,097`).
   - Because `DictionaryRepository.learningCandidates` executes `ORDER BY e.frequency DESC, e.id ASC LIMIT 450` and `WordGameEngine.buildRoundQueue` breaks frequency ties by `entryId ASC`, tying thousands of words at `70` or `58` forces learners through rows in alphabetical CSV order (heavily biased toward `а...` / `б...`).
   - The `173` entries with `frequency < 40` are excluded from both `learningCandidates` and `placementPool` (`WHERE e.frequency >= 40`).

4. **Independent `ru`/`en` Lists vs. False Cross-Language "Sense N" Pairing**
   - In `dictionary.csv`, `ru` and `en` are independent semicolon-separated lists (`дом; комната`).
   - However, **`201` entries** have major length mismatches (`|count(ru) - count(en)| >= 4` or `>= 4` vs `1`), and `13,653` entries have multiple items.
   - Because the UI groups `translations` by `position`, mismatched `ru[i]` and `en[i]` are displayed together under `Sense 1`, `Sense 2`, etc. (for example, `рафтан` pairs Russian `пойти` with English `to ride` at `position = 2`).

5. **Compound Phrases, Inflected Headwords & Archaic Tail**
   - `2,008` Tajik entries are multi-word expressions (mostly light-verb compounds like `кор кардан`, `ёрӣ додан`), yet only `4` entries are tagged `phr`.
   - Some inflected/derived forms exist as separate entries even though `WordStemmer` strips their affixes (e.g., `наметавонад`, `бубахшед`, `онҳо`, `худаш`, `зудтар`, `камтар`, `муҳимтарин`). Keeping ultra-common greetings (`бубахшед`) can help beginners, but low-value inflected duplicates dilute frequency lists.

---

## 3. Reference Books & Datasets Inventory (`D:\Projects\booksofdictionary`)

### A. Parsed / Machine-Readable Sources

| File | Source / Authority | Size / Entries | Current App Coverage / Status |
| :--- | :--- | :--- | :--- |
| `books/saymiddinov2006_tj-ru.json` | *Фарҳанги тоҷикӣ ба русӣ* (D. Saymiddinov et al., Academy of Sciences, 2006) | `40,874` headwords | Covers **`13,037 / 18,487` (`70.5%`)** of app rows (orthography + `(...)` expanded). **`28,461`** Saymiddinov headwords are absent from the app. |
| `datasets/egslava_taj_rus.csv` & `egslava_rus_taj.csv` | *Таджикско-русский* / *Русско-таджикский словарь* (M. S. Osimi, 1985) | ~40k rows | Combined with Saymiddinov, **`13,086 / 18,487` (`70.8%`)** are attested. **`3,394` single-word** & **`2,007` multi-word** rows remain unattested in these two books. |
| `books/vozhahoi_seristemol.pdf` & `.txt` | *Луғати вожаҳои серистеъмоли забонҳои тоҷикӣ, русӣ ва англисӣ* (Ministry of Education, Dushanbe, 2022) | `1,095` lines | High-priority modern trilingual school & civic vocabulary; partially applied. |
| `datasets/en_ru_dictionary_20k.json` & `openrussian/` | Muller 20k EN-RU + OpenRussian (RU-EN) | `20,036` EN / ~50k RU | Used for RU↔EN triangulation (`16,991` app rows match at least one Muller EN headword; `4,592` show raw surface token mismatch candidates needing semantic check). |
| `datasets/kaikki-tg.jsonl` | Wiktionary Tajik JSONL extract | `13.5 MB` | Supplementary EN gloss reference. |
| `datasets/oftob_*` | *Oftob.com* bilingual tables | Legacy reference | **Do not use as authority** — historical source of false cognates/slang; reference books always win. |
| `reports/xcheck3/batches/b000.json`..`b091.json` | Pre-joined audit batches (`92` files, ~35 KB each) | `19,270` records | Pairs current dictionary entries with `[saym]`, `[osimi]`, `[oftob]`, `[wikt]` contexts. |

### B. Un-OCR'd Image-Only Scanned Books (Require OCR / Vision Model)

| PDF File | Book | Pages / Size | `.txt` Status |
| :--- | :--- | ---: | :--- |
| `books/x_kalontarov2008_tj-ru/Kalontarov 2008.pdf` | Kalontarov — *Таджикско-русский словарь* (2008) | `320` pages (`22.9 MB`) | Empty (`\x0c` form-feeds only) |
| `books/x_kalontarov2007_ru-tj/Kalontarov 2007.pdf` | Kalontarov — *Русско-таджикский словарь* (2007) | `273` pages (`17.9 MB`) | Empty (`\x0c` form-feeds only) |
| `books/ru-tj.08.pdf` | A. Tagoev — *Новый русско-таджикский словарь* | `383` pages (`4.7 MB`) | Empty (`\x0c` form-feeds only) |

---

## 4. Token-Sensitive (High-Demand) Tasks: Playbook for a Free Model

Processing `18,487` entries + `976` scanned book pages through a frontier reasoning model consumes **8–12M+ tokens**. Instead, split the work into **small, deterministic JSON batches** (`100–250` items or `5–10` pages per prompt) and delegate them to a free text or vision model, then merge patches deterministically in Python and validate with `tools/build_dictionary.py`.

### Overview of All 6 High-Demand Tasks

| Task | Objective | Volume / Batches | Est. Total Tokens | Priority |
| :--- | :--- | :--- | ---: | :--- |
| **Task A** | Full semantic, POS & parallel `ru`/`en` sense-order audit using `saymiddinov2006` + `Osimi` + `Muller` | `254` zero-overlap + `201` imbalance first (3 batches), then `b000`–`b091` (92 batches) | ~1.8M – 2.5M | **High** |
| **Task B** | Audit `3,394` single-word & `2,007` multi-word entries not found in Saymiddinov/Osimi | `~54` batches × 100 rows | ~600K | **High** |
| **Task C** | OCR & structured extraction of `Kalontarov 2007/2008` + `Tagoev` (`976` scanned pages) | `~98` batches × 10 pages | ~2.5M – 4.0M | Medium |
| **Task D** | Trilingual example sentences (`example_tg`, `ru`, `en`) for all `frequency >= 70` entries (`~5,196` rows) | `~52` batches × 100 rows | ~1.5M – 2.5M | **High** (unlocks Cloze game) |
| **Task E** | Semantic `topic` classification (`16,078` untopiced/POS-bucketed rows) & frequency tie-breaking | `~65` batches × 250 rows | ~800K | Medium |
| **Task F** | Gap-fill missing modern high-frequency Tajik words from `saymiddinov2006` + `Ministry 2022` | `~25` batches × 150 candidate rows | ~500K | Low–Medium |

---

### Task A: Semantic, POS & Parallel Sense Alignment Audit

#### What to Do
Cross-check all rows in `data/source/dictionary.csv` against `saymiddinov2006_tj-ru.json`, `egslava_taj_rus.csv` (*Osimi 1985*), and `en_ru_dictionary_20k.json` (*Muller*). Fix:
1. Missing **primary** book meanings (e.g., where the app only kept a secondary/colloquial meaning).
2. Wrong `pos` tags (`n` vs `adj` vs `adv`).
3. Out-of-order English vs. Russian synonyms so `ru.split(";")[i]` corresponds semantically to `en.split(";")[i]`.

#### How to Do It

**Step 1 — Export Priority Batch (254 zero-overlap + 201 sense-imbalance rows) & clean `b000..b091`:**
Strip `[oftob]` snippets before sending to the free model so it is never biased by website errors:

```python
import csv, json, re
from collections import defaultdict

rows = list(csv.DictReader(open(r"data\source\dictionary.csv", encoding="utf-8")))
saym = json.load(open(r"D:\Projects\booksofdictionary\books\saymiddinov2006_tj-ru.json", encoding="utf-8"))

def norm_tg(s):
    s = s.lower().strip().replace("ӯ", "у").replace("ӣ", "и").replace("ъ", "")
    s = re.sub(r"([бвгғджзйкқлмнпрстфхҳчҷш])\1", r"\1", s)
    return s.replace("ья", "я").replace("ье", "е").replace("ьё", "ё").replace("ью", "ю")

saym_idx = defaultdict(list)
for k, v in saym.items():
    base = re.sub(r"\s+[ivxIVX]+$", "", k.strip().lower())
    m = re.search(r"\(([^)]+)\)", base)
    variants = [base] if not m else [base[:m.start()] + base[m.end():], base[:m.start()] + m.group(1) + base[m.end():]]
    for w in variants:
        saym_idx[norm_tg(w)].extend(v if isinstance(v, list) else [str(v)])

priority = []
for i, r in enumerate(rows, 2):
    defs = saym_idx.get(norm_tg(r["tg"]), [])
    ru_cnt = len([x for x in r["ru"].split(";") if x.strip()])
    en_cnt = len([x for x in r["en"].split(";") if x.strip()])
    zero_overlap = False
    if defs:
        joined = re.sub(r"([а-я])-([а-я])", r"\1\2", " ".join(defs).lower().replace("ё", "е"))
        rt = set(re.findall(r"[а-я]{4,}", r["ru"].lower().replace("ё", "е")))
        bt = set(re.findall(r"[а-я]{4,}", joined))
        zero_overlap = bool(rt and bt and not (rt & bt) and "см." not in joined)
    if zero_overlap or abs(ru_cnt - en_cnt) >= 4 or (ru_cnt >= 4 and en_cnt == 1) or (en_cnt >= 4 and ru_cnt == 1):
        priority.append({
            "line": i, "tg": r["tg"], "pos": r["pos"], "freq": int(r["frequency"]),
            "app_ru": r["ru"], "app_en": r["en"], "saym_2006": defs[:3]
        })

for b in range(0, len(priority), 100):
    with open(rf"D:\Projects\booksofdictionary\reports\priority_a_{b//100:02d}.json", "w", encoding="utf-8") as f:
        json.dump(priority[b:b+100], f, ensure_ascii=False, indent=2)
print(f"Exported {len(priority)} priority items across {(len(priority)+99)//100} batches.")
```

*(For the full sweep, strip `ref_ru`/`ref_en` lines starting with `[oftob]` from `D:\Projects\booksofdictionary\reports\xcheck3\batches\b000.json`..`b091.json`.)*

**Step 2 — Prompt Template for Free Model (copy-paste per batch):**
> **System / Instruction:**
> You are a Tajik–Russian–English lexicographer. Authoritative reference is `saym_2006` (*Saymiddinov 2006*, Academy of Sciences of Tajikistan). Never use website slang.
> Rules:
> 1. Return ONLY a JSON array of items that need changes (`[]` if all items in the batch are accurate and sense-aligned).
> 2. Keep modern post-1998 Tajik orthography (no `ц, щ, ы, ь` in `tg`).
> 3. Valid `pos` values ONLY: `n, v, adj, adv, pron, num, prep, conj, intj, part, phr`.
> 4. Prefix every English verb infinitive in `en` with `"to "` (e.g. `"to go; to leave"`).
> 5. Semicolons `;` separate items, and `ru` and `en` MUST match in sense order (top 2–4 core senses). Keep optional usage clarifications in trailing parentheses like `(gram.)` or `(of fruit)`. Never leave unbalanced parentheses.
>
> **JSON Schema per patched item:**
> `[{"line": 500, "tg": "бардошта", "pos": "adj", "ru": "...", "en": "...", "reason": "short note"}]`
>
> **Batch data:** `[PASTE priority_a_00.json]`

**Step 3 — Merge & Validate:**
Apply approved patches back to `dictionary.csv` keyed by `(line, tg)` and run:
```powershell
python tools/build_dictionary.py --self-test
python tools/build_dictionary.py --check
python tools/build_dictionary.py
```

---

### Task B: Audit the `3,394` Single-Word & `2,007` Multi-Word Unattested Entries

#### What to Do
Classify the `5,401` app rows absent from Saymiddinov 2006 and Osimi 1985 into:
- `KEEP` — genuine modern Tajik word, *Ministry 2022* term (e.g. `замонавӣ`, `спорт`, `электрикӣ`), common compound verb (`кор кардан`), or intentional beginner greeting (`бубахшед`).
- `FIX` — spelling typo, wrong POS, or poor translation.
- `DROP` — Uzbek dialect loanword, redundant conjugated/plural inflection already covered by `WordStemmer`, or unattested garbage.

#### How to Do It

**Step 1 — Export batches of 100 unattested entries:**
```python
import csv, json, re

rows = list(csv.DictReader(open(r"data\source\dictionary.csv", encoding="utf-8")))
saym = json.load(open(r"D:\Projects\booksofdictionary\books\saymiddinov2006_tj-ru.json", encoding="utf-8"))
def norm_tg(s):
    s = s.lower().strip().replace("ӯ","у").replace("ӣ","и").replace("ъ","")
    s = re.sub(r"([бвгғджзйкқлмнпрстфхҳчҷш])\1", r"\1", s)
    return s.replace("ья","я").replace("ье","е").replace("ьё","ё").replace("ью","ю")

saym_keys = set()
for k in saym:
    b = re.sub(r"\s+[ivxIVX]+$", "", k.strip().lower())
    saym_keys.add(norm_tg(re.sub(r"[()]", "", b)))
    saym_keys.add(norm_tg(re.sub(r"\([^)]*\)", "", b)))

unattested = [
    {"line": i, "tg": r["tg"], "pos": r["pos"], "freq": int(r["frequency"]), "ru": r["ru"], "en": r["en"]}
    for i, r in enumerate(rows, 2) if norm_tg(r["tg"]) not in saym_keys
]
for idx in range(0, len(unattested), 100):
    with open(rf"D:\Projects\booksofdictionary\reports\unattested_{idx//100:02d}.json", "w", encoding="utf-8") as f:
        json.dump(unattested[idx:idx+100], f, ensure_ascii=False, indent=2)
print(f"Exported {len(unattested)} items.")
```

**Step 2 — Prompt Template for Free Model:**
> Review these Tajik dictionary rows that were not matched in *Saymiddinov 2006*.
> Output ONLY a JSON array containing rows that should be `FIX`ed or `DROP`ped (omit valid modern Tajik words and valid compound verbs that should be `KEEP`).
> Mark `DROP` for: Uzbek-only words, corrupted words, non-standard phonetic typos that duplicate an existing lemma, or low-utility conjugated verb forms (`-ам/-ат/-аш`, `на-` negatives).
> Format: `[{"line": 123, "tg": "...", "action": "DROP"|"FIX", "pos": "...", "ru": "...", "en": "...", "reason": "..."}]`

---

### Task C: OCR & Structured Extraction of the 3 Scanned PDFs (`976` Pages)

#### What to Do
Convert the three scanned image PDFs into structured JSONL dictionaries:
- `Kalontarov 2008.pdf` (`320` pages, TJ→RU)
- `Kalontarov 2007.pdf` (`273` pages, RU→TJ)
- `ru-tj.08.pdf` (Tagoev, `383` pages, RU→TJ)

Then extract modern compound phrases (`кор кардан`, idiomatic noun+verb expressions) and compare against `dictionary.csv`.

#### How to Do It

**Step 1 — Render PDF pages to PNG (`pip install pypdfium2`) or pre-OCR with Tesseract (`tesseract --psm 6 -l tgk+rus`):**
```python
import pypdfium2 as pdfium, os

pdfs = [
    ("kalontarov2008", r"D:\Projects\booksofdictionary\books\x_kalontarov2008_tj-ru\Kalontarov 2008.pdf"),
    ("kalontarov2007", r"D:\Projects\booksofdictionary\books\x_kalontarov2007_ru-tj\Kalontarov 2007.pdf"),
    ("tagoev2008",     r"D:\Projects\booksofdictionary\books\ru-tj.08.pdf"),
]
for tag, path in pdfs:
    out_dir = rf"D:\Projects\booksofdictionary\ocr_pages\{tag}"
    os.makedirs(out_dir, exist_ok=True)
    doc = pdfium.PdfDocument(path)
    for i, page in enumerate(doc):
        if i < 4:  # optionally skip cover/preface after verifying page numbers
            pass
        bmp = page.render(scale=2.5).to_pil()  # ~180-200 DPI
        bmp.save(os.path.join(out_dir, f"p{i+1:04d}.png"), optimize=True)
    print(f"{tag}: rendered {len(doc)} pages")
```

**Step 2 — Feed 5–8 PNG pages per request to a free Vision-LLM (or feed raw Tesseract `tgk+rus` text to a free text LLM in 10-page chunks):**
> Transcribe every dictionary entry from these scanned dictionary pages into valid UTF-8 JSONL (one JSON object per headword).
> Preserve Tajik diacritics accurately: `ғ ӣ қ ӯ ҳ ҷ` (never substitute `г и к у х ч`).
> Schema: `{"headword": "...", "pos": "...", "senses": ["..."], "phrases": [{"tg": "...", "ru": "..."}]}`
> Save output to `kalontarov2008_extracted.jsonl`.

**Step 3 — Cross-check extracted `headword` / `phrases` against `dictionary.csv`** for missing modern idioms or post-2006 terms.

---

### Task D: Trilingual Example Sentences for Core Words (`frequency >= 70`)

#### What to Do
Populate `example_tg`, `example_ru`, and `example_en` for the `5,196` highest-frequency words (`frequency >= 70`), scaling example coverage from **`0.74%` (`136`)** to **`> 28%` (`5,200+`)** and unlocking contextual Cloze prompts in `WordGameEngine`.

#### How to Do It

**Step 1 — Export `frequency >= 70` entries missing examples, pre-attached with authentic Tajik+Russian phrases mined from `saymiddinov2006_tj-ru.json`:**
```python
import csv, json, re
from collections import defaultdict

rows = list(csv.DictReader(open(r"data\source\dictionary.csv", encoding="utf-8")))
saym = json.load(open(r"D:\Projects\booksofdictionary\books\saymiddinov2006_tj-ru.json", encoding="utf-8"))
saym_flat = {re.sub(r"\s+[ivxIVX]+$", "", k).strip().lower(): " | ".join(v) for k, v in saym.items()}

todo = []
for i, r in enumerate(rows, 2):
    if int(r["frequency"]) >= 70 and not r["example_tg"].strip():
        todo.append({
            "line": i, "tg": r["tg"], "pos": r["pos"],
            "ru": r["ru"], "en": r["en"],
            "book_snippets": saym_flat.get(r["tg"].strip().lower(), "")[:350]
        })

for idx in range(0, len(todo), 100):
    with open(rf"D:\Projects\booksofdictionary\reports\examples_batch_{idx//100:02d}.json", "w", encoding="utf-8") as f:
        json.dump(todo[idx:idx+100], f, ensure_ascii=False, indent=2)
print(f"Exported {len(todo)} entries needing examples.")
```

**Step 2 — Prompt Template for Free Model:**
> Generate one natural, everyday trilingual example sentence (`5–10` words) for each entry below.
> Strict rules:
> 1. If `book_snippets` contains a complete short Tajik+Russian illustrative phrase, prefer adapting it into a clean sentence.
> 2. `example_tg` MUST literally contain the Tajik headword (exact word or obvious inflected form starting with the same root) so a regex cloze blanker matches it.
> 3. Use standard modern Tajik (`ғ ӣ қ ӯ ҳ ҷ`, no Soviet `ц/щ/ы/ь`).
> 4. Keep `example_ru` and `example_en` accurate translations of `example_tg`.
> Output JSON array: `[{"line": 2, "tg": "...", "example_tg": "...", "example_ru": "...", "example_en": "..."}]`

**Step 3 — Regex Cloze Check before merging:**
Verify each returned `example_tg` matches the exact word-boundary pattern used in `WordGameEngine` (`(?<!\w)<stem>\w*`) before writing back to `dictionary.csv`.

---

### Task E: Semantic Topic Classification & Frequency De-Clustering

#### What to Do
1. Reclassify the **`9,577` untopiced** rows and **`6,501` `adjectives`/`verbs`** rows into clear thematic topics (`health`, `work`, `law`, `tech`, `society`, `culture`, `sport`, `food`, `home`, `travel`, `nature`, `education`, `feelings`, `time`, `people`, `abstract`).
2. Spread out the `11,190` tied rows clustered at `58, 70, 63, 56, 55` across `42..79` using OpenRussian/NGSL frequency ranks + LLM tie-breaking so the game introduces diverse semantic roots instead of alphabetical CSV runs.

#### How to Do It
Export 250 entries per batch (`line, tg, pos, topic, frequency, en`) and instruct the free model:
> Classify each word into ONE topic from: `basics, greetings, questions, family, people, body, health, food, home, places, nature, animals, colors, numbers, time, travel, work, education, tech, society, feelings, grammar, actions, descriptions, abstract`.
> Assign a `freq_adj` offset in `[-4, +4]` based on everyday spoken frequency (`+3/+4` for daily concrete words, `-3/-4` for formal/literary words).
> Output ONLY JSON: `[{"line": 100, "topic": "...", "freq_adj": 2}]`

*Note:* If adding new topic keys (`tech`, `society`, `actions`, `descriptions`), also add their translations to `TopicLocalization` (iOS) / `localizedTopicName` (Android).

---

### Task F: Missing High-Frequency Headword Gap-Fill (*Saymiddinov 2006* & *Ministry 2022*)

#### What to Do
Select everyday modern words present in `saymiddinov2006_tj-ru.json` (`28,461` unincluded entries) and `vozhahoi_seristemol.txt` that do not yet appear in `dictionary.csv`.

#### How to Do It

**Step 1 — Filter out archaic/rare/dialect entries in Python before touching any LLM:**
```python
import csv, json, re

app_tg = {r["tg"].strip().lower() for r in csv.DictReader(open(r"data\source\dictionary.csv", encoding="utf-8"))}
saym = json.load(open(r"D:\Projects\booksofdictionary\books\saymiddinov2006_tj-ru.json", encoding="utf-8"))

ARCHAIC = re.compile(r"^(кн\.|уст\.|ист\.|поэт\.|обл\.|диал\.|редк\.|рел\.)")
candidates = []
for k, defs in saym.items():
    hw = re.sub(r"\s+[ivxIVX]+$", "", k).strip().lower()
    if "(" in hw or " " in hw or hw in app_tg or len(hw) < 3:
        continue
    joined = " | ".join(defs)
    if ARCHAIC.match(joined.strip()) or "см." in joined[:30].lower():
        continue
    candidates.append({"tg": hw, "saym_ru": joined[:280]})

for idx in range(0, min(len(candidates), 4000), 150):
    with open(rf"D:\Projects\booksofdictionary\reports\missing_words_{idx//150:02d}.json", "w", encoding="utf-8") as f:
        json.dump(candidates[idx:idx+150], f, ensure_ascii=False, indent=2)
print(f"Filtered down from {len(saym)} to {len(candidates)} modern candidate headwords.")
```

**Step 2 — Prompt Template for Free Model:**
> From these candidate words from *Saymiddinov 2006*, select ONLY common modern Tajik words (frequency equivalent `65–85`) that are not mere morphological variants (`-гӣ`, `-нок`, passive participles) of common words.
> For each selected word, provide valid CSV fields matching `data/source/dictionary.csv` (`tg, pos, ru, en, frequency, topic`).
> Output JSON array: `[{"tg": "...", "pos": "n", "ru": "...", "en": "...", "frequency": 72, "topic": "..."}]`

**Step 3 — Append safely to `data/source/dictionary.csv` (or `dictionary_supplement.csv` if appending without shifting primary IDs), then run:**
```powershell
python tools/build_dictionary.py --self-test
python tools/build_dictionary.py --check
python tools/build_dictionary.py
```
Verify both `TajikDictionary/Resources/dictionary.sqlite` and `app/src/main/assets/dictionary.sqlite` report identical SHA-256 checksums after rebuild.
