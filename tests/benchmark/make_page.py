#!/usr/bin/env python3
"""tests/benchmark/make_page.py — render the held-out benchmark as one HTML page.

    python3 tests/benchmark/make_page.py bench.json out.html

Same source JSON as the .docx builder (tests/benchmark/make_doc_json.sh), a
different reading posture: the document is for marking up line by line, the page
is for seeing the shape of the result and jumping straight to the failures.

The page is self-contained — no external CSS, fonts, or scripts — because
published artifacts run under a CSP that blocks every external host.
"""
import html
import json
import sys

IN, OUT = sys.argv[1], sys.argv[2]
entries = json.load(open(IN))

# A case's input and output are shown whole where they fit and clipped where
# they do not: the page's job is the shape of the parse, and the .docx carries
# the full text for anyone who needs to check a specific row.
MAX_IN, MAX_ROWS = 22, 15

e_ = html.escape


def tally(k):
    return sum(1 for x in entries if x["rating"] == k)


N = len(entries)
NP, NA, NF = tally("PASS"), tally("PARTIAL"), tally("FAIL")

CLUSTERS = [
    ("truncation", "a strategy claims the input and emits a fraction of it",
     "the only failure that is both silent and catastrophic"),
    ("banner", "a leading or trailing line with no <code>key:</code> is dropped",
     "usually the version line — the one a reader came for"),
    ("box-rules", "<code>─</code> and <code>━</code> rules are not read as separators",
     "so the table never parses at all and falls to verbatim lines"),
    ("dropped-line", "a detail line outside the main record is discarded",
     "MAC addresses, <code>Service Info:</code>, summary counts"),
    ("blank-column", "empty columns collapse; values land under the wrong names",
     "the output looks perfectly tidy and is wrong"),
    ("csv-on-date", "<code>Mon, 2016-02-15</code> reads as 2-field CSV",
     "the split lands inside the timestamp"),
    ("group-header", "a two-row header defeats the column split", ""),
    ("dropped-unit", "a unit or a time component is silently discarded", ""),
]


def cluster_count(name):
    return sum(1 for x in entries if x.get("cluster") == name)


def table_html(rows):
    if not rows:
        return '<p class="empty">no rows</p>'
    head, body = rows[0], rows[1:]
    clipped = len(body) > MAX_ROWS
    shown = body[:MAX_ROWS]
    th = "".join(f"<th>{e_(c)}</th>" for c in head)
    trs = "".join(
        "<tr>" + "".join(f"<td>{e_(c)}</td>" for c in r) + "</tr>" for r in shown)
    more = (f'<p class="clip">+{len(body) - MAX_ROWS} more rows</p>'
            if clipped else "")
    return f'<div class="scroll"><table><thead><tr>{th}</tr></thead><tbody>{trs}</tbody></table></div>{more}'


def case_html(e):
    r = e["rating"]
    lines = e["input"][:MAX_IN]
    clip = (f'<span class="clip">… {len(e["input"]) - MAX_IN} more lines</span>'
            if len(e["input"]) > MAX_IN else "")
    multi = ""
    for i, d in enumerate(e.get("multi_datasets") or []):
        multi += (f'<p class="dslabel">dataset {i + 1} — <span class="strat">'
                  f'{e_(d["strategy"])}</span> <span class="conf">{d["conf"]}</span></p>'
                  + table_html(d["table"]))
    if multi:
        verdict = "better than default" if e["multi"] == "better" else "worse than default"
        multi = (f'<div class="panel multi"><p class="plabel">with <code>--multi</code>'
                 f' <span class="tag">{verdict}</span></p>{multi}</div>')
    return f"""
<article class="case {r.lower()}" data-rating="{r}" id="c{e['rank']}">
  <header class="chead">
    <span class="rank">{e['rank']}</span>
    <h3>{e_(e['name'])}</h3>
    <span class="chip {r.lower()}">{r}</span>
    <span class="strat">{e_(e['strategy'])}</span><span class="conf">{e['conf']}</span>
  </header>
  <p class="note">{e_(e['note'])}</p>
  <div class="panels">
    <div class="panel"><p class="plabel">input</p>
      <div class="scroll"><pre>{e_(chr(10).join(lines))}</pre></div>{clip}</div>
    <div class="panel"><p class="plabel">output <span class="tag">default mode</span></p>
      {table_html(e['table'])}</div>
  </div>
  {multi}
</article>"""


