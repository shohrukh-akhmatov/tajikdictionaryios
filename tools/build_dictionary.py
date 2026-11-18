#!/usr/bin/env python3
"""
Builds and validates the offline dictionary database (SQLite) from data/source/dictionary.csv.

The SAME script and the SAME normalization rules are used by both apps:
  * Android: app/src/main/assets/dictionary.sqlite
  * iOS:     TajikDictionary/Resources/dictionary.sqlite

Usage:
    python3 tools/build_dictionary.py                      # build with default output path
    python3 tools/build_dictionary.py --check              # lint CSV and print stats without writing
    python3 tools/build_dictionary.py --out path/to/dictionary.sqlite
    python3 tools/build_dictionary.py --self-test          # verify normalization vectors

Source format (CSV, UTF-8, header row):
    tg,pos,ru,en,frequency,topic,example_tg,example_ru,example_en
  * One row = one Tajik entry (homonyms such as "дар" door / "дар" in are separate rows).
  * ru / en hold translations separated by ";" in sense order.
  * A trailing "(...)" in a translation becomes a usage note, e.g. "you (singular)".
  * Russian/English entries are generated automatically (deduplicated by headword), and
    every translation is stored in BOTH directions, so TJ->RU and RU->TJ come from one source.

Python 3.9+ (no third-party dependencies).
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sqlite3
import sys
import unicodedata
from collections import Counter
from datetime import datetime, timezone
from typing import Dict, List, Optional, Tuple

SCHEMA_VERSION = 1
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_SOURCE = os.path.join(ROOT, "data", "source", "dictionary.csv")
# (marker directory that identifies the repo, output path)
DEFAULT_OUTPUTS = [
    ("app", os.path.join(ROOT, "app", "src", "main", "assets", "dictionary.sqlite")),               # Android repo
    ("TajikDictionary", os.path.join(ROOT, "TajikDictionary", "Resources", "dictionary.sqlite")),   # iOS repo
]
REQUIRED_COLUMNS = {"tg", "pos", "ru", "en", "frequency", "topic", "example_tg", "example_ru", "example_en"}
VALID_POS = {"n", "v", "adj", "adv", "pron", "num", "prep", "conj", "intj", "part", "phr"}

# ---------------------------------------------------------------------------
# Normalization — MUST stay identical to:
#   Android: core/text/TextNormalizer.kt
#   iOS:     Core/Text/TextNormalizer.swift
# ---------------------------------------------------------------------------
_KEEP_COMBINING = {"\u0306"}  # breve: keeps "й" (и + breve) distinct from "и"
_FOLD = str.maketrans({"ғ": "г", "қ": "к", "ҳ": "х", "ҷ": "ч"})
_APOSTROPHES = re.compile(r"[\u0027\u2018\u2019\u02BC`]")
_NON_WORD = re.compile(r"[^\w ]+", re.UNICODE)
_SPACES = re.compile(r"\s+")


def normalize(text: str) -> str:
    """Lowercase + fold Tajik-specific letters + strip accents/punctuation.

    "Ҳафта" -> "хафта", "Хӯрдан" -> "хурдан", "ёрӣ" -> "ери", "Don't" -> "dont", "café" -> "cafe"
    """
    s = text.lower()
    s = unicodedata.normalize("NFD", s)
    s = "".join(ch for ch in s if not unicodedata.combining(ch) or ch in _KEEP_COMBINING)
    s = unicodedata.normalize("NFC", s)
    s = s.translate(_FOLD)
    s = _APOSTROPHES.sub("", s)
    s = s.replace("_", " ")
    s = _NON_WORD.sub(" ", s)
    s = _SPACES.sub(" ", s).strip()
    return s


def search_key(text: str) -> str:
    """normalize() + drop the English infinitive marker so "to go" is found by "go"."""
    s = normalize(text)
    if s.startswith("to ") and len(s) > 3:
        s = s[3:]
    return s


NORMALIZATION_VECTORS = [
    ("Ҳафта", "хафта"),
    ("хӯрдан", "хурдан"),
    ("ҶАВОБ", "чавоб"),
    ("ғамгин", "гамгин"),
    ("қалам", "калам"),
    ("бинӣ", "бини"),
    ("ёрӣ", "ери"),
    ("Чёрный", "черный"),
    ("мой", "мой"),
    ("  кор   кардан ", "кор кардан"),
    ("кор-бор", "кор бор"),
    ("Don't", "dont"),
    ("café", "cafe"),
    ("To Go", "go"),       # via search_key
]


def self_test() -> None:
    failures = 0
    for raw, expected in NORMALIZATION_VECTORS:
        got = search_key(raw)
        status = "ok " if got == expected else "FAIL"
        if got != expected:
            failures += 1
        print(f"  [{status}] {raw!r:>18} -> {got!r} (expected {expected!r})")
    if failures:
        sys.exit(f"{failures} normalization vector(s) failed")
    print("All normalization vectors passed.")


# ---------------------------------------------------------------------------
# Build & Linter
# ---------------------------------------------------------------------------
SCHEMA = """
CREATE TABLE metadata (
    key   TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL
);
CREATE TABLE entries (
    id         INTEGER PRIMARY KEY NOT NULL,
    lang       TEXT    NOT NULL,              -- 'tg' | 'ru' | 'en'
    headword   TEXT    NOT NULL,              -- display form
    search_key TEXT    NOT NULL,              -- normalized form used for lookups
    pos        TEXT,                          -- n, v, adj, adv, pron, num, prep, conj, intj, part, phr
    frequency  INTEGER NOT NULL DEFAULT 0,    -- 0..100, higher = more common
    topic      TEXT
);
CREATE INDEX idx_entries_lang_key ON entries(lang, search_key);
CREATE TABLE translations (
    id       INTEGER PRIMARY KEY NOT NULL,
    from_id  INTEGER NOT NULL REFERENCES entries(id),
    to_id    INTEGER NOT NULL REFERENCES entries(id),
    position INTEGER NOT NULL DEFAULT 0,      -- sense order (0 = primary)
    note     TEXT                             -- e.g. "singular", "of the alphabet"
);
CREATE INDEX idx_translations_from ON translations(from_id, position);
CREATE TABLE examples (
    id       INTEGER PRIMARY KEY NOT NULL,
    entry_id INTEGER NOT NULL REFERENCES entries(id),  -- Tajik entry
    tg       TEXT NOT NULL,
    ru       TEXT,
    en       TEXT
);
CREATE INDEX idx_examples_entry ON examples(entry_id);
"""

_NOTE = re.compile(r"^(.*?)\s*\(([^)]*)\)\s*$")


def split_translation(raw: str) -> Tuple[str, Optional[str]]:
    m = _NOTE.match(raw)
    if m and m.group(1).strip():
        return m.group(1).strip(), m.group(2).strip()
    return raw.strip(), None


def parse_list(cell: str) -> List[str]:
    return [p.strip() for p in (cell or "").split(";") if p.strip()]


class Builder:
    def __init__(self) -> None:
        self.entries: List[dict] = []
        self.translations: List[Tuple[int, int, int, Optional[str]]] = []
        self.examples: List[Tuple[int, str, Optional[str], Optional[str]]] = []
        self._target_index: Dict[Tuple[str, str], int] = {}
        self._links = set()
        self._reverse_candidates: Dict[int, List[Tuple[int, int, int, int, int, Optional[str]]]] = {}
        self._rev_seq = 0
        self._finalized = False
        self._seen_tg_pos = set()
        self.warnings: List[str] = []
        self.pos_counts: Counter = Counter()
        self.topic_counts: Counter = Counter()

    def _add_entry(self, lang: str, headword: str, pos: Optional[str], freq: int, topic: Optional[str]) -> int:
        entry_id = len(self.entries) + 1
        self.entries.append({
            "id": entry_id, "lang": lang, "headword": headword,
            "search_key": search_key(headword), "pos": pos, "frequency": freq, "topic": topic,
        })
        return entry_id

    def _target(self, lang: str, headword: str, pos: Optional[str], freq: int, topic: Optional[str]) -> int:
        key = (lang, headword.lower())
        if key in self._target_index:
            entry = self.entries[self._target_index[key] - 1]
            entry["frequency"] = max(entry["frequency"], freq)
            return entry["id"]
        entry_id = self._add_entry(lang, headword, pos, freq, topic)
        self._target_index[key] = entry_id
        return entry_id

    def _link(self, a: int, b: int, position: int, note: Optional[str]) -> None:
        if (a, b) in self._links:
            return
        self._links.add((a, b))
        self.translations.append((a, b, position, note))

    def _queue_reverse(
        self,
        target_id: int,
        tg_id: int,
        source_pos: int,
        freq: int,
        item_count: int,
        note: Optional[str],
    ) -> None:
        penalty = 0 if source_pos == 0 else (8 if source_pos == 1 else source_pos * 14)
        score = penalty - freq
        self._rev_seq += 1
        self._reverse_candidates.setdefault(target_id, []).append(
            (score, source_pos, -freq, item_count, self._rev_seq, tg_id, note)
        )

    def finalize(self) -> None:
        if self._finalized:
            return
        self._finalized = True
        for target_id, candidates in self._reverse_candidates.items():
            candidates.sort(key=lambda item: item[:5])
            position = 0
            for _, _, _, _, _, tg_id, note in candidates:
                if (target_id, tg_id) in self._links:
                    continue
                self._links.add((target_id, tg_id))
                self.translations.append((target_id, tg_id, position, note))
                position += 1

    def add_row(self, line: int, row: Dict[str, str]) -> None:
        tg = (row.get("tg") or "").strip()
        pos = (row.get("pos") or "").strip() or None
        if not tg:
            raise ValueError(f"line {line}: empty 'tg'")
        if pos and pos not in VALID_POS:
            raise ValueError(f"line {line}: unknown pos '{pos}' (valid: {sorted(VALID_POS)})")

        if (tg.lower(), pos or "") in self._seen_tg_pos:
            self.warnings.append(f"line {line}: duplicate (tg={tg!r}, pos={pos!r})")
        self._seen_tg_pos.add((tg.lower(), pos or ""))

        ru, en = parse_list(row.get("ru", "")), parse_list(row.get("en", ""))
        if not ru and not en:
            raise ValueError(f"line {line}: '{tg}' has no translations")
        if not ru:
            self.warnings.append(f"line {line}: '{tg}' missing Russian translation")
        if not en:
            self.warnings.append(f"line {line}: '{tg}' missing English translation")

        freq_raw = (row.get("frequency") or "0").strip() or "0"
        freq = int(freq_raw)
        if not (0 <= freq <= 100):
            raise ValueError(f"line {line}: frequency {freq} out of range 0..100")

        topic = (row.get("topic") or "").strip() or None
        self.pos_counts[pos or "(none)"] += 1
        self.topic_counts[topic or "(none)"] += 1

        tg_id = self._add_entry("tg", tg, pos, freq, topic)
        for lang, items in (("ru", ru), ("en", en)):
            for position, raw in enumerate(items):
                if raw.count("(") != raw.count(")"):
                    self.warnings.append(f"line {line}: unbalanced parentheses in {lang} item {raw!r}")
                headword, note = split_translation(raw)
                target_id = self._target(lang, headword, pos, freq, topic)
                self._link(tg_id, target_id, position, note)      # TJ -> RU/EN
                self._queue_reverse(target_id, tg_id, position, freq, len(items), note)

        ex_tg = (row.get("example_tg") or "").strip()
        if ex_tg:
            self.examples.append((tg_id, ex_tg,
                                  (row.get("example_ru") or "").strip() or None,
                                  (row.get("example_en") or "").strip() or None))

    def summary(self) -> Dict[str, object]:
        self.finalize()
        return {
            "tg": sum(1 for e in self.entries if e["lang"] == "tg"),
            "ru": sum(1 for e in self.entries if e["lang"] == "ru"),
            "en": sum(1 for e in self.entries if e["lang"] == "en"),
            "translations": len(self.translations),
            "examples": len(self.examples),
            "topics": dict(self.topic_counts.most_common()),
            "pos": dict(self.pos_counts.most_common()),
            "warnings": len(self.warnings),
        }

    def write(self, out_path: str, source_path: str) -> Dict[str, int]:
        self.finalize()
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        tmp = out_path + ".tmp"
        if os.path.exists(tmp):
            os.remove(tmp)
        con = sqlite3.connect(tmp)
        con.executescript(SCHEMA)
        con.executemany(
            "INSERT INTO entries(id, lang, headword, search_key, pos, frequency, topic) "
            "VALUES(:id, :lang, :headword, :search_key, :pos, :frequency, :topic)", self.entries)
        con.executemany(
            "INSERT INTO translations(from_id, to_id, position, note) VALUES(?, ?, ?, ?)", self.translations)
        con.executemany("INSERT INTO examples(entry_id, tg, ru, en) VALUES(?, ?, ?, ?)", self.examples)
        stats = {lang: sum(1 for e in self.entries if e["lang"] == lang) for lang in ("tg", "ru", "en")}
        stats["translations"] = len(self.translations)
        stats["examples"] = len(self.examples)
        meta = {
            "schema_version": str(SCHEMA_VERSION),
            "data_version": datetime.now(timezone.utc).strftime("%Y.%m.%d.%H%M"),
            "built_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "source": os.path.relpath(source_path, ROOT),
            "stats": json.dumps(stats, ensure_ascii=False),
        }
        con.executemany("INSERT INTO metadata(key, value) VALUES(?, ?)", meta.items())
        con.commit()
        con.execute("PRAGMA user_version = %d" % SCHEMA_VERSION)
        con.execute("VACUUM")
        con.close()
        os.replace(tmp, out_path)
        return stats


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", default=DEFAULT_SOURCE)
    parser.add_argument("--out", help="output .sqlite path (default: the app's bundled asset path)")
    parser.add_argument("--check", action="store_true", help="validate CSV and print stats without writing .sqlite")
    parser.add_argument("--self-test", action="store_true", help="run normalization test vectors and exit")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        if not args.check:
            return

    builder = Builder()
    with open(args.source, encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        missing_cols = REQUIRED_COLUMNS - set(reader.fieldnames or [])
        if missing_cols:
            sys.exit(f"Missing CSV column(s): {sorted(missing_cols)}")
        for line, row in enumerate(reader, start=2):
            builder.add_row(line, row)

    if args.check:
        for w in builder.warnings:
            print(f"WARN: {w}", file=sys.stderr)
        print(json.dumps(builder.summary(), ensure_ascii=False, indent=2))
        return

    if args.out:
        outputs = [args.out]
    else:
        outputs = [path for marker, path in DEFAULT_OUTPUTS if os.path.isdir(os.path.join(ROOT, marker))]
        if not outputs:
            sys.exit("Could not find the app asset directory; pass --out explicitly.")
    for out in outputs:
        stats = builder.write(out, args.source)
        print(f"Wrote {os.path.relpath(out, ROOT)}  {json.dumps(stats, ensure_ascii=False)}")


if __name__ == "__main__":
    main()
