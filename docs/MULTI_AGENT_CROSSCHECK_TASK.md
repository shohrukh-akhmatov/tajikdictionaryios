# Full Non-OCR Extraction & Multi-Agent Trilingual Cross-Check Task Playbook

> **Purpose:** Complete, unrestricted multi-agent execution specification to extract **100% of the clean digital text** (no OCR required) from:
> 1. **Prof. V. K. Muller (2007)** — `D:\Projects\booksofdictionary\books\3.-Мюллер-В.К.-Большой-англо-русский-и-русско-английский-словарь-_-Big-English-Russian-Russian-English-Dictionary.pdf` (`1,008` PDF pages: EN→RU `pp. 10–669`, RU→EN `pp. 674–1000`, irregular verbs `pp. 1001–1006`).
> 2. **D. Saymiddinov et al. (2006, Academy of Sciences of Tajikistan)** — `D:\Projects\booksofdictionary\books\farhangi_tojiki_rusi.zip` (*Фарҳанги тоҷикӣ ба русӣ*, ~70,000 words & expressions, paired with its clean UTF-8 text `D:\Projects\booksofdictionary\books\saymiddinov2006_clean.txt`).
> 3. **Supporting Academic Sources** — `D:\Projects\booksofdictionary\books\vozhahoi_seristemol.txt` (*Ministry of Education 2022*) and `D:\Projects\booksofdictionary\datasets\egslava_taj_rus.csv` / `egslava_rus_taj.csv` (*Osimi 1985*).
>
> And execute a **100% full-coverage multi-agent semantic cross-check** across all `18,487` entries of `data/source/dictionary.csv` (`Tajik ↔ Russian ↔ English`) using parallel worker agents, specialist Russian-pivot homograph auditors, and independent QA verifiers.

---

## 1. Copy-Pasteable Master Coordinator Prompt

Give this exact instruction block (or attach this whole `.md` file) to your Coordinator Agent / multi-agent framework:

```text
You are the Coordinator Agent for a full-lexicon, zero-sampling academic audit of the Tajik–Russian–English offline dictionary (`18,487` entries) used identically by both `D:\Projects\tajikdictionaryios` and `D:\Projects\tajikdictionaryandroid`.

You have an unrestricted token budget and full permission to run Python scripts and launch multiple parallel subagents/swarm workers. Do NOT take shortcuts or sample rows — verify 100% of all 18,487 entries across all 3 languages.

AUTHORITATIVE SOURCE HIERARCHY (strict):
1. Tajik ↔ Russian:
   - PRIMARY: *Фарҳанги тоҷикӣ ба русӣ* (D. Saymiddinov et al., Academy of Sciences of Tajikistan, 2006) extracted from `farhangi_tojiki_rusi.zip` / `saymiddinov2006_clean.txt`.
   - MODERN CIVIC/SCHOOL TERMINOLOGY: *Луғати вожаҳои серистеъмоли забонҳои тоҷикӣ, русӣ ва англисӣ* (`vozhahoi_seristemol.txt`, Ministry of Education, 2022).
   - SECONDARY HISTORICAL: *Osimi 1985* (`egslava_taj_rus.csv`, `egslava_rus_taj.csv`).
2. Russian ↔ English:
   - PRIMARY: Prof. V. K. Muller (2007) *Большой англо-русский и русско-английский словарь* (`3.-Мюллер-В.К.-...pdf`), BOTH Part I (EN→RU) and Part II (RU→EN).
3. FORBIDDEN AS TRUTH: Never trust `oftob.com` spreadsheets if they conflict with Saymiddinov 2006, Ministry 2022, Osimi 1985, or Muller 2007. Website false cognates, slang, and machine-translated distortions must be replaced with book-verified translations.

EXECUTION PHASES:
- Phase 1 (Deterministic Python, NO OCR): Extract 100% clean UTF-8 text and structured JSON from Muller 2007 PDF (using `pypdfium2`, NEVER `pypdf`!) and upgrade the Saymiddinov 2006 extraction (`farhangi2006_entries.json` + `farhangi2006_phrases.json`). Follow Section 2 scripts verbatim.
- Phase 2 (Deterministic Python): Build 93 enriched trilingual shards (`shard_000.json`..`shard_092.json`, 200 rows each = all 18,487 CSV rows) pre-joined with Saymiddinov 2006 entries + expanded `~` phrases + `см.` cross-references, Ministry 2022, Muller RU→EN, and Muller EN→RU back-translations.
- Phase 3 (Parallel Multi-Agent Cross-Check):
  * Wave 1 (10–20 parallel Lexicographer Agents): Audit EVERY single row in `shard_000.json`..`shard_092.json` and emit an explicit per-row verdict (`OK`, `PATCH`, or `DROP_CANDIDATE`) for all 18,487 lines in `patches/patch_000.json`..`patches/patch_092.json`.
  * Wave 2 (2 Russian-Pivot Homograph Specialist Agents): Audit all entries whose Russian bridge word has multiple distinct meanings in Russian/Muller (e.g. мир, лук, ключ, свет, брак, язык, коса, пол, среда, пора, ток, бал, дар, лавка, ручка, лира, такса, класс, партия) to ensure Tajik did NOT pick up the wrong English sense via a Russian homograph!
  * Wave 3 (2 Independent QA Verifier Agents): Verify 100% of `PATCH` and `DROP_CANDIDATE` decisions against raw extracted book records and CSV linting rules.
  * Wave 4 (2 Enrichment Agents): Extract authentic book phrases/examples for `frequency >= 70` words lacking examples and curate missing high-frequency modern words attested in both Saymiddinov 2006 and Muller 2007.
- Phase 4 (Deterministic Merge, Build & Sync): Verify `sum(verdicts) == 18,487`, apply approved patches to `dictionary.csv` in BOTH `tajikdictionaryios` and `tajikdictionaryandroid`, run `build_dictionary.py --self-test`, `--check` (`warnings == 0`), rebuild `dictionary.sqlite`, verify identical SHA-256 checksums across both repos, and write `D:\Projects\booksofdictionary\extracted\audit_report.md`.
```

