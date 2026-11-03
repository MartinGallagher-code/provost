# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""A byte-level BPE tokenizer read from a Hugging Face tokenizer.json, in
plain Python: what the tiny LM needs at capture time without transformers.

    tok = Tokenizer.load("tokenizer.json")
    tok.encode("Filesystem  Size")    # -> [token ids], no special tokens added

It covers the tokenizer the tiny LM was trained with (transformers loads
SmolLM2's as a GPT2Tokenizer): no normalizer; added tokens split out first;
then ByteLevel's GPT-2 pattern; then BPE merges over the byte-to-unicode
alphabet. The model directory carries that tokenizer as transformers had it
(ml/export_lm.py writes it), not the Hub's tokenizer.json, whose Digits step
transformers does not apply. The GPT-2 pattern needs Unicode letter and
number classes, which the re module lacks, so it is a small scanner over
unicodedata categories. ml/export_lm.py --check compares it with
transformers on every piece of the corpus.
"""
import json
import unicodedata

# Unicode White_Space, which the pattern's \s means
_SPACE = set("\t\n\x0b\x0c\r \x85\xa0     　") | {
    chr(c) for c in range(0x2000, 0x200B)}
_CONTRACTIONS = ("s", "t", "re", "ve", "m", "ll", "d")


def _cat(ch):
    """'L' letter, 'N' number, 'S' whitespace, 'O' anything else."""
    if ch in _SPACE:
        return "S"
    c = unicodedata.category(ch)[0]
    return c if c in "LN" else "O"


def _byte_alphabet():
    """GPT-2's reversible map from bytes to printable characters."""
    keep = list(range(ord("!"), ord("~") + 1)) + list(range(ord("¡"), ord("¬") + 1)) + \
        list(range(ord("®"), ord("ÿ") + 1))
    out, n = {}, 0
    for b in range(256):
        if b in keep:
            out[b] = chr(b)
        else:
            out[b] = chr(256 + n)
            n += 1
    return out


def split_gpt2(text):
    """GPT-2's pattern, alternatives tried in order at each position:
    's|'t|'re|'ve|'m|'ll|'d| ?\\p{L}+| ?\\p{N}+| ?[^\\s\\p{L}\\p{N}]+|\\s+(?!\\S)|\\s+"""
    out, i, n = [], 0, len(text)
    cats = [_cat(ch) for ch in text]
    while i < n:
        ch = text[i]
        if ch == "'":
            hit = next((c for c in _CONTRACTIONS if text.startswith(c, i + 1)), None)
            if hit:
                out.append(text[i:i + 1 + len(hit)])
                i += 1 + len(hit)
                continue
        j = i + 1 if ch == " " and i + 1 < n and cats[i + 1] != "S" else i
        k = cats[j] if j < n else None
        if k in ("L", "N", "O") and not (j == i and k == "S"):
            e = j
            while e < n and cats[e] == k:
                e += 1
            out.append(text[i:e])
            i = e
            continue
        # whitespace: the run, minus its last character when a non-space follows
        e = i
        while e < n and cats[e] == "S":
            e += 1
        if e < n and e - i > 1:
            e -= 1
        out.append(text[i:e])
        i = e
    return out


class Tokenizer:
    def __init__(self, vocab, merges, added=()):
        self.vocab = vocab
        self.ranks = {tuple(m.split(" ", 1)) if isinstance(m, str) else tuple(m): r
                      for r, m in enumerate(merges)}
        self.added = sorted(added, key=lambda a: -len(a[0]))   # (content, id), longest first
        self.bytes = _byte_alphabet()
        self.cache = {}

    @classmethod
    def load(cls, path):
        with open(path, encoding="utf-8") as fh:
            t = json.load(fh)
        m, pre = t["model"], t.get("pre_tokenizer") or {}
        if (m.get("type") != "BPE" or t.get("normalizer") or m.get("byte_fallback")
                or pre.get("type") != "ByteLevel" or not pre.get("use_regex", True)
                or pre.get("add_prefix_space")):
            raise ValueError(f"{path}: not a plain byte-level BPE tokenizer")
        return cls(m["vocab"], m["merges"], [(a["content"], a["id"]) for a in t.get("added_tokens", [])])

    def _bpe(self, word):
        """Ids of one pre-token (already mapped to the byte alphabet)."""
        hit = self.cache.get(word)
        if hit is not None:
            return hit
        parts = list(word)
        while len(parts) > 1:
            best, at = None, -1
            for k in range(len(parts) - 1):
                r = self.ranks.get((parts[k], parts[k + 1]))
                if r is not None and (best is None or r < best):
                    best, at = r, k
            if best is None:
                break
            pair = (parts[at], parts[at + 1])
            merged, k = [], 0
            while k < len(parts):
                if k < len(parts) - 1 and (parts[k], parts[k + 1]) == pair:
                    merged.append(parts[k] + parts[k + 1])
                    k += 2
                else:
                    merged.append(parts[k])
                    k += 1
            parts = merged
        ids = [self.vocab[p] for p in parts]
        self.cache[word] = ids
        return ids

    def _plain(self, text):
        ids = []
        for word in split_gpt2(text):
            ids.extend(self._bpe("".join(self.bytes[b] for b in word.encode("utf-8"))))
        return ids

    def encode(self, text):
        """Token ids of text, no special tokens added (added tokens that occur
        in the text are still matched, as transformers does)."""
        if not self.added or not any(a in text for a, _ in self.added):
            return self._plain(text)
        ids, i, start = [], 0, 0
        while i < len(text):
            hit = next(((a, t) for a, t in self.added if text.startswith(a, i)), None)
            if hit:
                if start < i:
                    ids.extend(self._plain(text[start:i]))
                ids.append(hit[1])
                i += len(hit[0])
                start = i
            else:
                i += 1
        if start < len(text):
            ids.extend(self._plain(text[start:]))
        return ids

    def __call__(self, texts):
        """The Encoder's tokenize: a list of strings -> a list of id lists."""
        return [self.encode(t) for t in texts]
