#!/usr/bin/env python3
"""Build Japanese token dictionaries for RAGFlow.

This tool downloads/filters external resources and exports them in the
`huqie` format (``word frequency tag`` per line). It keeps the generated
assets under ``rag/res`` so that the runtime tokenizer can keep using the
combined ``huqie.txt`` file while we maintain the sources per domain.

Usage (from the project root)::

    python3 scripts/build_huqie_jp.py

The script is idempotent. Re-running it will refresh the source files and
recreate ``rag/res/huqie.txt`` (and remove its ``.trie`` cache so the
runtime can rebuild it with the new contents).
"""

from __future__ import annotations

import argparse
import csv
import html
import io
import lzma
import sys
import textwrap
import urllib.error
import urllib.request
from dataclasses import dataclass
from html.parser import HTMLParser
from pathlib import Path
from typing import Iterable
import math

# External resources ---------------------------------------------------------
# Update the seed if upstream rotates the filename.
NEOLOGD_URL = (
    "https://raw.githubusercontent.com/neologd/mecab-ipadic-neologd/master/"
    "seed/mecab-user-dict-seed.20200910.csv.xz"
)
ORION_DICTIONARY_URL = "https://www.orionkikai.co.jp/technology/pap/dictionary/"

# Output filenames -----------------------------------------------------------
JA_GENERAL_NAME = "huqie_ja_general.txt"
JA_HVAC_NAME = "huqie_ja_hvac.txt"
COMBINED_NAME = "huqie.txt"

# POS mapping: use compact ascii-friendly codes understood by RagTokenizer ----
POS_MAP = {
    # 名詞系
    "名詞-固有名詞-人名-一般": "nr",
    "名詞-固有名詞-人名-姓": "nr",
    "名詞-固有名詞-人名-名": "nr",
    "名詞-固有名詞-人名": "nr",
    "名詞-固有名詞-地域-一般": "ns",
    "名詞-固有名詞-地域-国": "ns",
    "名詞-固有名詞-地域": "ns",
    "名詞-固有名詞-組織-一般": "nt",
    "名詞-固有名詞-組織": "nt",
    "名詞-固有名詞-一般": "nr",
    "名詞-数-助数詞可能": "m",
    "名詞-数": "m",
    "名詞-代名詞-一般": "r",
    "名詞-代名詞-縮約": "r",
    "名詞-代名詞": "r",
    "名詞-形容動詞語幹": "a",
    "名詞-ナイ形容詞語幹": "a",
    "名詞-サ変接続": "vn",
    "名詞-接尾-人名": "suffix",
    "名詞-接尾-地域": "suffix",
    "名詞-接尾-助数詞": "suffix",
    "名詞-接尾": "suffix",
    "名詞-接続詞的": "c",
    "名詞-副詞可能": "d",
    "名詞-一般": "n",
    "名詞-非自立": "n",
    "名詞-連体化": "b",
    "名詞-特殊": "n",
    # 動詞・形容詞など
    "動詞-自立": "v",
    "動詞-非自立": "v",
    "動詞-接尾": "v",
    "形容詞-自立": "a",
    "形容詞-非自立": "a",
    "形容動詞": "a",
    "副詞-一般": "d",
    "副詞-助詞類接続": "d",
    "感動詞": "e",
    "連体詞": "b",
    "接続詞": "c",
    "接頭詞-名詞接続": "prefix",
    "接頭詞-動詞接続": "prefix",
    "接頭詞-形容詞接続": "prefix",
    "接頭詞": "prefix",
    "助詞-係助詞": "p",
    "助詞-格助詞": "p",
    "助詞-副助詞": "p",
    "助詞-終助詞": "p",
    "助詞-準体助詞": "p",
    "助詞-連体化": "p",
    "助助詞": "p",
    "助動詞": "aux",
    "フィラー": "f",
    "記号-一般": "x",
    "記号-句点": "x",
    "記号-読点": "x",
    "記号-カッコ": "x",
    "記号-空白": "x",
    "記号-アルファベット": "x",
    "記号": "x",
    "未知語": "x",
    # fallbacks for main categories
    "名詞": "n",
    "動詞": "v",
    "形容詞": "a",
    "副詞": "d",
    "助詞": "p",
    "接頭詞": "prefix",
    "接尾辞": "suffix",
    "連体詞": "b",
    "感動詞": "e",
}

