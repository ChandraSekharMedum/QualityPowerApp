// md2docx.js -- convert a Markdown file to a real .docx (OOXML), no dependencies.
//
// Written because this machine has no Word COM, no pandoc and no LibreOffice, and the
// deployment document needed to go to a customer as a Word file.
//
// A .docx is a zip of XML parts. This emits the parts to a directory; the caller zips it
// (Compress-Archive / ZipFile::CreateFromDirectory) and renames to .docx.
//
// Deliberately uses DIRECT formatting rather than named styles, so no styles.xml is needed
// and the output does not depend on a template being present.
//
// Supports the subset the project's docs actually use: h1-h4, paragraphs with **bold** and
// `code`, tables, bullet lists, blockquotes, fenced code blocks, horizontal rules.
//
// Usage: node md2docx.js <input.md> <outputPartsDir> ["Document Title"]

const fs = require('fs');
const path = require('path');

const [, , inPath, outDir, docTitle] = process.argv;
if (!inPath || !outDir) {
  console.error('usage: node md2docx.js <input.md> <outputPartsDir> ["Title"]');
  process.exit(1);
}

const esc = (s) => String(s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

// ---------------------------------------------------------------- inline runs
// Splits a line into runs, honouring **bold** and `code`. Links are rendered as plain
// text: a real w:hyperlink needs an entry in document.xml.rels per link, and the value
// here is a readable document, not clickable chrome.
function runs(text, base = {}) {
  const out = [];
  const re = /(\*\*[^*]+\*\*|`[^`]+`)/g;
  let last = 0, m;
  const push = (t, opts) => {
    if (!t) return;
    const rPr = [];
    if (opts.bold || base.bold) rPr.push('<w:b/>');
    if (opts.code) rPr.push('<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/>');
    if (opts.code) rPr.push('<w:sz w:val="18"/>');
    else if (base.sz) rPr.push(`<w:sz w:val="${base.sz}"/>`);
    if (opts.code) rPr.push('<w:color w:val="B03A2E"/>');
    else if (base.color) rPr.push(`<w:color w:val="${base.color}"/>`);
    if (base.italic) rPr.push('<w:i/>');
    const pr = rPr.length ? `<w:rPr>${rPr.join('')}</w:rPr>` : '';
    out.push(`<w:r>${pr}<w:t xml:space="preserve">${esc(t)}</w:t></w:r>`);
  };
  while ((m = re.exec(text)) !== null) {
    push(text.slice(last, m.index), {});
    const tok = m[0];
    if (tok.startsWith('**')) push(tok.slice(2, -2), { bold: true });
    else push(tok.slice(1, -1), { code: true });
    last = re.lastIndex;
  }
  push(text.slice(last), {});
  return out.join('');
}

const para = (content, pPr = '') => `<w:p>${pPr ? `<w:pPr>${pPr}</w:pPr>` : ''}${content}</w:p>`;

function heading(text, level) {
  const sizes = { 1: 36, 2: 28, 3: 24, 4: 22 };
  const colors = { 1: '0D6273', 2: '0D6273', 3: '2C3E50', 4: '2C3E50' };
  const before = level === 1 ? 0 : 320;
  const pPr = `<w:spacing w:before="${before}" w:after="140"/><w:keepNext/>`;
  const rPr = `<w:rPr><w:b/><w:sz w:val="${sizes[level]}"/><w:color w:val="${colors[level]}"/></w:rPr>`;
  const body = `<w:r>${rPr}<w:t xml:space="preserve">${esc(text.replace(/`/g, ''))}</w:t></w:r>`;
  return para(body, pPr);
}

function hr() {
  return para('', '<w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="BDC3C7"/></w:pBdr><w:spacing w:before="160" w:after="160"/>');
}

function cell(text, isHeader, widthPct) {
  const shade = isHeader ? '<w:shd w:val="clear" w:fill="EAF0F1"/>' : '';
  const content = para(runs(text, { bold: isHeader, sz: 18 }), '<w:spacing w:before="40" w:after="40"/>');
  return `<w:tc><w:tcPr><w:tcW w:w="${widthPct}" w:type="pct"/>${shade}</w:tcPr>${content}</w:tc>`;
}

function table(rows) {
  const borders = '<w:tblBorders>' +
    ['top', 'left', 'bottom', 'right', 'insideH', 'insideV']
      .map(s => `<w:${s} w:val="single" w:sz="4" w:space="0" w:color="BDC3C7"/>`).join('') +
    '</w:tblBorders>';
  const cols = rows[0].length;
  const w = Math.floor(5000 / cols);
  const grid = `<w:tblGrid>${Array(cols).fill(`<w:gridCol w:w="${Math.floor(9360 / cols)}"/>`).join('')}</w:tblGrid>`;
  const trs = rows.map((r, i) => {
    const cells = [];
    for (let c = 0; c < cols; c++) cells.push(cell(r[c] !== undefined ? r[c] : '', i === 0, w));
    const trPr = i === 0 ? '<w:trPr><w:tblHeader/></w:trPr>' : '';
    return `<w:tr>${trPr}${cells.join('')}</w:tr>`;
  }).join('');
  return `<w:tbl><w:tblPr><w:tblW w:w="5000" w:type="pct"/>${borders}</w:tblPr>${grid}${trs}</w:tbl>` +
         para('', '<w:spacing w:after="120"/>');
}

// ---------------------------------------------------------------- block parse
const lines = fs.readFileSync(inPath, 'utf8').replace(/\r\n/g, '\n').split('\n');
const body = [];
let i = 0;

const splitRow = (l) => l.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map(s => s.trim());

while (i < lines.length) {
  const line = lines[i];

  if (/^```/.test(line)) {                                   // fenced code
    i++;
    const buf = [];
    while (i < lines.length && !/^```/.test(lines[i])) buf.push(lines[i++]);
    i++;
    const pPr = '<w:shd w:val="clear" w:fill="F4F6F7"/><w:spacing w:before="80" w:after="80"/>' +
                '<w:ind w:left="220"/><w:pBdr>' +
                '<w:left w:val="single" w:sz="18" w:space="6" w:color="0D6273"/></w:pBdr>';
    buf.forEach(t => body.push(para(
      `<w:r><w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/><w:sz w:val="17"/></w:rPr>` +
      `<w:t xml:space="preserve">${esc(t || ' ')}</w:t></w:r>`, pPr)));
    continue;
  }

  const h = line.match(/^(#{1,4})\s+(.*)$/);
  if (h) { body.push(heading(h[2], h[1].length)); i++; continue; }

  if (/^---+\s*$/.test(line)) { body.push(hr()); i++; continue; }

  if (/^\|/.test(line) && i + 1 < lines.length && /^\|[\s:|-]+\|?\s*$/.test(lines[i + 1])) {
    const rows = [splitRow(line)];
    i += 2;
    while (i < lines.length && /^\|/.test(lines[i])) rows.push(splitRow(lines[i++]));
    body.push(table(rows));
    continue;
  }

  if (/^>\s?/.test(line)) {                                   // blockquote
    const buf = [];
    while (i < lines.length && /^>\s?/.test(lines[i])) buf.push(lines[i++].replace(/^>\s?/, ''));
    const pPr = '<w:ind w:left="260"/><w:spacing w:before="80" w:after="80"/><w:pBdr>' +
                '<w:left w:val="single" w:sz="18" w:space="8" w:color="D4A017"/></w:pBdr>' +
                '<w:shd w:val="clear" w:fill="FDF6E3"/>';
    body.push(para(runs(buf.join(' ').trim(), { sz: 20 }), pPr));
    continue;
  }

  const li = line.match(/^\s*[-*]\s+(.*)$/);
  if (li) {
    const pPr = '<w:ind w:left="360" w:hanging="180"/><w:spacing w:after="60"/>';
    body.push(para(`<w:r><w:rPr><w:sz w:val="20"/></w:rPr><w:t xml:space="preserve">&#8226;  </w:t></w:r>` +
                   runs(li[1], { sz: 20 }), pPr));
    i++; continue;
  }

  if (line.trim() === '') { i++; continue; }

  body.push(para(runs(line.trim(), { sz: 20 }), '<w:spacing w:after="120"/>'));
  i++;
}

// ---------------------------------------------------------------- emit parts
const doc =
`<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
${body.join('\n')}
<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>
</w:body></w:document>`;

const contentTypes =
`<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
</Types>`;

const rels =
`<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
</Relationships>`;

const core =
`<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:title>${esc(docTitle || path.basename(inPath))}</dc:title>
<dc:creator>Columbus</dc:creator>
</cp:coreProperties>`;

fs.mkdirSync(path.join(outDir, '_rels'), { recursive: true });
fs.mkdirSync(path.join(outDir, 'word'), { recursive: true });
fs.mkdirSync(path.join(outDir, 'docProps'), { recursive: true });
fs.writeFileSync(path.join(outDir, '[Content_Types].xml'), contentTypes, 'utf8');
fs.writeFileSync(path.join(outDir, '_rels', '.rels'), rels, 'utf8');
fs.writeFileSync(path.join(outDir, 'docProps', 'core.xml'), core, 'utf8');
fs.writeFileSync(path.join(outDir, 'word', 'document.xml'), doc, 'utf8');

console.log(`parts written to ${outDir}  (${body.length} blocks)`);