---

## 2. Phase 1 — Clean Non-OCR Digital Extraction

### Crucial Technical Warning for Muller 2007 PDF
- **NEVER use `pypdf` / `PyPDF2`:** Its default CFF Type1 parser corrupts IPA blocks into `/G5B/G78...` codes and turns soft wrap hyphens into Cyrillic letters (`П`, `Н`, `Й`).
- **ALWAYS use `pypdfium2`** (`import pypdfium2 as pdfium`), which is already installed in this Python environment and extracts clean Unicode Cyrillic + Latin directly in ~3 seconds across all `1,008` pages.
- Handle these exact PDFium byte patterns observed in the file:
  1. **Running Headers:** Top 1–2 lines of dictionary pages repeat the guide word and printed page number (`pg_idx`, e.g., `abductor\r\n10\r\n` on 0-indexed page `10`, `673\r\n` on `673`). Strip them before joining lines.
  2. **Non-Unicode IPA Blocks (Part I):** Transcriptions are enclosed between `0x01` and `0x04` control bytes (e.g., `abductor \x01...\x04 n 1. похититель`). Strip `re.sub(r"\x01[^\r\n]*?\x04", " ", text)`.
  3. **Soft Syllable Wraps Across Line Breaks:** Word-wrap hyphens before `\r\n` appear as control bytes `\x0e`, `\x14`, `\x1a` (or end-of-line letter wrap). Join broken words without inserting spaces.
  4. **Inline Hyphens Within Same Line:** Compound hyphens appear as a control byte between two letters (e.g., `walk\x01up` → `walk-up`, `что\x0eто` → `что-то`). Replace `([letter])[\x01-\x1f]([letter])` → `\1-\2`, then drop any leftover control characters `[\x00-\x08\x0b\x0c\x0e-\x1f]`.

### Script 1: `D:\Projects\booksofdictionary\scripts\extract_muller_2007.py`

