# Execution Plan — Full Non-OCR Extraction & Trilingual Cross-Check

**Status:** Analysis complete, ready to execute (awaiting go-ahead for Phases 3–4)
**Source playbook:** `docs/MULTI_AGENT_CROSSCHECK_TASK.md`
**Analysed:** 2026-11-28
**Repos affected:** `tajikdictionaryios` **and** `tajikdictionaryandroid`

---

## 0. Executive summary

The playbook is technically sound in direction but **cannot be run verbatim**. Reconnaissance
found three blocking issues and five correctness defects. The audit targets are far more
valuable than the playbook assumes (the CSV lints *clean* today), the real risk is
**irreversible ID shifts** in a shipped database, and the single largest content gap is
**examples, not translations**.

| Finding | Impact |
| :--- | :--- |
| `D:\Projects\booksofdictionary\extracted\` does not exist, and none of the 3 playbook scripts exist | Phases 1–2 must be written from scratch |
| Playbook's Muller cleaner injects **~73,000 spurious hyphens** (measured 14,090 in 191 pages, 15.5×) | Corrupts every EN↔RU lookup; one-character fix |
| Playbook's Phase 4 **deletes CSV rows**, violating a documented invariant | Would shift entry IDs and break saved favourites/history in both apps |
| Saymiddinov index needs parenthetical-expansion, not literal lookup | Coverage 68.1% → **70.5%** measured |
| Only **136 of 18,487** rows have an example (0.7%); 5,062 high-frequency rows lack one | Largest genuine content gap |
| CSVs + SQLite already byte-identical across both repos, and lint clean | Strong baseline; every regression is detectable |

---

## 1. Verified baseline (measured, not assumed)

### 1.1 Repository state

| Item | Value |
| :--- | :--- |
| `data/source/dictionary.csv` (iOS) | 2,212,857 bytes, sha256 `020c11fd…` |
| `data/source/dictionary.csv` (Android) | **byte-identical**, same sha256 |
| `TajikDictionary/Resources/dictionary.sqlite` | 11,509,760 bytes, sha256 `0c9a158d…` |
| `app/src/main/assets/dictionary.sqlite` (Android) | **byte-identical** |
| `dictionary_supplement.csv` | header only (empty), 63 bytes |
| git HEAD (both repos) | `…Add unrestricted multi-agent extraction…` |
| iOS working tree | **dirty** (many modified Swift sources) — unrelated to data |
| Android working tree | clean |

> ⚠️ The iOS tree has uncommitted source changes. Data work should be committed
> **separately** from those so the CSV diff stays reviewable.

### 1.2 CSV lint baseline — already clean

`python tools/build_dictionary.py --self-test` → *All normalization vectors passed.*
`--check` → **0 warnings** in both repos.

| Check | Result |
| :--- | :--- |
| Rows | 18,487 |
| Invalid `pos` | 0 (all within the 11 allowed tags) |
| Soviet letters (`ц щ ы ь`) in `tg` | **0** |
| Duplicate `(tg, pos)` | **0** |
| Empty `tg` / missing `ru` / missing `en` | 0 / 0 / 0 |
| Unbalanced parentheses in translation items | **0** |
| `и т. п` fragments | **0** |
| Frequency outside 0–100 | 0 |
| `pos=v` rows not `to `-prefixed in `en` | **2** |
| Rows with `len(ru senses) ≠ len(en senses)` | **6,872** (4,135 have more RU) |
| Shards at 200 rows | **93** (exactly as the playbook assumes) |

`--check` summary: tg 18,487 · ru 24,232 · en 21,265 · translations 209,230 · examples 136.

### 1.3 Source availability

| Source | Path | State |
| :--- | :--- | :--- |
| Muller 2007 | `books/3.-Мюллер…Big-English-Russian….pdf` | 11,957,751 B · **1,008 pages** ✓ |
| Farhangi 2006 (zip) | `books/farhangi_tojiki_rusi.zip` | 2,644,672 B · 1 member, 12,076,032 B OLE2 `.doc` ✓ (UTF-16LE verified) |
| Farhangi 2006 (text) | `books/saymiddinov2006_clean.txt` | 42,989 lines ✓ |
| Farhangi 2006 (json) | `books/saymiddinov2006_tj-ru.json` | **40,874 headwords** ✓ |
| Ministry 2022 | `books/vozhahoi_seristemol.txt` | 1,003 lines ✓ |
| Osimi 1985 | `datasets/egslava_taj_rus.csv` | 4,985,551 B · **no header**, `tg%ru` delimiter |
| Osimi 1985 (rev) | `datasets/egslava_rus_taj.csv` | 14,832,021 B |
| Wikt. TG extract | `datasets/kaikki-tg.jsonl` | 4,678 records (only 11.3% CSV coverage) |
| **Output dir** | `extracted/` | **DOES NOT EXIST** — created by Phase 1 |

Environment: Python 3.12.10 · `pypdfium2` 5.15.1 ✓ · `pypdf` 7.0.0 present (must **not** be used) · `pdfminer` present.

---

## 2. Blocking issues that change the plan

### 2.1 `extracted/` and all three scripts are absent

`D:\Projects\booksofdictionary\extracted` does not exist. `scripts/` contains only
pre-existing files (`align_dictionary.py`, `apply_academic_fixes.py`, `audit_dict.py`,
`check_candidates.py`, `inspect_anomalies.py`). **None** of `extract_muller_2007.py`,
`extract_farhangi_2006.py`, `build_trilingual_shards.py`, `apply_verified_patches.py` exists.

→ *Zero prior extraction state. Phase 1 starts from a clean slate; approximately 1 day of work.*

### 2.2 DEFECT — the Muller cleaner corrupts line breaks into hyphens (severe)

Playbook Script 1, step 4:

```python
text = re.sub(r"([A-Za-zА-ЯЁа-яё])[\x01-\x1f]([A-Za-zА-ЯЁа-яё])", r"\1-\2", text)
```

`[\x01-\x1f]` **includes `\x0a` (newline)**. Every ordinary line break sitting between two
letters is therefore rewritten as a hyphen.

Measured on pages 9–199:

| Cleaner | Hyphens emitted |
| :--- | ---: |
| Playbook (verbatim) | **15,060** |
| Fixed (exclude `\x0a`) | **970** |

That is **14,090 spurious hyphens in 191 pages (15.5× inflation)** — e.g.
`абдуктор-abeam`, `глупый-absurdity`, `accommodation-train`. Extrapolated across the
991 text pages: **≈73,000 corrupted hyphen positions**, degrading every EN↔RU lookup the
shards depend on.

**Fix (one character class):**

```python
text = re.sub(r"([A-Za-zА-ЯЁа-яё])[\x01-\x09\x0b\x0c\x0e-\x1f]([A-Za-zА-ЯЁа-яё])", r"\1-\2", text)
```

### 2.3 DEFECT — Phase 4 deletes rows and breaks a documented invariant (critical)

Playbook Script 5 drops rows:

```python
if patch.get("verdict") == "DROP_CANDIDATE":
    dropped_cnt += 1
    continue          # row removed from the CSV