# ---------------------------------------------------------------------------
@dataclass
class Entry:
    word: str
    freq: int
    pos: str

    def as_line(self) -> str:
        return f"{self.word} {self.freq} {self.pos}\n"


class OrionParser(HTMLParser):
    """Minimal parser that extracts term/description pairs."""

    def __init__(self) -> None:
        super().__init__()
        self._in_heading = False
        self._in_paragraph = False
        self._current_term: list[str] | None = None
        self.entries: list[str] = []

    def handle_starttag(self, tag: str, attrs):
        if tag == "h3":
            attrs_dict = dict(attrs)
            if attrs_dict.get("class") == "title03":
                self._in_heading = True
                self._current_term = []
        elif tag == "p" and self._current_term is not None:
            self._in_paragraph = True

    def handle_endtag(self, tag: str):
        if tag == "h3" and self._in_heading:
            self._in_heading = False
            if self._current_term is not None:
                # strip whitespace now so <p> can detect empty headings
                joined = "".join(self._current_term).strip()
                self._current_term = [joined] if joined else None
        elif tag == "p" and self._in_paragraph:
            self._in_paragraph = False
            if self._current_term:
                term = self._current_term[0]
                if term:
                    self.entries.append(term)
            self._current_term = None

    def handle_data(self, data: str):
        if self._in_heading and self._current_term is not None:
            self._current_term.append(data)
        elif self._in_paragraph:
            # We do not store the description, only mark that the section
            # contains an actual definition (the heading is appended in endtag).
            pass


# Utility functions ----------------------------------------------------------
def log(msg: str) -> None:
    print(msg, file=sys.stderr)


def ensure_download(url: str, dest: Path, *, force: bool = False) -> Path:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and not force:
        log(f"Using cached file: {dest}")
        return dest
    log(f"Downloading {url} → {dest}")
    try:
        with urllib.request.urlopen(url) as response:
            data = response.read()
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Failed to download {url}: {exc}") from exc
    dest.write_bytes(data)
    return dest


def normalize_word(raw: str) -> str:
    text = raw.strip().replace("\u3000", " ")
    # Avoid plain spaces/tab because downstream parser splits on whitespace.
    text = text.replace("\t", " ")
    if " " in text:
        text = text.replace(" ", "\u00A0")  # non-breaking space
    return text


def map_pos(raw: str) -> str:
    if not raw:
        return "x"
    parts = [p.strip() for p in raw.split("-") if p.strip()]
    for length in range(len(parts), 0, -1):
        key = "-".join(parts[:length])
        if key in POS_MAP:
            return POS_MAP[key]
    main = parts[0]
    return POS_MAP.get(main, "x")


def cost_to_freq(cost: int) -> int:
    """Map MeCab cost into a frequency-like weight within [1, 1000]."""

    # Clamp cost to keep the exponent stable while allowing frequent terms to
    # stay near the upper bound.
    normalized_cost = min(max(cost, -5000), 40000)
    exponent = -(normalized_cost + 500) / 4000
    score = int(round(1000 * math.exp(exponent)))
    return max(1, min(1000, score))


# Builders ------------------------------------------------------------------
def build_general_words(cache_dir: Path, *, min_freq: int | None = None) -> dict[str, Entry]:
    cached = ensure_download(NEOLOGD_URL, cache_dir / "neologd_seed.csv.xz")
    entries: dict[str, Entry] = {}
    log("Processing NEologd seed (may take a moment)…")
    with lzma.open(cached, "rt", encoding="utf-8", errors="ignore") as fh:
        reader = csv.reader(fh)
        for row in reader:
            if not row:
                continue
            surface = normalize_word(row[0])
            if not surface:
                continue
            try:
                cost = int(row[3])
            except (ValueError, IndexError):
                cost = 5000
            pos_parts = []
            try:
                for part in row[4:8]:
                    if part and part != "*":
                        pos_parts.append(part)
            except IndexError:
                pass
            pos_raw = "-".join(pos_parts)
            pos = map_pos(pos_raw)
            freq = cost_to_freq(cost)
            if len(surface) > 40:
                continue
            if min_freq is not None and freq < min_freq:
                continue
            if surface in entries:
                if freq > entries[surface].freq:
                    entries[surface] = Entry(surface, freq, pos)
            else:
                entries[surface] = Entry(surface, freq, pos)
    log(f"Collected {len(entries)} entries from NEologd")
    return entries