cluster_rows = "".join(
    f'<tr><td class="cname">{name}</td><td class="cnum">{cluster_count(name)}</td>'
    f'<td>{what}{f"<span class=cwhy>{why}</span>" if why else ""}</td></tr>'
    for name, what, why in CLUSTERS)

cases = "".join(case_html(e) for e in entries)

doc = f"""<title>Fifty Unseen Outputs</title>
<style>
:root {{
  --paper:#F1F2F4; --surface:#FFFFFF; --surface-2:#F8F9FA; --sunken:#EDEFF2;
  --ink:#181B20; --ink-2:#525C69; --ink-3:#7C8794;
  --rule:#D6DAE0; --rule-soft:#E6E9ED;
  --accent:#2B3A80;
  --pass:#1C6437; --partial:#7E5310; --fail:#9B2743;
  --pass-bg:#E3EFE7; --partial-bg:#F5EBDA; --fail-bg:#F6E2E7;
  --serif:"Iowan Old Style","Palatino Linotype",Palatino,"Book Antiqua",Georgia,serif;
  --mono:ui-monospace,"SF Mono",SFMono-Regular,Menlo,Consolas,"Liberation Mono",monospace;
}}
@media (prefers-color-scheme:dark) {{
  :root:not([data-theme="light"]) {{
    --paper:#0F1216; --surface:#171B21; --surface-2:#1B2027; --sunken:#101419;
    --ink:#E7EAEE; --ink-2:#9BA5B2; --ink-3:#77828F;
    --rule:#2A313A; --rule-soft:#222831;
    --accent:#9FADF2;
    --pass:#74CE96; --partial:#DDAF63; --fail:#EF8199;
    --pass-bg:#15261C; --partial-bg:#272014; --fail-bg:#2A171E;
  }}
}}
:root[data-theme="dark"] {{
  --paper:#0F1216; --surface:#171B21; --surface-2:#1B2027; --sunken:#101419;
  --ink:#E7EAEE; --ink-2:#9BA5B2; --ink-3:#77828F;
  --rule:#2A313A; --rule-soft:#222831;
  --accent:#9FADF2;
  --pass:#74CE96; --partial:#DDAF63; --fail:#EF8199;
  --pass-bg:#15261C; --partial-bg:#272014; --fail-bg:#2A171E;
}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--paper);color:var(--ink);
  font:400 17px/1.6 var(--serif);-webkit-font-smoothing:antialiased}}
.wrap{{max-width:1120px;margin:0 auto;padding:0 24px 96px}}
.prose{{max-width:68ch}}
h1,h2,h3{{text-wrap:balance;margin:0}}
code{{font-family:var(--mono);font-size:.86em;background:var(--sunken);
  padding:.08em .3em;border-radius:2px}}

/* masthead ---------------------------------------------------------------- */
header.top{{border-bottom:1px solid var(--rule);padding:56px 0 34px;margin-bottom:38px}}
.eyebrow{{font:600 11px/1 var(--mono);letter-spacing:.16em;text-transform:uppercase;
  color:var(--ink-3);margin:0 0 18px}}
h1{{font-size:clamp(34px,5.4vw,54px);line-height:1.04;letter-spacing:-.018em;font-weight:600}}
.dek{{margin:18px 0 0;font-size:19px;color:var(--ink-2);max-width:62ch}}

/* score ------------------------------------------------------------------- */
.score{{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));
  gap:14px;margin:32px 0 10px}}
.stat{{background:var(--surface);border:1px solid var(--rule);border-radius:3px;
  padding:18px 20px;border-top:3px solid var(--bar)}}
.stat.p{{--bar:var(--pass)}} .stat.a{{--bar:var(--partial)}} .stat.f{{--bar:var(--fail)}}
.stat .n{{font:600 40px/1 var(--mono);font-variant-numeric:tabular-nums;letter-spacing:-.03em}}
.stat.p .n{{color:var(--pass)}} .stat.a .n{{color:var(--partial)}} .stat.f .n{{color:var(--fail)}}
.stat .k{{font:600 11px/1 var(--mono);letter-spacing:.14em;text-transform:uppercase;
  color:var(--ink-3);margin:12px 0 6px}}
.stat .d{{font-size:14.5px;color:var(--ink-2);line-height:1.45}}

/* bar --------------------------------------------------------------------- */
.bar{{display:flex;height:9px;border-radius:2px;overflow:hidden;margin:16px 0 6px;
  border:1px solid var(--rule)}}
.bar i{{display:block}}
.bar .p{{background:var(--pass)}} .bar .a{{background:var(--partial)}} .bar .f{{background:var(--fail)}}
.barkey{{font:11px/1 var(--mono);letter-spacing:.09em;color:var(--ink-3);
  text-transform:uppercase;margin:0 0 34px}}

section{{margin:44px 0}}
h2{{font-size:27px;font-weight:600;letter-spacing:-.012em;margin-bottom:6px}}
.h2sub{{color:var(--ink-2);font-size:15.5px;margin:0 0 20px}}
p{{margin:0 0 14px}}

/* criteria ---------------------------------------------------------------- */
dl.crit{{margin:0;display:grid;grid-template-columns:auto 1fr;gap:12px 20px;align-items:baseline}}
dl.crit dt{{font:600 12px/1.4 var(--mono);letter-spacing:.1em;padding-top:3px}}
dl.crit dt.p{{color:var(--pass)}} dl.crit dt.a{{color:var(--partial)}} dl.crit dt.f{{color:var(--fail)}}
dl.crit dd{{margin:0;color:var(--ink-2);font-size:16px}}

/* cluster table ----------------------------------------------------------- */
table.cl{{width:100%;border-collapse:collapse;font-size:15.5px}}
table.cl td{{border-top:1px solid var(--rule-soft);padding:11px 12px 11px 0;
  vertical-align:baseline;color:var(--ink-2)}}
table.cl .cname{{font:600 13px/1.5 var(--mono);color:var(--ink);white-space:nowrap;
  width:1%;padding-right:22px}}
table.cl .cnum{{font:600 15px/1.5 var(--mono);font-variant-numeric:tabular-nums;
  color:var(--ink);width:1%;padding-right:22px;text-align:right}}
.cwhy{{display:block;color:var(--ink-3);font-size:14px;margin-top:2px;font-style:italic}}

/* filter ------------------------------------------------------------------ */
.filter{{position:sticky;top:0;z-index:5;background:var(--paper);
  border-bottom:1px solid var(--rule);padding:12px 0;display:flex;gap:8px;
  flex-wrap:wrap;align-items:center;margin-bottom:10px}}
.filter span.lab{{font:600 11px/1 var(--mono);letter-spacing:.14em;text-transform:uppercase;
  color:var(--ink-3);margin-right:4px}}
button.f{{font:600 12px/1 var(--mono);letter-spacing:.06em;padding:8px 13px;cursor:pointer;
  background:var(--surface);color:var(--ink-2);border:1px solid var(--rule);border-radius:2px}}
button.f:hover{{border-color:var(--ink-3);color:var(--ink)}}
button.f[aria-pressed="true"]{{background:var(--ink);color:var(--paper);border-color:var(--ink)}}
button.f:focus-visible{{outline:2px solid var(--accent);outline-offset:2px}}

/* case -------------------------------------------------------------------- */
.case{{background:var(--surface);border:1px solid var(--rule);border-left:3px solid var(--edge);
  border-radius:3px;padding:20px 22px;margin:0 0 16px}}
.case.pass{{--edge:var(--pass)}} .case.partial{{--edge:var(--partial)}} .case.fail{{--edge:var(--fail)}}
.case[hidden]{{display:none}}
.chead{{display:flex;align-items:center;gap:11px;flex-wrap:wrap;margin-bottom:9px}}
.chead h3{{font:600 19px/1.25 var(--serif);letter-spacing:-.008em}}
.rank{{font:600 12px/1 var(--mono);color:var(--ink-3);font-variant-numeric:tabular-nums}}
.chip{{font:600 10.5px/1 var(--mono);letter-spacing:.12em;padding:5px 8px;border-radius:2px}}
.chip.pass{{background:var(--pass-bg);color:var(--pass)}}
.chip.partial{{background:var(--partial-bg);color:var(--partial)}}
.chip.fail{{background:var(--fail-bg);color:var(--fail)}}
.strat{{font:12px/1 var(--mono);color:var(--ink-3)}}
.conf{{font:12px/1 var(--mono);color:var(--ink-3);
  border:1px solid var(--rule);border-radius:2px;padding:3px 5px}}
.note{{color:var(--ink-2);font-size:15.5px;margin:0 0 15px;max-width:82ch}}
.panels{{display:grid;grid-template-columns:1fr 1fr;gap:16px}}
@media (max-width:820px){{.panels{{grid-template-columns:1fr}}}}
.panel{{min-width:0}}
.panel.multi{{margin-top:16px;border-top:1px dashed var(--rule);padding-top:14px}}
.plabel{{font:600 10.5px/1 var(--mono);letter-spacing:.14em;text-transform:uppercase;
  color:var(--ink-3);margin:0 0 8px;display:flex;gap:8px;align-items:center;flex-wrap:wrap}}
.dslabel{{font:11px/1 var(--mono);color:var(--ink-3);margin:12px 0 6px}}
.tag{{font:600 10px/1 var(--mono);letter-spacing:.08em;text-transform:none;
  background:var(--sunken);color:var(--ink-3);padding:4px 6px;border-radius:2px}}
.scroll{{overflow-x:auto;background:var(--surface-2);border:1px solid var(--rule-soft);
  border-radius:2px}}
pre{{margin:0;padding:11px 13px;font:12px/1.55 var(--mono);white-space:pre;color:var(--ink)}}
.panel table{{border-collapse:collapse;font:12px/1.5 var(--mono);
  font-variant-numeric:tabular-nums;width:100%}}
.panel th{{text-align:left;background:var(--sunken);color:var(--ink);font-weight:600;
  padding:6px 10px;white-space:nowrap;border-bottom:1px solid var(--rule)}}
.panel td{{padding:5px 10px;white-space:nowrap;color:var(--ink-2);
  border-bottom:1px solid var(--rule-soft)}}
.panel tr:last-child td{{border-bottom:0}}
.clip{{font:11px/1.4 var(--mono);color:var(--ink-3);margin:6px 0 0}}
.empty{{font:12px/1.4 var(--mono);color:var(--ink-3);margin:0;padding:10px 12px;
  background:var(--surface-2);border:1px solid var(--rule-soft);border-radius:2px}}

.caveat{{border-left:3px solid var(--accent);background:var(--surface);
  padding:16px 20px;border-radius:0 3px 3px 0;margin:30px 0}}
.caveat p:last-child{{margin:0}}
footer{{border-top:1px solid var(--rule);margin-top:52px;padding-top:22px;
  font-size:14.5px;color:var(--ink-3)}}
</style>

<div class="wrap">
<header class="top">
  <p class="eyebrow">provost · held-out benchmark · 12–13 august 2026</p>
  <h1>Fifty outputs it had never seen</h1>
  <p class="dek">Tool output with no hint row, no strategy, no golden and no prior
  review, run through <code>provost</code> in default mode. The corpus measures whether
  known inputs still work. This measures whether unknown ones ever did.</p>
</header>

<div class="score">
  <div class="stat p"><div class="n">{NP}</div><p class="k">pass</p>
    <p class="d">Everything present, everything in the right column.</p></div>
  <div class="stat a"><div class="n">{NA}</div><p class="k">partial</p>
    <p class="d">Broadly right; something lost or mis-shaped.</p></div>
  <div class="stat f"><div class="n">{NF}</div><p class="k">fail</p>
    <p class="d">The output misrepresents the input.</p></div>
</div>
<div class="bar">
  <i class="p" style="flex:{NP}"></i><i class="a" style="flex:{NA}"></i><i class="f" style="flex:{NF}"></i>
</div>
<p class="barkey">{NP} pass · {NA} partial · {NF} fail · {N} inputs</p>

<section class="prose">
  <h2>The short answer</h2>
  <p><strong>When these fifty inputs were genuinely unseen (12 August), the score
  was 23 pass / 12 partial / 15 fail</strong> — roughly seven in ten usable, three in
  ten wrong, materially worse than the corpus score suggests. That 23/12/15
  remains the only honest generalisation number this set ever produced.</p>
  <p>The fix round on 13 August then worked all nine defect clusters — a
  truncation guard, character-offset column assignment, Unicode rule handling,
  keep-everything changes to the fallback parsers, and four narrow strategies.
  The tallies above are the current state. <strong>But the moment the engine was
  tuned against these files they stopped measuring generalisation</strong>; from here
  on this set measures regression, and the next generalisation number needs a
  fresh fifty.</p>
</section>

<section class="prose">
  <h2>Where the inputs came from</h2>
  <p>Fourteen from public documentation and sample data — <code>tokei</code> and
  <code>scc</code> summaries, <code>rclone about</code>, <code>borg list</code> in
  both forms, three nmap scans, an ASCII table with a decorative header and
  footer, a quoted CSV, <code>/etc/hosts</code>, an INI file, an ARP table.
  Thirty-six captured live from this machine, chosen for shape variety rather
  than convenience: aligned tables with and without headers, colon and equals
  key/value, JSON, TSV, hierarchies, box drawings, two-row headers, multi-record
  logs.</p>
  <p>There was deliberately no pass/fail gate on this set — a gate invites
  fitting the engine to the files. The fix round then did exactly that, with
  eyes open: the price of clearing the defects is that these fifty now measure
  memorisation, which is why the 23/12/15 measured before any tuning is the
  number to quote for generalisation.</p>
</section>

<section class="prose">
  <h2>How each one was rated</h2>
  <p class="h2sub">Written down before the first input was executed, so a
  disappointing result could not be reclassified into a better one.</p>
  <dl class="crit">
    <dt class="p">PASS</dt>
    <dd>Everything in the input is present <em>and</em> correctly structured: real
    column names where the input supplies them, values under the right column,
    prose not sliced one word per column, nothing dropped.</dd>
    <dt class="a">PARTIAL</dt>
    <dd>Structure broadly right, but something is lost or mis-shaped — a header not
    applied, a line dropped, a value split or merged.</dd>
    <dt class="f">FAIL</dt>
    <dd>The output misrepresents the input: values under the wrong column names, a
    table shredded, or a substantial part missing.</dd>
  </dl>
  <p style="margin-top:18px">Where an input genuinely has no header —
  <code>getent passwd</code>, <code>du</code>, <code>wc</code>,
  <code>/etc/hosts</code> — generic A/B/C column names are the honest answer and
  were rated PASS, not marked down.</p>
</section>

<div class="caveat prose">
  <p><strong>This is a self-assessment, and I wrote the engine being rated.</strong>
  It is a screen, not a verdict. The human review rounds remain the real measure,
  and the two disagree often enough to matter — a rating you overturn is worth
  more than one you accept.</p>
</div>

<section>
  <h2>The 27 defects are 9 problems</h2>
  <p class="h2sub prose">The failures are not fifty separate bugs. The top four
  clusters account for fifteen of the twenty-seven.</p>
  <div class="scroll"><table class="cl"><tbody>{cluster_rows}</tbody></table></div>
</section>

<section class="prose">
  <h2>What the fixes were (13 August)</h2>
  <p><strong>Truncation</strong> got a guard: a strategy whose parse is much smaller
  than its input and blind to most of its lines loses its claim, and the next
  parser runs — <code>git log --stat</code> went from 3 fields kept to all 40
  lines kept. <strong>Blank-column collapse</strong> got character-offset
  assignment: where data rows are sparser than the header, values are placed by
  the header label&#8217;s printed span — <code>lsblk</code> sizes now sit under
  FSAVAIL, <code>lsof</code> paths under NAME. Both mechanisms withdraw on weak
  evidence rather than guess. The rest: box-drawing rules read as separators
  (tokei, scc), fallback parsers keep what they cannot parse instead of dropping
  it (curl/gcc/openssl banners, locale&#8217;s empty values, cipher names),
  weekday commas stopped reading as CSV (borg), and uname, /proc/net/dev, stat
  and <code>ps f</code> got narrow parsers for their fixed shapes.</p>
  <p>The blast radius mattered as much as the fixes: 173 corpus goldens were
  regenerated, and the recurring finding was goldens that had been faithfully
  recording defects — conntrack&#8217;s golden dropped protocol and state from
  every row; a fixture literally named <code>tbl-empty-label-col</code> held
  sizes under LABEL. Six tools newly reach a tidy golden. The corpus gate closed
  at 3470 passed, 0 failed, zero deleted goldens.</p>
</section>

<section class="prose">
  <h2>What the original run said to fix first</h2>
  <p><strong>Truncation is the most damaging</strong>, because it is silent.
  <code>git log --stat</code> goes in at 40 lines and comes out at 3.
  <code>java -XshowSettings</code> goes in at 24 and comes out at 2.
  <code>apt-cache policy</code> goes in at 14 and comes out at 4. In each case a
  strategy detected with high confidence, claimed the whole input, and then
  produced almost nothing — with no signal that anything was missing. A parse
  dramatically shorter than its input is a reliable tell, and the engine does not
  currently look for it. That check needs no new parsing logic at all, only a
  comparison of numbers it already has.</p>
  <p><strong>Blank-column collapse is the most insidious</strong>, because the
  output looks perfectly tidy while being wrong. <code>lsblk -f</code> prints
  eight columns of which five are empty on every row; the surviving values are
  assigned to the first names in the header rather than their own, so sizes
  appear under <code>FSTYPE</code> and mountpoints under <code>LABEL</code>.
  <code>lsof</code> is the same defect and worse. Nothing in the output betrays
  the error. The fix is to split on the header's character offsets rather than
  count whitespace-separated fields.</p>
  <p>One bright spot: <code>--multi</code> already rescues three of the fifteen
  failures and never made one worse. The decorated ASCII table is the cleanest
  demonstration — default mode shreds the <code>### header ###</code> one word per
  column and never applies <code>col1 col2</code>, while <code>--multi</code>
  returns three datasets with a correct two-column table in the middle. That is an
  argument for segmentation sitting closer to the default than it does.</p>
</section>

<section>
  <h2>All fifty</h2>
  <p class="h2sub prose">Input on the left, what provost made of it on the right.
  Long inputs and tables are clipped here; the full text is in the review
  document.</p>
  <div class="filter">
    <span class="lab">show</span>
    <button class="f" data-f="all" aria-pressed="true">all {N}</button>
    <button class="f" data-f="FAIL" aria-pressed="false">fail {NF}</button>
    <button class="f" data-f="PARTIAL" aria-pressed="false">partial {NA}</button>
    <button class="f" data-f="PASS" aria-pressed="false">pass {NP}</button>
  </div>
  {cases}
</section>

<footer class="prose">
  <p>Inputs, runner and ratings live in <code>tests/benchmark/</code>. Re-run with
  <code>bash tests/benchmark/run.sh</code> and read the diff — nothing is
  asserted.</p>
</footer>
</div>

<script>
const btns = document.querySelectorAll('button.f');
const cases = document.querySelectorAll('.case');
btns.forEach(b => b.addEventListener('click', () => {{
  const want = b.dataset.f;
  btns.forEach(o => o.setAttribute('aria-pressed', String(o === b)));
  cases.forEach(c => {{ c.hidden = !(want === 'all' || c.dataset.rating === want); }});
}}));
</script>
"""

open(OUT, "w").write(doc)
print(f"wrote {OUT} ({len(doc) / 1024:.0f} KB, {N} cases)")