```

But `tools/build_dictionary.py` states (lines 26–29):

> *Entry ids are assigned in reading order and the apps store them (favorites, history, …),
> so never delete or reorder rows.*

Every deletion shifts the `id` of every subsequent entry in the shipped SQLite, silently
remapping users' favourites and history in **both** apps.

**Options (needs a decision — see §7):**

1. **Recommended** — never delete. Write `DROP_CANDIDATE` rows to
   `extracted/quarantine.csv` for review; leave the CSV untouched in this pass.
2. Delete only at the **tail** of the file (rows above the last deletion boundary).
3. Accept the ID break and bump `SCHEMA_VERSION`, forcing a client-side re-index.

### 2.4 DEFECT — `~` placeholder handling strips legitimate inflection notation

The Saymiddinov text uses parentheses as grammatical notation, not noise:

```
МУҲИМ(М) 1. важный, значительный; …
ҚУВВА(Т) 1. сила; мощь; энергия; …
МОШИН(А) 1. машина; …
```

The playbook's `expand_parentheses()` handles these correctly. But Script 2 then does:

```python
canonical = re.sub(r"[()]", "", base_hw)     # "муҳим(м)" -> "муҳимм"   ✗
```

which produces `муҳимм` instead of `муҳим`, so every `~` phrase under such a headword
(27,026 `~` occurrences exist) expands to a non-word.

**Fix:** derive `canonical` from the *parenthesis-free* expansion, not a blind character strip.

Additionally **1,684 lines have unbalanced parentheses** (truncated entries such as
`АБРОР (мн. от бир(р) рел. праведные`). These must be quarantined, not silently expanded.

### 2.5 DEFECT — `clean_gloss()` destroys exactly what Wave 2 needs

```python
def clean_gloss(g):
    g = re.sub(r"\([^)]*\)", "", g).strip().lower()   # drops "(земной шар)" etc.
```

Wave 2's whole job is disambiguating Russian homographs by their parenthetical sense
markers (`(земной шар)` vs `(отсутствие войны)`). Stripping them removes the signal.

**Fix:** retain the raw gloss alongside the cleaned key.

### 2.6 DEFECT — noisy evidence injection in `lookup_muller_ru_en()`

The loop pulls up to 12 arbitrary `[а-яё]{3,}` tokens out of the Saymiddinov body and
treats them as translation candidates. Those tokens are prose (*"более"*, *"ко всем"*),
not glosses, and will manufacture false "book-verified" matches that Wave 1 then trusts.

**Fix:** only use tokens from the **gloss position** (after the grammatical marker), and cap at ~4.

---

## 3. Measured coverage — what is actually verifiable

Naive key lookup understates coverage because book headwords carry inflection notation.
Applying parenthetical expansion + orthographic normalization:

| Index construction | Rows covered |
| :--- | ---: |
| Raw `tj-ru.json` keys (what the playbook does) | 12,591 / 18,487 = **68.1%** |
| + parenthetical expansion (`муҳим(м)` → `муҳим`) | 12,898 = 69.8% |
| + normalization (`ӯ→у`, `ӣ→и`, `ъ`, doubled consonants) | **13,037 = 70.5%** |

**Real remaining gap: 5,450 rows**

| Segment | Count | Character |
| :--- | ---: | :--- |
| Single words | 3,407 | mixed — many genuinely absent (`спорт`, `видео`, `сент`, `электрикӣ`) |
| Multi-word phrases | 2,007 | need `~` expansion or the phrase index |
| `pos=v` | 1,558 | **systematic** — see below |

### 3.1 The verb gap is structural, not lexical

| Metric | Value |
| :--- | ---: |
| `pos=v` rows | 1,981 |
| Reached by the headword index | 344 (17.4%) |
| Unreached | 1,637 |
| …of which multi-word | 1,522 |
| …ending in ` кардан` | 853 |
| …whose **stem** exists in Saymiddinov | **909** |

Tajik verbs are analytic compounds (`гап задан`, `кор кардан`, `тайёр кардан`). The book
lists the *noun/adj stem*, not the compound. So 909 of 1,637 are recoverable by
stem-matching — the compound verb layer is what the shard builder must synthesize.

### 3.2 Secondary sources are thin — do not over-trust them

| Source | Coverage of CSV |
| :--- | :--- |
| Ministry 2022 (1,003 lines) | 504 / 16,294 single words ≈ **3%** |
| kaikki Wiktionary (4,678 records) | 2,066 / 18,294 = **11.3%** |

Ministry 2022 is a 1,003-line school terminology list — useful for *civic/school terms*,
not as a general verifier. It cannot justify mass edits.

### 3.3 The biggest real gap is examples, not translations

| Metric | Value |
| :--- | ---: |
| Rows with `example_tg` | **136 / 18,487 = 0.7%** |
| Rows at `frequency ≥ 70` | 5,196 |
| …of those **without** an example | **5,062** |

Phase 4 Wave 4 is the highest-yield, lowest-risk phase: it *adds* content to empty
columns and shifts no IDs.

---

## 4. Constraint the plan must respect

Every `PATCH` that changes `ru` or `en` **rewrites the translation graph**, not just a field:

`build_dictionary.py` mints RU/EN entries keyed by `(lang, lowercase headword)`, then builds
*reverse* links ranked by `(penalty, sense position, -frequency, sequence)`.

Consequences:

- Splitting one RU sense into two **creates a new RU entry id** and re-ranks reverse links.
- Dropping a sense can **orphan** an RU/EN headword.
- The 6,872 rows where `len(ru) ≠ len(en)` are the volatile set: editing either side
  perturbs the parallel-sense contract the playbook's rule 2 asks for.

→ Therefore: **every patch batch must be validated by a full `--check` (warnings == 0) and a
entry-id diff**, and the `DROP` path must be disabled by default (§2.3).

---

## 5. Execution plan

### Phase 0 — Guardrails (before touching anything)

| Step | Action |
| :--- | :--- |
| 0.1 | Snapshot: copy both CSVs + both SQLite files to `extracted/backup/` with sha256 manifest |
| 0.2 | Record entry-id map (`headword → id`) from the current SQLite as the regression reference |
| 0.3 | Confirm branches/commits so data land separately from the dirty iOS sources |
| 0.4 | Create `extracted/{shards,patches,backup}` |

### Phase 1 — Clean extraction (deterministic, no OCR, no LLM)

Write `booksofdictionary/scripts/`:

| Script | Output |
| :--- | :--- |
| `extract_muller_2007.py` **(fixed §2.2)** | `muller2007_en_ru_clean.txt`, `_en_ru.json`, `_ru_en_clean.txt`, `_ru_en.json`, `_irregular_verbs.txt` |
| `extract_farhangi_2006.py` **(fixed §2.4)** | `farhangi2006_entries.json`, `farhangi2006_phrases.json` (legacy-char map verified: `clean.txt` is already modern — `ў/ѓ/ї/ќ/њ/љ` all count **0**) |
| `extract_supporting.py` **(new)** | `osimi1985_tj_ru.json` (headerless `%`-delimited), `ministry2022.json`, `kaikki_tg.jsonl` (English senses) |

**Acceptance gates for Phase 1:**

- Muller: page count **1,008**; EN→RU headwords in **60k–110k** band (a materially lower
  count means the tokenizer is mis-splitting); RU→EN similarly.
- Hyphen sanity: total `-` occurrences within **2×** of the clean page count (~1,000/page is wrong).
- No `\x01…\x04` remnants, no U+FFFD replacement characters.
- Farhangi: ≥ 40,000 headwords; parenthetical expansions ≥ 41,000.
- Deterministic re-run: same sha256 on a second invocation.

### Phase 2 — Shard builder (deterministic)

`build_trilingual_shards.py` **(fixed §2.5, §2.6)** — enrich each row with:

- `saym_2006` bodies (paren-expanded index + normalized fallback)
- `saym_redirects` (resolve `см. X`, max 1 hop, cycle-guarded)
- `saym_phrases` (`~` expansion using the corrected canonical, §2.4)
- `saym_stem_hits` **(new)** — rescues the 909 stem-only verbs
- `ministry_2022`, `muller_ru_en` (**raw gloss retained**), `muller_en_ru`
- `evidence_strength` **(new)** ∈ `{book-verbatim, book-stem, phrase-index, muller-only, none}`

**93 shards × 200 rows = 18,487** exactly; assert `sum(len(shard)) == 18_487`.
`evidence_strength` lets Wave 1 treat "no evidence" rows honestly instead of inventing justification.

### Phase 3 — Parallel cross-check

**Design change:** 93 auditor subagents is latency-bound and low-yield. Instead:

- **A deterministic pre-classifier** assigns each row a candidate verdict from objective
  signals (evidence strength, ru/en sense-count mismatch, `pos` agreement, Soviet letters,
  duplicate stem, phrase-without-evidence). This is free and reproducible.
- **LLM auditors then review only the ~20–30% of rows the classifier cannot settle**, plus
  a random control sample of the "OK" set to measure classifier precision.

| Wave | Agents | Input | Output |
| :--- | ---: | :--- | :--- |
| Pre-classifier | 0 (Python) | all 93 shards | `patches/preclass.json` + disputed queue |
| 1 — shard auditors | 12–16, batched 6–8 shards each | disputed + control rows | `patches/patch_NNN.json` |
| 2 — RU homograph specialists | 2 | `bridge_homographs.json` | `patches/bridge_homograph_patches.json` |
| 3 — independent QA | 2 | every `PATCH`/`DROP` | `qa_verified_patches.json` |
| 4 — examples & additions | 2 | 5,062 high-freq example-less rows | `examples_and_additions.json` |

Hard gates: `len(output) == len(input)` per shard; every verdict carries `evidence_strength`
and a `source` pointer; QA samples **100%** of `DROP_CANDIDATE` and ≥30% of `PATCH`.

### Phase 4 — Merge, build, sync (guarded)

1. `assert sum(verdicts) == 18_487` and `set(lines) == set(range(2, 18_489))`.
2. Apply **PATCH only** by default; `DROP` → `extracted/quarantine.csv` (§2.3).
3. Diff entry-id map against §0.2 — report any shift; abort on unexpected shifts.
4. Write iOS CSV atomically → `--self-test` → `--check` (**warnings must be 0**).
5. Rebuild SQLite; copy to Android; verify sha256 parity on **CSV and SQLite**.
6. Write `extracted/audit_report.md`.

---

## 6. Risk register

| Risk | Severity | Mitigation |
| :--- | :--- | :--- |
| Row deletion shifts shipped entry IDs | **Critical** | Disable `DROP` by default (§2.3) |
| Muller hyphens corrupt every lookup | **High** | §2.2 fix + hyphen-count gate |
| LLM patches unsupported by any book | **High** | `evidence_strength` gate + 100% QA on DROPs |
| Translation-graph churn on 6,872 mismatched rows | Medium | Batch + `--check` per batch + id diff |
| Ministry/kaikki over-trusted (3% / 11% coverage) | Medium | Cap their authority in prompts |
| iOS tree dirty → entangled commit | Medium | Commit data separately (§1.1) |
| Long wall-clock (full 18,487 LLM pass) | Medium | Pre-classifier triage (§Phase 3) |

---

## 7. Decisions required before execution

1. **DROP semantics** — quarantine instead of delete (recommended), tail-only delete, or accept an ID break?
2. **Audit depth** — pre-classifier + LLM on disputed rows (recommended, fast, honest), or exhaustive LLM pass over all 18,487?
3. **Scope** — run Phases 1–2 only, or continue through the audit and the guarded merge?
4. **Repo sync** — mirror to `tajikdictionaryandroid` and rebuild SQLite now, or land iOS first?

---

## 8. Definition of done

- [ ] `extracted/` populated; all extractions reproducible (identical sha256 on re-run)
- [ ] Muller hyphen rate within 2× of source page count
- [ ] 93 shards, `sum == 18,487`, every row carries `evidence_strength`
- [ ] Verdict for **every** row (or an explicit `NO_EVIDENCE` verdict — never a silent gap)
- [ ] `--self-test` passes; `--check` reports **0 warnings** in both repos
- [ ] Entry-id map unchanged *or* every shift reviewed
- [ ] CSV and SQLite sha256 identical across iOS and Android
- [ ] `extracted/audit_report.md` with before/after stats and per-verdict counts