```python
import glob
import json
import os
import re
from collections import defaultdict
import pypdfium2 as pdfium

OUT_DIR = r"D:\Projects\booksofdictionary\extracted"
os.makedirs(OUT_DIR, exist_ok=True)

pdf_matches = glob.glob(r"D:\Projects\booksofdictionary\books\*Big-English*")
assert len(pdf_matches) == 1, f"Expected 1 Muller PDF, found: {pdf_matches}"
PDF_PATH = pdf_matches[0]


def clean_pdfium_page(raw_text: str, page_index_zero_based: int) -> str:
    text = raw_text.replace("\r\n", "\n").replace("\r", "\n")
    # 1. Strip Part I IPA symbol font spans enclosed by \x01 ... \x04
    text = re.sub(r"\x01[^\n]*?\x04", " ", text)
    # 2. Strip top running header (guide word + printed page number matching page_index_zero_based)
    lines = text.split("\n")
    pg_str = str(page_index_zero_based)
    cleaned_head = []
    skipped_pg = False
    for idx, ln in enumerate(lines):
        s = ln.strip()
        if idx <= 2 and not skipped_pg and s == pg_str:
            skipped_pg = True
            continue
        if idx == 0 and len(lines) > 1 and lines[1].strip() == pg_str and len(s) < 60:
            continue  # guide word above page number
        cleaned_head.append(ln)
    text = "\n".join(cleaned_head)
    # 3. Restore soft word-wrap hyphens at end of line (e.g. абдук\x1a\nтор -> абдуктор)
    text = re.sub(r"([A-Za-zА-ЯЁа-яё])[\x00-\x1f]\n([A-Za-zА-ЯЁа-яё])", r"\1\2", text)
    # 4. Replace remaining inline control bytes between letters with real hyphen (что\x0eто -> что-то)
    text = re.sub(r"([A-Za-zА-ЯЁа-яё])[\x01-\x1f]([A-Za-zА-ЯЁа-яё])", r"\1-\2", text)
    # 5. Strip leftover control bytes except \n and \t
    text = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", " ", text)
    text = re.sub(r"[ \t]+", " ", text)
    return "\n".join(ln.strip() for ln in text.split("\n") if ln.strip())


def split_entries_en_ru(pages_text: list[str]) -> dict[str, list[str]]:
    # Part I headwords start at line start with ASCII Latin + optional POS markers (n, a, v, adv, prep, etc.)
    joined = "\n".join(pages_text)
    entries = defaultdict(list)
    cur_hw = None
    cur_buf = []
    # Match lines beginning with an English headword followed by POS or homograph number or cross-ref "="
    hw_re = re.compile(
        r"^([A-Za-z][A-Za-z0-9'\-.,\s]{0,45}?)(?:\s+[IVX]+\b|\s+(?:n|v|a|adv|prep|prp|conj|int|pron|num|pref|suf|pl)\b|\s*=|\s+1\.)"
    )
    for ln in joined.split("\n"):
        if len(ln) <= 3 and ln.isalpha() and ln.isupper():
            continue  # section letter header like "A"
        m = hw_re.match(ln)
        if m:
            cand = m.group(1).strip().rstrip(",")
            # Filter out prose phrases starting with "to ~" or "(...)"
            if cand and not cand.startswith("to ") and not cand.startswith("("):
                if cur_hw and cur_buf:
                    entries[cur_hw.lower()].append(" ".join(cur_buf))
                cur_hw = cand
                cur_buf = [ln]
                continue
        if cur_hw:
            # Join wrapped Cyrillic/Latin prose seamlessly
            if cur_buf and re.search(r"-$", cur_buf[-1]):
                cur_buf[-1] = cur_buf[-1][:-1] + ln
            else:
                cur_buf.append(ln)
    if cur_hw and cur_buf:
        entries[cur_hw.lower()].append(" ".join(cur_buf))
    return dict(entries)


def split_entries_ru_en(pages_text: list[str]) -> dict[str, list[str]]:
    # Part II (pages 674..1000): Cyrillic Russian headword at start of line followed immediately by English or Russian qualifier
    joined = "\n".join(pages_text)
    entries = defaultdict(list)
    cur_hw = None
    cur_buf = []
    # Line begins with Russian word (+ optional superscript digit / parenthetical), NOT starting with "~", "(", or punctuation
    hw_re = re.compile(r"^([а-яёА-ЯЁ][а-яёА-ЯЁ\-]{1,40}(?:\d)?)\s+(.*)$")
    for ln in joined.split("\n"):
        # Continuation lines typically start with Latin, "(", "~", or continuation Cyrillic words from wrapped glosses
        if ln[0] in "~(«\"'—1234567890" or ("a" <= ln[0].lower() <= "z"):
            if cur_buf:
                cur_buf.append(ln)
            continue
        m = hw_re.match(ln)
        if m:
            hw_raw, rest = m.group(1), m.group(2)
            # Heuristic: real Russian headword line contains either Latin gloss, "см.", or grammatical marker shortly after
            has_latin = bool(re.search(r"[A-Za-z]", rest))
            has_marker = bool(re.match(r"^(?:см\.|тж\.|союз|предлог|част\.|межд\.|м\.|ж\.|с\.|мн\.|\()", rest))
            if has_latin or has_marker:
                hw = re.sub(r"\d+$", "", hw_raw).lower()
                if cur_hw and cur_buf:
                    entries[cur_hw].append(" ".join(cur_buf))
                cur_hw = hw
                cur_buf = [ln]
                continue
        if cur_buf:
            cur_buf.append(ln)
    if cur_hw and cur_buf:
        entries[cur_hw].append(" ".join(cur_buf))
    return dict(entries)


def main():
    doc = pdfium.PdfDocument(PDF_PATH)
    assert len(doc) == 1008, f"Expected 1008 pages, got {len(doc)}"

    # Part I: English -> Russian (0-indexed 9..668 = PDF pages 10..669)
    en_ru_pages = [clean_pdfium_page(doc[i].get_textpage().get_text_range(), i) for i in range(9, 669)]
    with open(os.path.join(OUT_DIR, "muller2007_en_ru_clean.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(en_ru_pages))
    en_ru_dict = split_entries_en_ru(en_ru_pages)
    with open(os.path.join(OUT_DIR, "muller2007_en_ru.json"), "w", encoding="utf-8") as f:
        json.dump(en_ru_dict, f, ensure_ascii=False, indent=2)

    # Part II: Russian -> English (0-indexed 673..999 = PDF pages 674..1000)
    ru_en_pages = [clean_pdfium_page(doc[i].get_textpage().get_text_range(), i) for i in range(673, 1000)]
    with open(os.path.join(OUT_DIR, "muller2007_ru_en_clean.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(ru_en_pages))
    ru_en_dict = split_entries_ru_en(ru_en_pages)
    with open(os.path.join(OUT_DIR, "muller2007_ru_en.json"), "w", encoding="utf-8") as f:
        json.dump(ru_en_dict, f, ensure_ascii=False, indent=2)

    # Appendix: Irregular verbs (0-indexed 1000..1005 = PDF pages 1001..1006)
    irr_pages = [clean_pdfium_page(doc[i].get_textpage().get_text_range(), i) for i in range(1000, 1006)]
    with open(os.path.join(OUT_DIR, "muller2007_irregular_verbs.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(irr_pages))

    print(f"Extracted Muller 2007 -> EN-RU headwords: {len(en_ru_dict):,}, RU-EN headwords: {len(ru_en_dict):,}")


if __name__ == "__main__":
    main()
```