def build_hvac_terms(cache_dir: Path) -> dict[str, Entry]:
    cached = ensure_download(ORION_DICTIONARY_URL, cache_dir / "orion_hvac.html")
    parser = OrionParser()
    parser.feed(cached.read_text(encoding="utf-8"))
    entries: dict[str, Entry] = {}
    for term in parser.entries:
        clean = normalize_word(html.unescape(term))
        if not clean:
            continue
        entries[clean] = Entry(clean, 600, "n_hvac")
    log(f"Collected {len(entries)} HVAC terms from Orion")
    return entries


def write_dict(path: Path, entries: Iterable[Entry]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fout:
        for entry in entries:
            fout.write(entry.as_line())
    log(f"Wrote {path}")


def merge_entries(*sources: dict[str, Entry]) -> dict[str, Entry]:
    merged: dict[str, Entry] = {}
    for source in sources:
        for word, entry in source.items():
            merged[word] = entry
    return merged


def main() -> int:
    parser = argparse.ArgumentParser(description="Build Japanese huqie dictionaries")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("rag/res"),
        help="Directory where huqie assets live (default: rag/res)",
    )
    parser.add_argument(
        "--cache-dir",
        type=Path,
        default=Path("rag/res/huqie_cache"),
        help="Where to cache downloaded raw resources",
    )
    parser.add_argument(
        "--skip-general",
        action="store_true",
        help="Skip building the general Japanese dictionary",
    )
    parser.add_argument(
        "--skip-hvac",
        action="store_true",
        help="Skip building the HVAC terminology dictionary",
    )
    parser.add_argument(
        "--no-aggregate",
        action="store_true",
        help="Do not merge into huqie.txt (useful for dry-runs)",
    )
    parser.add_argument(
        "--force-download",
        action="store_true",
        help="Re-download resources even if cached",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Limit number of general entries (debug/testing)",
    )
    parser.add_argument(
        "--max-entries",
        type=int,
        default=500_000,
        help="Keep at most this many general entries (highest weight first)",
    )
    parser.add_argument(
        "--min-freq",
        type=int,
        default=20,
        help="Discard general entries with a computed frequency below this threshold",
    )

    args = parser.parse_args()
    cache_dir: Path = args.cache_dir
    output_dir: Path = args.output_dir

    if args.force_download and cache_dir.exists():
        for cached in cache_dir.glob("*"):
            cached.unlink()

    generated: list[dict[str, Entry]] = []

    if not args.skip_general:
        general_entries = build_general_words(cache_dir, min_freq=args.min_freq)
        if args.max_entries is not None and len(general_entries) > args.max_entries:
            limited_keys = sorted(general_entries)[: args.max_entries]
            general_entries = {key: general_entries[key] for key in limited_keys}
            log(
                f"Trimmed general dictionary to {len(general_entries)} entries "
                f"(max={args.max_entries})"
            )
        if args.limit is not None:
            limited_keys = sorted(general_entries)[: args.limit]
            general_entries = {key: general_entries[key] for key in limited_keys}
        general_path = output_dir / JA_GENERAL_NAME
        write_dict(general_path, (general_entries[key] for key in sorted(general_entries)))
        generated.append(general_entries)

    if not args.skip_hvac:
        hvac_entries = build_hvac_terms(cache_dir)
        hvac_path = output_dir / JA_HVAC_NAME
        write_dict(hvac_path, (hvac_entries[key] for key in sorted(hvac_entries)))
        generated.append(hvac_entries)

    if generated and not args.no_aggregate:
        combined_path = output_dir / COMBINED_NAME
        combined_entries = merge_entries(*generated)
        write_dict(combined_path, (combined_entries[key] for key in sorted(combined_entries)))
        trie_path = combined_path.with_suffix(combined_path.suffix + ".trie")
        if trie_path.exists():
            trie_path.unlink()
            log(f"Removed stale trie cache: {trie_path}")

    if not generated:
        log("Nothing was generated (all sources skipped)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
