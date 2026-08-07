const fs = require('fs');
const { Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
        WidthType, ShadingType, HeadingLevel, PageBreak } = require('docx');
const IN = process.argv[2], OUT = process.argv[3];
const entries = JSON.parse(fs.readFileSync(IN, 'utf8'));
const MONO = 'Courier New', CONTENT_W = 9026;
const mono = (t) => new Paragraph({ spacing:{before:0,after:0},
  children:[new TextRun({ text: t===''?' ':t, font:MONO, size:14 })] });
const label = (t,c) => new Paragraph({ spacing:{before:120,after:40},
  children:[new TextRun({ text:t, bold:true, size:18, color:c })] });
const cell = (t,w,o={}) => new TableCell({ width:{size:w,type:WidthType.DXA},
  shading: o.header?{type:ShadingType.CLEAR,fill:'EDEDED'}:undefined,
  margins:{top:20,bottom:20,left:o.marg??60,right:o.marg??60},
  children:[new Paragraph({ spacing:{before:0,after:0},
    children:[new TextRun({ text:t===''?' ':t, font:MONO, size:o.size??14, bold:!!o.header })] })] });
// Every output renders as a REAL Word table, however wide.
function outputBlock(rows){
  const ncols = Math.max(...rows.map(r=>r.length));
  const size = ncols>20?10:ncols>12?12:14, marg = ncols>12?30:60;
  const colW = Math.max(620, Math.floor(CONTENT_W/ncols));
  const widths = Array.from({length:ncols},()=>colW);
  return [new Table({ columnWidths:widths, width:{size:colW*ncols,type:WidthType.DXA},
    rows: rows.map((r,ri)=> new TableRow({ tableHeader: ri===0,
      children: widths.map((w,ci)=> cell(r[ci]===undefined?'':r[ci], w, {header:ri===0,size,marg})) })) }),
    new Paragraph({ spacing:{before:0,after:0}, children:[] })];
}
const children = [];
children.push(
  new Paragraph({ heading:HeadingLevel.HEADING_1,
    children:[new TextRun({ text:'glean — inputs that hold MULTIPLE datasets', bold:true, size:32 })] }),
  new Paragraph({ spacing:{after:120},
    children:[new TextRun({ text:`The first ${entries.length} corpus inputs (alphabetical) that split into more than one dataset under 'glean --multi'. 412 of 3,705 inputs do.`, size:20, italics:true })] }),
  label('What you are looking at'),
  new Paragraph({ spacing:{after:60}, children:[new TextRun({ text:'Each entry shows the raw input, then EVERY dataset --multi splits it into, in order, each as its own table with the strategy that won it and its confidence.', size:20 })] }),
  new Paragraph({ spacing:{after:60}, children:[new TextRun({ text:"A 'text' dataset is a comment or legend run kept VERBATIM (one lineN field per line) rather than forced through a parser.", size:20 })] }),
  new Paragraph({ spacing:{after:60}, children:[new TextRun({ text:'Three verdicts: agree; SPLIT OK BUT FORMATTING OFF (the boundaries are right, a piece is parsed badly); or DISAGREE (the split itself is wrong). Say in Notes what it should be.', size:20 })] }),
  new Paragraph({ children:[new PageBreak()] }));
for (const e of entries) {
  children.push(
    new Paragraph({ heading:HeadingLevel.HEADING_2, spacing:{before:200,after:40},
      children:[new TextRun({ text:`${e.rank}. ${e.name}`, bold:true, size:24 })] }),
    new Paragraph({ spacing:{after:80},
      children:[new TextRun({ text:`splits into ${e.n} datasets`, size:18, color:'8A5A00' }),
        ...(e.prior ? [new TextRun({ text:`   ·   you already marked this: ${e.prior==='agree'?'AGREE':'DISAGREE'}${e.priornote?' — '+e.priornote:''}`, size:18, color:'B03060', bold:true })] : [])] }),
    label('INPUT (raw)'));
  for (const l of e.input) children.push(mono(l));
  e.datasets.forEach((d,i) => {
    children.push(label(`DATASET ${i+1} of ${e.n} — ${d.strategy} (confidence ${d.conf})`, '1F5C99'));
    if (d.table && d.table.length) children.push(...outputBlock(d.table));
    else children.push(mono('(no rows)'));
  });
  children.push(
    new Paragraph({ spacing:{before:120,after:4},
      children:[new TextRun({ text:'VERDICT CHECK:', bold:true, size:20 })] }),
    new Paragraph({ spacing:{before:0,after:4},
      children:[new TextRun({ text:'   [ ] agree — split is right, output is right', size:20 })] }),
    new Paragraph({ spacing:{before:0,after:4},
      children:[new TextRun({ text:'   [ ] SPLIT OK, FORMATTING OFF — the pieces are right, but one or more is parsed badly', size:20 })] }),
    new Paragraph({ spacing:{before:0,after:20},
      children:[new TextRun({ text:'   [ ] DISAGREE — wrong split (too many pieces, too few, or a boundary in the wrong place)', size:20 })] }),
    new Paragraph({ spacing:{after:160}, children:[new TextRun({ text:'Notes:', size:20 })] }));
}
Packer.toBuffer(new Document({ creator:'glean', title:'glean — multi-dataset inputs', sections:[{children}] }))
  .then(b => { fs.writeFileSync(OUT,b); console.log(`wrote ${OUT} — ${entries.length} entries, ${(b.length/1e6).toFixed(2)} MB`); });