### Script 2: `D:\Projects\booksofdictionary\scripts\extract_farhangi_2006.py`

This script extracts directly from `farhangi_tojiki_rusi.zip` (cross-checked with `saymiddinov2006_clean.txt`), dehyphenates wrapped Russian words, preserves homographs, resolves `см.` cross-references, and expands **`~` tilde phrases and compound verbs** so all multi-word entries in `dictionary.csv` have authoritative book coverage.

```python
import json
import os
import re
import zipfile
from collections import defaultdict

OUT_DIR = r"D:\Projects\booksofdictionary\extracted"
os.makedirs(OUT_DIR, exist_ok=True)
ZIP_PATH = r"D:\Projects\booksofdictionary\books\farhangi_tojiki_rusi.zip"
CLEAN_TXT = r"D:\Projects\booksofdictionary\books\saymiddinov2006_clean.txt"

# Legacy Tajik .doc codepoint mapping verified against the binary Word stream
DOC_CHAR_MAP = str.maketrans({
    "ѓ": "ғ", "Ѓ": "Ғ",
    "ї": "ӣ", "Ї": "Ӣ",
    "ќ": "қ", "Ќ": "Қ",
    "ў": "ӯ", "Ў": "Ӯ",
    "њ": "ҳ", "Њ": "Ҳ",
    "љ": "ҷ", "Љ": "Ҷ",
})


def load_paragraphs() -> list[str]:
    if os.path.exists(CLEAN_TXT):
        with open(CLEAN_TXT, encoding="utf-8") as f:
            return [ln.strip() for ln in f if ln.strip()]
    # Fallback: read raw UTF-16LE paragraphs directly from ZIP .doc stream
    with zipfile.ZipFile(ZIP_PATH) as z:
        raw = z.read(z.namelist()[0])
    start = raw.find("А первая буква".encode("utf-16le"))
    assert start != -1, "Could not locate text stream in .doc"
    text = raw[start:].decode("utf-16le", errors="ignore").translate(DOC_CHAR_MAP)
    return [ln.strip() for ln in text.split("\r") if ln.strip()]


def dehyphenate(text: str) -> str:
    # Fix wrapped Russian/Tajik hyphens like "относя-щийся" -> "относящийся", "на-веки" -> "навеки"
    return re.sub(r"([а-яёғӣқӯҳҷА-ЯЁҒӢҚӮҲҶ])-\s*([а-яёғӣқӯҳҷ]{2,})", r"\1\2", text)


def expand_parentheses(hw: str) -> list[str]:
    m = re.search(r"\(([^)]+)\)", hw)
    if not m:
        return [hw]
    without = hw[:m.start()] + hw[m.end():]
    with_grp = hw[:m.start()] + m.group(1) + hw[m.end():]
    return expand_parentheses(without) + expand_parentheses(with_grp)


def main():
    paragraphs = load_paragraphs()
    entries = defaultdict(list)
    phrases = defaultdict(list)

    head_re = re.compile(r"^([А-ЯЁҒӢҚӮҲҶ][А-ЯЁҒӢҚӮҲҶ\-'()]*)(?:\s+([IVX]+))?\s+(.+)$")

    for ln in paragraphs:
        m = head_re.match(ln)
        if not m:
            continue
        raw_hw, roman, raw_body = m.group(1), m.group(2), m.group(3)
        body = dehyphenate(raw_body)
        base_hw = raw_hw.lower()

        # Store full entry under expanded base spellings (with optional Roman homograph tag)
        for variant in set(expand_parentheses(base_hw)):
            entries[variant].append({"roman": roman, "raw_headword": raw_hw, "body": body})

        # Extract '~' tilde sub-phrases (e.g. "~ шудан" -> "абадӣ шудан", "хотираи ~" -> "хотираи абадӣ")
        canonical = re.sub(r"[()]", "", base_hw)
        for seg in re.split(r"[;.]", body):
            if "~" not in seg:
                continue
            seg_clean = seg.strip()
            # Match Tajik expression containing '~' followed by its Russian gloss
            pm = re.match(
                r"^([а-яёғӣқӯҳҷА-ЯЁҒӢҚӮҲҶ~,\-\s]{2,55}?~[а-яёғӣқӯҳҷ~,\-\s]{0,40})\s+([а-яёa-zA-Z].{2,})$",
                seg_clean,
            )
            if pm:
                tg_phrase = re.sub(r"\s+", " ", pm.group(1).replace("~", canonical)).strip(" ,;")
                ru_gloss = pm.group(2).strip(" ,;")
                if 2 <= len(tg_phrase.split()) <= 5:
                    phrases[tg_phrase.lower()].append({"base": canonical, "ru": ru_gloss, "raw": seg_clean})

    with open(os.path.join(OUT_DIR, "farhangi2006_entries.json"), "w", encoding="utf-8") as f:
        json.dump(dict(entries), f, ensure_ascii=False, indent=2)
    with open(os.path.join(OUT_DIR, "farhangi2006_phrases.json"), "w", encoding="utf-8") as f:
        json.dump(dict(phrases), f, ensure_ascii=False, indent=2)

    print(f"Extracted Farhangi 2006 -> headwords: {len(entries):,}, expanded ~ phrases: {len(phrases):,}")


if __name__ == "__main__":
    main()
```

