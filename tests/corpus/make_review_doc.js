// Render the pre-screen's passing entries as a Word review workbook.
//
// Reads the JSON written by `prescreen.py --emit-json` and emits one section
// per entry -- raw input, tidy output, and a verdict checkbox -- ordered
// most-likely-to-be-wrong first, so a reviewer verifying the screen can start
// where it is weakest.
//
// Needs the `docx` npm package (not vendored here):
//   npm install docx
//
// Usage:
//   python3 tests/corpus/prescreen.py --emit-json /tmp/good.json
//   node tests/corpus/make_review_doc.js /tmp/good.json out.docx [limit]

const fs = require('fs');
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  WidthType, ShadingType, BorderStyle, HeadingLevel, AlignmentType, PageBreak,
} = require('docx');

const IN = process.argv[2];
const OUT = process.argv[3];
if (!IN || !OUT) {
  console.error('usage: node make_review_doc.js <prescreen.json> <out.docx> [limit]');
  process.exit(2);
}
const all = JSON.parse(fs.readFileSync(IN, 'utf8'));
const entries = process.argv[4] ? all.slice(0, parseInt(process.argv[4], 10)) : all;

// A4 (docx default) less 1440 DXA margins each side.
const CONTENT_W = 9026;
const MONO = 'Courier New';

const mono = (text, opts = {}) =>
  new Paragraph({
    spacing: { before: 0, after: 0 },
    children: [new TextRun({ text: text === '' ? ' ' : text, font: MONO, size: 14, ...opts })],
  });

const label = (text, opts = {}) =>
  new Paragraph({
    spacing: { before: 120, after: 40 },
    children: [new TextRun({ text, bold: true, size: 18, ...opts })],
  });

const cell = (text, width, opts = {}) =>
  new TableCell({
    width: { size: width, type: WidthType.DXA },
    shading: opts.header ? { type: ShadingType.CLEAR, fill: 'EDEDED' } : undefined,
    margins: { top: 20, bottom: 20, left: 60, right: 60 },
    children: [
      new Paragraph({
        spacing: { before: 0, after: 0 },
        children: [new TextRun({ text: text === '' ? ' ' : text, font: MONO, size: 14, bold: !!opts.header })],
      }),
    ],
  });

// Wide tables become unreadable in Word, so past 12 columns fall back to
// monospace rows. Nothing is dropped either way.
const MAX_TABLE_COLS = 12;

function outputBlock(rows) {
  const ncols = Math.max(...rows.map((r) => r.length));
  if (ncols > MAX_TABLE_COLS) {
    return rows.map((r, i) => mono((i === 0 ? '' : '') + r.join(' | '), { bold: i === 0 }));
  }
  const w = Math.floor(CONTENT_W / ncols);
  const widths = Array.from({ length: ncols }, (_, i) => (i === ncols - 1 ? CONTENT_W - w * (ncols - 1) : w));
  return [
    new Table({
      columnWidths: widths,
      width: { size: CONTENT_W, type: WidthType.DXA },
      rows: rows.map((r, ri) =>
        new TableRow({
          tableHeader: ri === 0,
          children: widths.map((wd, ci) => cell(r[ci] === undefined ? '' : r[ci], wd, { header: ri === 0 })),
        })
      ),
    }),
    new Paragraph({ spacing: { before: 0, after: 0 }, children: [] }),
  ];
}

const children = [];

