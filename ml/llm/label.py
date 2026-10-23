# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Label corpus captures with Claude (the LLM teacher), via the Anthropic API.

    pip install anthropic                     # not needed anywhere else in provost
    export ANTHROPIC_API_KEY=...
    python3 ml/llm/label.py --names ml/llm/pilot-2026-10-23.txt          # one request each
    python3 ml/llm/label.py --all --batch                                # whole corpus, Batches API (half price)

Each capture is sent with GUIDE.md as the (cached) system prompt and its lines
numbered from 0; the reply is one JSON label, checked with check.py. A label
that fails the check is sent back once with the checker's complaints. Labels
land in ml/data/llm/<name>.json; token usage is appended to
ml/data/llm/usage.jsonl so the cost of a run can be read off it.
"""
import argparse
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import check  # noqa: E402

INPUTS = os.path.join(ROOT, "tests", "corpus", "inputs")
OUT = os.path.join(ROOT, "ml", "data", "llm")


def system_prompt():
    with open(os.path.join(HERE, "GUIDE.md"), encoding="utf-8") as fh:
        guide = fh.read()
    # the API run checks labels itself (and retries), so drop the tool step
    return guide.split("## Checking your work")[0].rstrip() + "\n"


def user_prompt(name, lines):
    w = len(str(max(0, len(lines) - 1)))
    body = "\n".join(f"{j:>{w}} |{t}" for j, t in enumerate(lines))
    return f"Tool: {name}\nLines: {len(lines)}\n\n{body}\n"


def parse_reply(msg):
    text = "".join(b.text for b in msg.content if b.type == "text").strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[1].rsplit("```", 1)[0]
    return json.loads(text)


def params(a, name, lines, retry=None):
    messages = [{"role": "user", "content": user_prompt(name, lines)}]
    if retry:
        prev, problems = retry
        messages += [{"role": "assistant", "content": json.dumps(prev)},
                     {"role": "user", "content": "The checker found these problems; reply with the "
                      "corrected JSON only:\n" + "\n".join(problems)}]
    return {"model": a.model, "max_tokens": a.max_tokens,
            "system": [{"type": "text", "text": system_prompt(),
                        "cache_control": {"type": "ephemeral"}}],
            "output_config": {"effort": a.effort},
            "messages": messages}


def create(client, p):
    """One request, streamed (the SDK requires it for large max_tokens)."""
    with client.messages.stream(**p) as stream:
        return stream.get_final_message()


def log_usage(name, msg, mode):
    u = msg.usage
    with open(os.path.join(OUT, "usage.jsonl"), "a", encoding="utf-8") as fh:
        fh.write(json.dumps({"name": name, "mode": mode, "model": msg.model,
                             "input": u.input_tokens, "output": u.output_tokens,
                             "cache_read": u.cache_read_input_tokens or 0,
                             "cache_write": u.cache_creation_input_tokens or 0}) + "\n")


def finish(client, a, name, lines, msg, mode):
    """Check a reply; retry once (synchronously) with the checker's problems."""
    log_usage(name, msg, mode)
    try:
        label = parse_reply(msg)
        problems = check.convert(label, lines)[2]
    except ValueError as exc:
        label, problems = {}, [f"reply is not valid JSON: {exc}"]
    if problems:
        msg = create(client, params(a, name, lines, retry=(label, problems)))
        log_usage(name, msg, "retry")
        try:
            label = parse_reply(msg)
            problems = check.convert(label, lines)[2]
        except ValueError as exc:
            problems = [f"reply is not valid JSON: {exc}"]
    label["_problems"] = problems
    with open(os.path.join(OUT, f"{name}.json"), "w", encoding="utf-8") as fh:
        json.dump(label, fh, ensure_ascii=False)
    return not problems


def main(argv=None):
    global OUT
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--names", help="file with one corpus tool name per line")
    g.add_argument("--all", action="store_true", help="every capture in tests/corpus/inputs")
    ap.add_argument("--model", default="claude-opus-5-5")
    ap.add_argument("--effort", default="medium", choices=["low", "medium", "high", "xhigh", "max"])
    ap.add_argument("--max-tokens", type=int, default=32000)
    ap.add_argument("--max-lines", type=int, default=600, help="skip longer captures")
    ap.add_argument("--batch", action="store_true", help="use the Message Batches API (half price)")
    ap.add_argument("--redo", action="store_true", help="relabel captures that already have a label")
    ap.add_argument("--out", default=OUT, help="where labels and usage.jsonl go (default ml/data/llm)")
    a = ap.parse_args(argv)

    import anthropic
    from anthropic.types.message_create_params import MessageCreateParamsNonStreaming
    from anthropic.types.messages.batch_create_params import Request

    OUT = a.out
    os.makedirs(OUT, exist_ok=True)
    if a.all:
        names = sorted(f[:-4] for f in os.listdir(INPUTS) if f.endswith(".txt"))
    else:
        names = [n for n in open(a.names, encoding="utf-8").read().split() if n]
    todo = {}
    for n in names:
        if not a.redo and os.path.exists(os.path.join(OUT, f"{n}.json")):
            continue
        lines = check.read_lines(os.path.join(INPUTS, f"{n}.txt"))
        if len(lines) <= a.max_lines:
            todo[n] = lines
    print(f"{len(todo)} captures to label", file=sys.stderr)
    client = anthropic.Anthropic()
    ok = 0
    if a.batch:
        batch = client.messages.batches.create(requests=[
            Request(custom_id=f"c{i}", params=MessageCreateParamsNonStreaming(**params(a, n, ln)))
            for i, (n, ln) in enumerate(todo.items())])
        ids = {f"c{i}": n for i, n in enumerate(todo)}
        print(f"batch {batch.id}", file=sys.stderr)
        while client.messages.batches.retrieve(batch.id).processing_status != "ended":
            time.sleep(60)
        for r in client.messages.batches.results(batch.id):
            n = ids[r.custom_id]
            if r.result.type == "succeeded":
                ok += finish(client, a, n, todo[n], r.result.message, "batch")
            else:
                print(f"{n}: {r.result.type}", file=sys.stderr)
    else:
        for n, ln in todo.items():
            ok += finish(client, a, n, ln, create(client, params(a, n, ln)), "sync")
    print(f"{ok}/{len(todo)} labels pass the checker", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