---

## 3. Phase 2 — Trilingual Triangulation & 93-Shard Builder (`D:\Projects\booksofdictionary\scripts\build_trilingual_shards.py`)

This script reads all `18,487` rows of `data/source/dictionary.csv` and joins:
- `saym_entries` + resolved `см. <target>` redirect targets + `saym_phrases`
- `muller_ru_en` for every Russian gloss currently in `row["ru"]` AND top candidate Russian nouns/verbs from `saym_entries`
- `muller_en_ru` back-translation for every English gloss currently in `row["en"]`
- `ministry_2022` line matches

Then it writes `93` complete shards (`shard_000.json`..`shard_092.json`, 200 rows each = 100% of CSV rows).

```python
import csv
import json
import os
import re

CSV_PATH = r"D:\Projects\tajikdictionaryios\data\source\dictionary.csv"
EXT_DIR = r"D:\Projects\booksofdictionary\extracted"
SHARD_DIR = os.path.join(EXT_DIR, "shards")
os.makedirs(SHARD_DIR, exist_ok=True)


def norm_tg(s: str) -> str:
    s = s.lower().strip().replace("ӯ", "у").replace("ӣ", "и").replace("ъ", "")
    s = re.sub(r"([бвгғджзйкқлмнпрстфхҳчҷш])\1", r"\1", s)
    return s.replace("ья", "я").replace("ье", "е").replace("ьё", "ё").replace("ью", "ю")


def clean_gloss(g: str) -> str:
    g = re.sub(r"\([^)]*\)", "", g).strip().lower()
    return re.sub(r"^to\s+", "", g).strip()


def lookup_muller_ru_en(ru_cell: str, saym_bodies: list[str], muller_ru_en: dict) -> dict:
    hits = {}
    candidates = [clean_gloss(x) for x in ru_cell.split(";") if x.strip()]
    # Also probe top Russian words from Saymiddinov definition to catch missing primary senses
    for b in saym_bodies[:2]:
        for tok in re.findall(r"[а-яё]{3,}", b.lower()):
            if tok not in candidates and len(candidates) < 12:
                candidates.append(tok)
    for c in candidates:
        if c in muller_ru_en:
            hits[c] = muller_ru_en[c][:2]
        else:
            first_word = c.split()[0] if c.split() else ""
            if first_word in muller_ru_en:
                hits[first_word] = muller_ru_en[first_word][:2]
    return hits


def lookup_muller_en_ru(en_cell: str, muller_en_ru: dict) -> dict:
    hits = {}
    for raw in en_cell.split(";"):
        c = clean_gloss(raw)
        if not c:
            continue
        if c in muller_en_ru:
            hits[c] = muller_en_ru[c][:2]
        elif " " in c and c.split()[0] in muller_en_ru:
            w = c.split()[0]
            hits[w] = muller_en_ru[w][:1]
    return hits


def main():
    saym_entries = json.load(open(os.path.join(EXT_DIR, "farhangi2006_entries.json"), encoding="utf-8"))
    saym_phrases = json.load(open(os.path.join(EXT_DIR, "farhangi2006_phrases.json"), encoding="utf-8"))
    muller_en_ru = json.load(open(os.path.join(EXT_DIR, "muller2007_en_ru.json"), encoding="utf-8"))
    muller_ru_en = json.load(open(os.path.join(EXT_DIR, "muller2007_ru_en.json"), encoding="utf-8"))
    ministry_lines = [
        ln.strip() for ln in open(r"D:\Projects\booksofdictionary\books\vozhahoi_seristemol.txt", encoding="utf-8", errors="ignore")
        if ln.strip()
    ]

    # Normalized fallback index for Saymiddinov 1998/2011 orthography tolerance
    saym_norm_map = {}
    for k, v in saym_entries.items():
        saym_norm_map.setdefault(norm_tg(k), []).extend(v)

    with open(CSV_PATH, encoding="utf-8") as f:
        rows = list(csv.DictReader(f))

    enriched = []
    for line_no, r in enumerate(rows, 2):
        tg = r["tg"].strip()
        tg_lo = tg.lower()
        saym_hits = saym_entries.get(tg_lo) or saym_norm_map.get(norm_tg(tg)) or []
        saym_bodies = [f"[{h['roman']}] {h['body']}" if h.get("roman") else h["body"] for h in saym_hits]

        # Resolve single-hop "см. X" redirects automatically
        resolved_redirects = []
        for b in saym_bodies:
            rm = re.search(r"\bсм\.\s+([а-яёғӣқӯҳҷ]+)", b.lower())
            if rm:
                target = rm.group(1)
                for th in (saym_entries.get(target) or saym_norm_map.get(norm_tg(target)) or [])[:2]:
                    resolved_redirects.append(f"см. {target}: {th['body']}")

        phrase_hits = saym_phrases.get(tg_lo, []) if " " in tg else []
        ministry_hits = [ln for ln in ministry_lines if re.search(rf"\b{re.escape(tg_lo)}\b", ln.lower())][:3]

        enriched.append({
            "line": line_no,
            "tg": tg,
            "pos": r["pos"].strip(),
            "freq": int(r["frequency"] or 0),
            "topic": r["topic"].strip(),
            "app_ru": r["ru"].strip(),
            "app_en": r["en"].strip(),
            "saym_2006": saym_bodies[:4],
            "saym_redirects": resolved_redirects[:2],
            "saym_phrases": phrase_hits[:3],
            "ministry_2022": ministry_hits,
            "muller_ru_en": lookup_muller_ru_en(r["ru"], saym_bodies, muller_ru_en),
            "muller_en_ru": lookup_muller_en_ru(r["en"], muller_en_ru),
        })

    shard_size = 200
    for s in range(0, len(enriched), shard_size):
        idx = s // shard_size
        out = os.path.join(SHARD_DIR, f"shard_{idx:03d}.json")
        with open(out, "w", encoding="utf-8") as f:
            json.dump(enriched[s:s+shard_size], f, ensure_ascii=False, indent=2)

    print(f"Built {(len(enriched) + shard_size - 1)//shard_size} shards covering {len(enriched):,} rows.")


if __name__ == "__main__":
    main()
```