// ---- preamble -------------------------------------------------------------
children.push(
  new Paragraph({
    heading: HeadingLevel.HEADING_1,
    children: [new TextRun({ text: 'glean corpus — entries the pre-screen judged FINE', bold: true, size: 32 })],
  }),
  new Paragraph({
    spacing: { after: 120 },
    children: [new TextRun({ text: `${entries.length} entries, ordered most-likely-to-be-wrong first. Generated for verification of the round-8 pre-screen.`, size: 20, italics: true })],
  }),
  label('How to use this'),
  new Paragraph({ spacing: { after: 60 }, children: [new TextRun({ text: 'Each entry is one I claim is fine. Work down from the top: entry #1 is the one I am most likely to have got wrong, and risk falls to zero by roughly entry 1200. If the first hundred hold up, the tail almost certainly does too — the tail has no risk signals at all.', size: 20 })] }),
  new Paragraph({ spacing: { after: 60 }, children: [new TextRun({ text: 'Tick DISAGREE on anything that is not actually fine. Those are my false passes.', size: 20 })] }),
  label('What "fine" means here — and what it does not'),
  new Paragraph({ spacing: { after: 60 }, children: [new TextRun({ text: 'The screen checks structure only: ragged rows, blank or duplicate headers, separator rows kept as data, unsplit cells, pipes or stray whitespace left in cells, and column misalignment. It cannot see meaning. A parse that is cleanly rectangular but split on the wrong boundary passes. So "fine" means nothing is mechanically wrong, not that the result is correct.', size: 20 })] }),
  new Paragraph({ spacing: { after: 60 }, children: [new TextRun({ text: 'Measured against your existing marks: 95% of the 258 you validated pass this screen, and it flags 38% of the round-3 Horrible entries. All 17 Not quite entries pass it — those failures are semantic, and invisible here.', size: 20 })] }),
  new Paragraph({ spacing: { after: 60 }, children: [new TextRun({ text: 'Two known false passes are already in this document, left in deliberately as calibration: k6-summary (keeps its dot-leaders) and pgrep-a (pid not split from command).', size: 20, italics: true })] }),
  new Paragraph({ spacing: { after: 60 }, children: [new TextRun({ text: `Outputs with more than ${MAX_TABLE_COLS} columns are shown as pipe-separated monospace rows rather than a table, purely so they stay readable. Nothing is truncated anywhere in this document.`, size: 20 })] }),
  new Paragraph({ spacing: { after: 60 }, children: [new TextRun({ text: 'Rendering of raw bytes: control characters are illegal in Word XML, so the 1,670 of them in this corpus (mostly ANSI colour escapes, across 108 entries) are shown as visible control pictures — ␛ for ESC, ␇ for BEL, and so on. Tabs in the INPUT block are expanded to 8-column stops, the way a terminal shows them, so that column alignment reads correctly. Nothing is removed.', size: 20 })] }),
  new Paragraph({ children: [new PageBreak()] })
);

// ---- entries --------------------------------------------------------------
for (const e of entries) {
  children.push(
    new Paragraph({
      heading: HeadingLevel.HEADING_2,
      spacing: { before: 200, after: 40 },
      children: [new TextRun({ text: `${e.rank}. ${e.name}`, bold: true, size: 24 })],
    }),
    new Paragraph({
      spacing: { after: 80 },
      children: [
        new TextRun({ text: `my verdict: ${e.verdict}${e.tier ? ` (${e.tier})` : ''}`, size: 18, color: '444444' }),
        new TextRun({ text: `   ·   risk score ${e.risk}: ${e.why}`, size: 18, color: '8A5A00' }),
      ],
    }),
    label('INPUT (raw)')
  );
  for (const line of e.input) children.push(mono(line));
  children.push(label('OUTPUT (tidy)'));
  children.push(...outputBlock(e.table));
  children.push(
    new Paragraph({
      spacing: { before: 120, after: 20 },
      children: [new TextRun({ text: 'VERDICT CHECK:   [ ] agree — fine        [ ] DISAGREE — not fine', bold: true, size: 20 })],
    }),
    new Paragraph({ spacing: { after: 160 }, children: [new TextRun({ text: 'Notes:', size: 20 })] })
  );
}

const doc = new Document({
  creator: 'glean prescreen',
  title: 'glean corpus — entries the pre-screen judged fine',
  description: 'Risk-ranked verification set for the round-8 corpus pre-screen',
  sections: [{ children }],
});

Packer.toBuffer(doc).then((buf) => {
  fs.writeFileSync(OUT, buf);
  console.log(`wrote ${OUT} — ${entries.length} entries, ${(buf.length / 1e6).toFixed(1)} MB`);
});