---

## 4. Phase 3 — Multi-Agent Swarm Architecture & Agent Prompts

### Agent Roles & Workload Division

| Agent Role | Count | Input | Output | Coverage Mandate |
| :--- | :---: | :--- | :--- | :--- |
| **Coordinator** | `1` | Master Plan | Progress tracking, QA routing, final merge | Ensures `sum(verdicts) == 18,487` |
| **Wave 1: Trilingual Shard Auditors** | `10–20` | `shard_000.json`..`shard_092.json` | `patches/patch_000.json`..`patch_092.json` | **1 verdict (`OK` / `PATCH` / `DROP_CANDIDATE`) per CSV row** |
| **Wave 2: Russian-Bridge Homograph Auditors** | `2` | Multi-meaning Russian pivot extract | `patches/bridge_homograph_patches.json` | Fixes EN errors caused by Russian homographs (`мир`, `ключ`, `лук`, `брак`, `свет`, etc.) |
| **Wave 3: QA Verifier Agents** | `2` | All `PATCH` + `DROP_CANDIDATE` items + raw JSONs | `patches/qa_verified_patches.json` | Rejects hallucinations, enforces `pos`, `to `, `;`, `()`, post-1998 orthography |
| **Wave 4: Examples & Missing Words Agents** | `2` | High-freq rows + book-only terms | `patches/examples_and_additions.json` | Populates trilingual examples & verified missing everyday words |

---

### Prompt 1 — Wave 1 Trilingual Shard Auditor (Copy-Paste to Each Worker Agent)

> **Task:** You are auditing shard `shard_NNN.json` (200 entries from `data/source/dictionary.csv`).
> You MUST inspect **every single row** in the shard (`len(output) == len(input)`) and write `D:\Projects\booksofdictionary\extracted\patches\patch_NNN.json`.
>
> **Verification Rules for Every Row:**
> 1. **Tajik ↔ Russian (`app_ru` vs `saym_2006` / `saym_redirects` / `saym_phrases` / `ministry_2022`):**
>    - Verify `app_ru` accurately reflects the primary contemporary meanings in *Saymiddinov 2006* (skipping `уст.`/`ист.` unless the word itself is only historical).
>    - Verify `pos` matches grammar (`n`, `v`, `adj`, `adv`, `pron`, `num`, `prep`, `conj`, `intj`, `part`, `phr`).
>    - Ensure Tajik `tg` uses modern post-1998 orthography (no `ц, щ, ы, ь`).
> 2. **Russian ↔ English (`app_ru` + `app_en` vs `muller_ru_en` & `muller_en_ru`):**
>    - Check every gloss in `app_en` against *Muller 2007* (`muller_ru_en` and `muller_en_ru`).
>    - Detect **false Russian-bridge errors** (e.g., Tajik `олам` = "мир / world", NOT "peace"; Tajik `калид` = "ключ / key", NOT "spring"; Tajik `пиёз` = "лук / onion", NOT "bow"; Tajik `никоҳ` = "брак / marriage", NOT "defect").
>    - Ensure `app_ru` and `app_en` are **parallel in sense order**: item `i` in `ru` (split by `;`) should match item `i` in `en`.
>    - Prefix all English verbs with `"to "`. Keep optional clarifiers in trailing parentheses `(...)` cleanly balanced.
> 3. **Unattested / Noise Check:**
>    - If `saym_2006`, `saym_phrases`, and `ministry_2022` are ALL empty AND the word looks like Uzbek dialect noise, corrupted OCR, or an inflected duplicate, mark `"verdict": "DROP_CANDIDATE"` with a clear `reason`. Valid modern compounds (light-verb phrases) and standard modern borrowings (`спорт`, `электрикӣ`) stay `OK` or `PATCH`.
>
> **Output JSON Schema (strict — exactly 1 object per input row):**
> ```json
> [
>   {"line": 2, "tg": "дар", "verdict": "OK"},
>   {
>     "line": 500,
>     "tg": "бардошта",
>     "verdict": "PATCH",
>     "pos": "adj",
>     "ru": "поднятый; снятый",
>     "en": "lifted; raised",
>     "reason": "Saymiddinov 2006 vs Muller verification..."
>   }
> ]
> ```

---

### Prompt 2 — Wave 2 Russian-Bridge Homograph Specialist Agent

Generate the bridge-homograph candidate file first:
```python
import csv, json, os, re

POLYSEMOUS_RU = {
    "мир", "ключ", "лук", "брак", "свет", "язык", "коса", "пол", "пора", "среда",
    "ток", "дар", "ручка", "лира", "такса", "класс", "партия", "лавка", "вид",
    "лист", "рука", "земля", "дело", "место", "слово", "часть", "сторона", "образ",
    "сила", "конец", "ход", "ряд", "счёт", "счет", "строй", "состав", "род", "полк",
    "банка", "замок", "атлас", "орган", "дух", "лад", "бор", "вал", "брат", "мат"
}
rows = list(csv.DictReader(open(r"D:\Projects\tajikdictionaryios\data\source\dictionary.csv", encoding="utf-8")))
muller_ru_en = json.load(open(r"D:\Projects\booksofdictionary\extracted\muller2007_ru_en.json", encoding="utf-8"))
muller_en_ru = json.load(open(r"D:\Projects\booksofdictionary\extracted\muller2007_en_ru.json", encoding="utf-8"))

bridge_cases = []
for i, r in enumerate(rows, 2):
    ru_toks = set(re.findall(r"[а-яё]+", r["ru"].lower()))
    hit = sorted(ru_toks & POLYSEMOUS_RU)
    if hit:
        bridge_cases.append({
            "line": i, "tg": r["tg"], "pos": r["pos"], "ru": r["ru"], "en": r["en"],
            "pivot_ru": hit,
            "muller_ru_en": {w: muller_ru_en.get(w, [])[:2] for w in hit},
        })
with open(r"D:\Projects\booksofdictionary\extracted\bridge_homographs.json", "w", encoding="utf-8") as f:
    json.dump(bridge_cases, f, ensure_ascii=False, indent=2)
print(f"Exported {len(bridge_cases)} Russian-bridge homograph candidates.")
```

> **Prompt for Wave 2 Agent:**
> Check every item in `bridge_homographs.json`. Look at the Tajik meaning and `muller_ru_en` sense disambiguations (e.g., `(земной шар)` vs `(отсутствие войны)`, `(родник)` vs `(для замка)`). Flag and fix any row where `en` includes an unrelated English homograph leaked through Russian (for example, translating a Tajik word for *wedding/marriage* with `"defect; spoilage"` because Russian uses `"брак"`). Output strictly verified JSON patches.

---

### Prompt 3 — Wave 3 Independent QA Verifier Agent

> **Task:** Independently verify every `PATCH` and `DROP_CANDIDATE` produced by Wave 1 and Wave 2 against raw `farhangi2006_entries.json` and `muller2007_ru_en.json` / `muller2007_en_ru.json`.
> Reject or amend any patch that:
> 1. Introduces a translation NOT supported by *Saymiddinov 2006*, *Ministry 2022*, *Osimi 1985*, or *Muller 2007*.
> 2. Drops a common modern Tajik word (like `замонавӣ`, `спорт`, `электрикӣ`, `телефон`) just because it wasn't in a 2006 headword index.
> 3. Leaves unbalanced parentheses `(`, invalid POS tags, Soviet Tajik letters (`ц, щ, ы, ь`) in `tg`, `и т. п.` fragments, or missing `"to "` on English verbs.
> Output final `qa_verified_patches.json` with `"qa_status": "APPROVED" | "REJECTED"`.

---

## 5. Phase 4 — Deterministic Verification, Merge, Rebuild & Sync

Run this final verification script (`D:\Projects\booksofdictionary\scripts\apply_verified_patches.py`) after all agents finish:

```python
import csv, glob, json, os, shutil

IOS_CSV = r"D:\Projects\tajikdictionaryios\data\source\dictionary.csv"
AND_CSV = r"D:\Projects\tajikdictionaryandroid\data\source\dictionary.csv"
PATCH_DIR = r"D:\Projects\booksofdictionary\extracted\patches"
QA_FILE = os.path.join(PATCH_DIR, "qa_verified_patches.json")

# 1. Mathematical completeness check: every single row of all 93 shards must have an explicit verdict
shard_verdicts = {}
for p in sorted(glob.glob(os.path.join(PATCH_DIR, "patch_*.json"))):
    for rec in json.load(open(p, encoding="utf-8")):
        shard_verdicts[int(rec["line"])] = rec

with open(IOS_CSV, encoding="utf-8") as f:
    reader = csv.DictReader(f)
    fieldnames = reader.fieldnames
    rows = list(reader)

expected_lines = set(range(2, len(rows) + 2))
missing = expected_lines - set(shard_verdicts.keys())
assert not missing, f"Incomplete audit! {len(missing)} CSV lines skipped: {sorted(missing)[:10]}"
print(f"100% coverage verified: {len(shard_verdicts):,} / {len(rows):,} rows audited.")

# 2. Apply QA-approved patches
qa_items = json.load(open(QA_FILE, encoding="utf-8"))
approved = {int(x["line"]): x for x in qa_items if x.get("qa_status") == "APPROVED"}

kept_rows = []
patched_cnt = 0
dropped_cnt = 0
for line_no, row in enumerate(rows, 2):
    patch = approved.get(line_no)
    if not patch:
        kept_rows.append(row)
        continue
    if patch.get("verdict") == "DROP_CANDIDATE":
        dropped_cnt += 1
        continue
    for col in ("pos", "ru", "en", "topic", "example_tg", "example_ru", "example_en"):
        if col in patch and patch[col] is not None:
            row[col] = str(patch[col]).strip()
    patched_cnt += 1
    kept_rows.append(row)

# 3. Write atomically to iOS CSV and sync byte-for-byte to Android CSV
for target in (IOS_CSV, AND_CSV):
    tmp = target + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(kept_rows)
    os.replace(tmp, target)

print(f"Applied {patched_cnt} QA-approved patches, dropped {dropped_cnt} verified junk rows. Total rows: {len(kept_rows):,}")
```

Then rebuild & verify byte-for-byte parity across both apps:
```powershell
cd D:\Projects\tajikdictionaryios
python tools/build_dictionary.py --self-test
python tools/build_dictionary.py --check
python tools/build_dictionary.py
Get-FileHash D:\Projects\tajikdictionaryios\data\source\dictionary.csv, D:\Projects\tajikdictionaryandroid\data\source\dictionary.csv, D:\Projects\tajikdictionaryios\TajikDictionary\Resources\dictionary.sqlite, D:\Projects\tajikdictionaryandroid\app\src\main\assets\dictionary.sqlite | Format-Table -Property Path, Hash
```
