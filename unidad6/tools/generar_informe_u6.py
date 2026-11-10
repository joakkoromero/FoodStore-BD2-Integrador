"""Build the single U6 PDF with complete visible and embedded public sources.

No database commands are executed. Inputs must already contain real results.
--check-layout measures short reports without producing any PDF or QA file.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
import tempfile
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate, Flowable, Frame, PageBreak, PageTemplate, Paragraph,
    Preformatted, Spacer, Table, TableStyle,
)
from reportlab.platypus.tableofcontents import TableOfContents
from pypdf import PdfReader, PdfWriter

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT.parent / 'output/pdf/informe_u6.pdf'
BLUE = colors.HexColor('#153956')
TEAL = colors.HexColor('#087F8C')
PALE = colors.HexColor('#EDF4F7')
INK = colors.HexColor('#243443')
MARGIN = 42
BOTTOM = 48
TOP = 42
WIDTH = A4[0] - MARGIN * 2
HEIGHT = A4[1] - TOP - BOTTOM
MAX_CODE_CHARACTERS = 105
FORBIDDEN_PARTS = {'.git', 'private', 'privado', 'runtime', 'logs', 'backups',
                   '__pycache__', 'node_modules', 'output', 'consigna_qa'}
SECRET_PATTERNS = (
    r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    r'\b(?:sk-proj-|sk-)[A-Za-z0-9_-]{24,}\b',
    r'\b(?:ghp_|github_pat_)[A-Za-z0-9_]{24,}\b',
    r'(?i)\bpostgres(?:ql)?://[^\s/:<>]+:[^\s/@<>]+@',
    r'(?im)^\s*\$?env:PGPASSWORD\s*=\s*[\'"][^\'"\r\n<>]{4,}[\'"]',
)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def register_fonts():
    font_dir = Path('C:/Windows/Fonts')
    for name, filename in [('Arial', 'arial.ttf'), ('ArialBold', 'arialbd.ttf'),
                           ('ArialItalic', 'ariali.ttf'), ('ArialBoldItalic', 'arialbi.ttf'),
                           ('Consolas', 'consola.ttf')]:
        path = font_dir / filename
        if not path.is_file():
            raise FileNotFoundError('Required Windows font is missing: ' + filename)
        if name not in pdfmetrics.getRegisteredFontNames():
            pdfmetrics.registerFont(TTFont(name, str(path)))
    pdfmetrics.registerFontFamily('Arial', normal='Arial', bold='ArialBold',
                                  italic='ArialItalic', boldItalic='ArialBoldItalic')


def make_styles():
    return {
        'h1': ParagraphStyle('U6Heading1', fontName='ArialBold', fontSize=17,
                             leading=20, textColor=BLUE, spaceAfter=10, keepWithNext=True),
        'h2': ParagraphStyle('U6Heading2', fontName='ArialBold', fontSize=11.7,
                             leading=14, textColor=TEAL, spaceBefore=8,
                             spaceAfter=5, keepWithNext=True),
        'body': ParagraphStyle('U6Body', fontName='Arial', fontSize=10,
                               leading=13.2, textColor=INK, spaceAfter=6,
                               splitLongWords=True, allowWidows=0, allowOrphans=0),
        'list': ParagraphStyle('U6List', fontName='Arial', fontSize=10,
                               leading=13.2, textColor=INK, spaceAfter=4,
                               leftIndent=12, firstLineIndent=-12, splitLongWords=True,
                               allowWidows=0, allowOrphans=0),
        'small': ParagraphStyle('U6Small', fontName='Arial', fontSize=8.3,
                                leading=10.3, textColor=INK, spaceAfter=5,
                                splitLongWords=True),
        'cell': ParagraphStyle('U6Cell', fontName='Arial', fontSize=8.5,
                               leading=10.5, textColor=INK, splitLongWords=True),
        'headcell': ParagraphStyle('U6HeadCell', fontName='ArialBold', fontSize=8.5,
                                   leading=10.5, textColor=colors.white, splitLongWords=True),
        'code': ParagraphStyle('U6Code', fontName='Consolas', fontSize=8.1,
                               leading=9.8, textColor=INK, spaceAfter=0),
        'toc': ParagraphStyle('U6Toc', fontName='Arial', fontSize=9.2,
                              leading=12, textColor=INK, spaceBefore=5,
                              spaceAfter=5, leftIndent=0, firstLineIndent=0),
    }


def plain_markup(text):
    text = escape(text)
    text = re.sub(r'\*\*([^*]+)\*\*', r'<b>\1</b>', text)
    def link(match):
        label, target = match.group(1), match.group(2)
        if target.startswith(('https://', 'http://')):
            return '<link href="' + target.replace('"', '&quot;') + '">' + label + '</link>'
        return label if label == target else label + ' (' + target + ')'
    return re.sub(r'\[([^\]]+)\]\(([^)]+)\)', link, text)


def markup(text):
    """Parse code spans after joining Markdown continuation lines."""
    parts = []; start = 0
    for match in re.finditer(r'(`+)(.*?)\1', text, re.S):
        parts.append(plain_markup(text[start:match.start()]))
        code = match.group(2).replace('\n', ' ')
        parts.append('<font name="Consolas">' + escape(code) + '</font>')
        start = match.end()
    parts.append(plain_markup(text[start:]))
    return ''.join(parts)


def table_cells(line):
    line = line.strip()
    if line.startswith('|'): line = line[1:]
    if line.endswith('|') and not line.endswith('\\|'): line = line[:-1]
    cells = []; current = []; delimiter = 0; i = 0
    while i < len(line):
        if line[i:i+2] == '\\|':
            current.append('|'); i += 2; continue
        if line[i] == '`':
            end = i + 1
            while end < len(line) and line[end] == '`': end += 1
            run = end-i
            if delimiter == 0: delimiter = run
            elif delimiter == run: delimiter = 0
            current.append(line[i:end]); i = end; continue
        if line[i] == '|' and delimiter == 0:
            cells.append(''.join(current).strip()); current = []
        else:
            current.append(line[i])
        i += 1
    cells.append(''.join(current).strip())
    return cells


def starts_block(line):
    value = line.lstrip()
    return (bool(re.match(r'^(?:#{1,6}\s|`{3,}|~{3,}|[-*+]\s|\d+[.)]\s|\|)', value))
            or value in ('---', '***'))


class SectionMarker(Flowable):
    def __init__(self, key, title='', *, limited=False, end=False):
        Flowable.__init__(self)
        self.key = key; self.title = title; self.limited = limited; self.end = end
        self.width = self.height = 0

    def draw(self):
        pass


class U6Document(BaseDocTemplate):
    def __init__(self, filename, **kwargs):
        super().__init__(filename, pagesize=A4, leftMargin=MARGIN, rightMargin=MARGIN,
                         topMargin=TOP, bottomMargin=BOTTOM, **kwargs)
        self.addPageTemplates(PageTemplate(id='U6',
            frames=[Frame(MARGIN, BOTTOM, WIDTH, HEIGHT,
                          leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)],
            onPage=self.decorate_page))

    def beforeDocument(self):
        self.sections = {}; self.active_limit = None; self.topic = 'Mantenimiento de Food Store'

    def decorate_page(self, canvas, doc):
        if self.active_limit and doc.page > self.sections[self.active_limit]['start']:
            raise ValueError('One-page limit exceeded: ' + self.active_limit)
        canvas.saveState()
        canvas.setFillColor(INK); canvas.setFont('Arial', 7.8)
        canvas.drawString(MARGIN, A4[1]-25, 'BASES DE DATOS II | TP UNIDAD 6')
        canvas.setStrokeColor(colors.HexColor('#D3E0E7'))
        canvas.line(MARGIN, 36, A4[0]-MARGIN, 36)
        canvas.drawString(MARGIN, 24, 'Food Store | Exequiel Arancibia / Joaquin Romero')
        canvas.drawRightString(A4[0]-MARGIN, 24, str(doc.page))
        canvas.restoreState()

    def afterFlowable(self, flowable):
        if isinstance(flowable, SectionMarker):
            if flowable.end:
                self.sections[flowable.key]['end'] = self.page
                if self.active_limit == flowable.key: self.active_limit = None
            else:
                self.sections[flowable.key] = {'title': flowable.title, 'start': self.page}
                self.topic = flowable.title
                if flowable.limited: self.active_limit = flowable.key
        heading = getattr(flowable, 'u6_bookmark', None)
        if heading:
            key, label, in_toc = heading
            self.canv.bookmarkPage(key)
            self.canv.addOutlineEntry(label, key, level=0, closed=False)
            if in_toc: self.notify('TOCEntry', (0, label, self.page, key))


@dataclass
class Renderer:
    styles: dict

    def __post_init__(self):
        self.wrapped_lines = []

    def paragraph(self, text, style='body', bookmark=None):
        paragraph = Paragraph(markup(text), self.styles[style])
        if bookmark: paragraph.u6_bookmark = bookmark
        return paragraph

    def code(self, lines, source):
        result = []; style = self.styles['code']
        for number, original in enumerate(lines, 1):
            pending = original.expandtabs(4); first = True; pieces = []
            while pending:
                prefix = '' if first else '  '
                limit = min(len(pending), MAX_CODE_CHARACTERS-len(prefix))
                while limit > 0 and pdfmetrics.stringWidth(prefix+pending[:limit],
                                                           'Consolas', style.fontSize) > WIDTH-2:
                    limit -= 1
                if limit == 0: raise ValueError('A source character cannot fit the code frame')
                pieces.append(prefix+pending[:limit]); pending = pending[limit:]; first = False
            if not pieces: pieces = ['']
            if len(pieces) > 1:
                self.wrapped_lines.append({'source': source, 'line': number, 'visual_lines': len(pieces)})
            for piece in pieces: result.append(Preformatted(piece, style))
        result.append(Spacer(1, 7))
        return result

    def table(self, rows, source):
        if not rows or len({len(row) for row in rows}) != 1:
            raise ValueError('Inconsistent Markdown table: ' + source)
        count = len(rows[0])
        ratios = {2: [0.39, 0.61], 3: [0.23, 0.22, 0.55],
                  4: [0.26, 0.24, 0.24, 0.26], 5: [0.23, 0.16, 0.23, 0.23, 0.15]}
        widths = [WIDTH*x for x in ratios.get(count, [1/count]*count)]
        cells = [[self.paragraph(value, 'headcell' if index == 0 else 'cell')
                  for value in row] for index, row in enumerate(rows)]
        table = Table(cells, colWidths=widths, repeatRows=1, hAlign='LEFT', splitInRow=0)
        vertical_padding = 3 if source == 'Source manifest' else 5
        table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (-1, 0), BLUE),
            ('VALIGN', (0, 0), (-1, -1), 'TOP'),
            ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, PALE]),
            ('LEFTPADDING', (0, 0), (-1, -1), 6),
            ('RIGHTPADDING', (0, 0), (-1, -1), 6),
            ('TOPPADDING', (0, 0), (-1, -1), vertical_padding),
            ('BOTTOMPADDING', (0, 0), (-1, -1), vertical_padding),
            ('LINEBELOW', (0, 0), (-1, 0), 0.5, TEAL),
        ]))
        return [table, Spacer(1, 7)]

    def markdown(self, path):
        lines = path.read_text(encoding='utf-8-sig').splitlines(); result = []; i = 0
        while i < len(lines):
            line = lines[i].strip()
            if not line: i += 1; continue
            fence = re.match(r'^(`{3,}|~{3,})', line)
            if fence:
                delimiter = fence.group(1); block = []; i += 1
                close = re.compile(r'^'+re.escape(delimiter[0])+'{'+str(len(delimiter))+r',}\s*$')
                while i < len(lines) and not close.fullmatch(lines[i].strip()):
                    block.append(lines[i]); i += 1
                if i == len(lines): raise ValueError('Unclosed code block: ' + path.name)
                result.extend(self.code(block, path.relative_to(ROOT).as_posix())); i += 1; continue
            if line.startswith('|'):
                rows = []
                while i < len(lines) and lines[i].lstrip().startswith('|'):
                    row = table_cells(lines[i]); i += 1
                    if not all(re.fullmatch(r':?-{3,}:?', value) for value in row): rows.append(row)
                result.extend(self.table(rows, path.name)); continue
            if line in ('---', '***'): i += 1; continue
            heading = re.match(r'^(#{1,6})\s+(.+)$', line)
            if heading:
                result.append(self.paragraph(heading.group(2), 'h1' if len(heading.group(1)) == 1 else 'h2'))
                i += 1; continue
            item = re.match(r'^([-*+]\s+|\d+[.)]\s+)(.*)$', line)
            block = [line]; i += 1
            # Includes soft line breaks, indented list continuations and code
            # spans whose closing backticks occur on a subsequent source line.
            while i < len(lines) and lines[i].strip() and not starts_block(lines[i]):
                block.append(lines[i].strip()); i += 1
            result.append(self.paragraph('\n'.join(block), 'list' if item else 'body'))
        return result


def public_path(path, *, attachment_only=False):
    resolved = path.resolve()
    if not resolved.is_relative_to(ROOT.resolve()) or not resolved.is_file() or path.is_symlink():
        raise ValueError('Source must be a regular file inside the project')
    relative = resolved.relative_to(ROOT.resolve())
    allowed_extensions = {'.md', '.ps1', '.psm1', '.psd1', '.sql'}
    if attachment_only: allowed_extensions.update({'.json', '.txt', '.csv', '.tsv'})
    if (any(part.casefold() in FORBIDDEN_PARTS for part in relative.parts)
            or resolved.suffix.casefold() not in allowed_extensions
            or any(word in resolved.name.casefold() for word in ('secret', 'pgpass', '.env'))):
        raise ValueError('Private or unsupported source cannot be attached: ' + relative.as_posix())
    text = resolved.read_bytes().decode('utf-8-sig')
    if any(re.search(pattern, text) for pattern in SECRET_PATTERNS):
        raise ValueError('Potential credential in source; local review required: ' + relative.as_posix())
    return resolved


def locate_source(name):
    candidates = []
    for path in ROOT.rglob(name):
        relative = path.relative_to(ROOT)
        if 'docs' in relative.parts or any(part.casefold() in FORBIDDEN_PARTS for part in relative.parts):
            continue
        candidates.append(public_path(path))
    if len(candidates) != 1:
        raise ValueError('Expected exactly one public source named ' + name)
    return candidates[0]


def sources_for(args):
    required = [public_path(ROOT/'SPEC_U6.md'), public_path(ROOT/'AGENTS.md')]
    for name in ('backup_foodstore.ps1', 'health_check.sql', 'maintenance.sql', 'restore_test.ps1'):
        required.append(locate_source(name))
    required.append(public_path(ROOT/args.validation_source) if args.validation_source
                    else locate_source('validaciones.sql'))
    extra = []
    # Companion scripts/modules are real dependencies and must not disappear
    # from a PDF-only delivery. These directories are public source directories.
    for folder in (ROOT, ROOT/'scripts', ROOT/'sql', ROOT/'tools'):
        if folder.is_dir():
            for path in sorted(folder.iterdir()):
                if path.is_file() and path.suffix.casefold() in {'.ps1', '.psm1', '.psd1', '.sql'}:
                    extra.append(public_path(path))
    extra.extend(public_path(ROOT/path) for path in args.source)
    return list(dict.fromkeys(required+extra))


def measure_one_page(flowables):
    # Conservative dry layout: sum even spaces that ReportLab may collapse.
    # The real document also enforces the limit on every build pass.
    used = 0.0
    for flowable in flowables:
        _, height = flowable.wrap(WIDTH, HEIGHT)
        used += height + flowable.getSpaceBefore() + flowable.getSpaceAfter()
    return {'measured_height_points': round(used, 2), 'available_height_points': round(HEIGHT, 2),
            'fits_conservative_measure': used <= HEIGHT}


def add_section(story, renderer, key, title, path, *, limited=False):
    if story: story.append(PageBreak())
    story.append(SectionMarker(key, title, limited=limited))
    story.extend(renderer.markdown(path))
    story.append(SectionMarker(key, end=True))


def verify_embedded(pdf, source_bytes):
    reader = PdfReader(pdf)
    if reader.is_encrypted: raise ValueError('Deliverable unexpectedly encrypted')
    actual = {name: list(values) for name, values in reader.attachments.items()}
    if set(actual) != set(source_bytes): raise ValueError('Embedded source names differ from manifest')
    checks = []
    for name, expected in source_bytes.items():
        if len(actual[name]) != 1 or actual[name][0] != expected:
            raise ValueError('Embedded source bytes differ: ' + name)
        checks.append({'name': name, 'bytes': len(expected), 'sha256': sha256(expected),
                       'extracted_bytes_equal_source': True})
    if any(not page.extract_text().strip() for page in reader.pages):
        raise ValueError('PDF contains an empty text page')
    return reader, checks


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument('--validation-source', help='Project-relative validation SQL path')
    parser.add_argument('--source', action='append', default=[], help='Additional public source to include')
    parser.add_argument('--attachment-only', action='append', default=[],
                        help='Project-relative public evidence/IA file to embed without a visible code listing; repeatable')
    parser.add_argument('--check-layout', action='store_true', help='Measure existing short reports only')
    args = parser.parse_args(argv)
    register_fonts(); styles = make_styles(); renderer = Renderer(styles)
    short_reports = [('SPEC_U6', ROOT/'SPEC_U6.md'),
                     ('informe_post_incidente', ROOT/'docs/informe_post_incidente.md')]
    measurements = {}
    for key, path in short_reports:
        if not path.is_file():
            if args.check_layout: continue
            raise FileNotFoundError('Required report missing: ' + path.relative_to(ROOT).as_posix())
        measurements[key] = measure_one_page(renderer.markdown(path))
    if args.check_layout:
        print(json.dumps({'pdf_created': False, 'measurements': measurements}, ensure_ascii=False, indent=2))
        return
    renderer.wrapped_lines.clear()
    resolution = ROOT/'docs/resolucion.md'
    if not resolution.is_file(): raise FileNotFoundError('Required report missing: docs/resolucion.md')
    sources = sources_for(args)
    source_bytes = {path.relative_to(ROOT).as_posix(): path.read_bytes() for path in sources}
    attachment_bytes = dict(source_bytes)
    for name in args.attachment_only:
        path = public_path(ROOT/name, attachment_only=True)
        attachment_bytes[path.relative_to(ROOT).as_posix()] = path.read_bytes()
    target = args.output.resolve(); target.parent.mkdir(parents=True, exist_ok=True)
    story = []
    add_section(story, renderer, 'SPEC_U6', 'Especificación U6', ROOT/'SPEC_U6.md', limited=True)
    add_section(story, renderer, 'informe_post_incidente', 'Informe post-incidente',
                ROOT/'docs/informe_post_incidente.md', limited=True)
    add_section(story, renderer, 'resolucion', 'Resolución y evidencias', resolution)
    story.append(PageBreak())
    story.append(renderer.paragraph('Anexos - Índice de fuentes', 'h1',
                                    ('anexos', 'Anexos - Índice de fuentes', False)))
    story.append(renderer.paragraph('Los listados siguientes contienen las fuentes públicas completas. '
        'SPEC_U6.md ya está representada íntegramente en la primera página y no se duplica como listado. '
        'Todos los archivos, incluida SPEC, también se adjuntan individualmente dentro del PDF con sus bytes originales. '
        'Las evidencias y conversaciones de IA adicionales se adjuntan sin repetirlas como listados de código; '
        'el cuerpo contiene su explicación y los resultados pertinentes. '
        'Los ajustes visuales de líneas del listado no modifican esos archivos.', 'body'))
    toc = TableOfContents(); toc.levelStyles = [styles['toc']]; story.append(toc)
    story.append(Spacer(1, 12))
    story.append(renderer.paragraph('Integridad de los adjuntos', 'h2'))
    rows = [['Archivo público', 'SHA-256 de los bytes originales']]
    rows.extend([[name, '`'+sha256(data)+'`'] for name, data in attachment_bytes.items()])
    story.extend(renderer.table(rows, 'Source manifest'))
    for index, path in enumerate(sources[1:], 1):
        relative = path.relative_to(ROOT).as_posix()
        key = 'source-'+str(index); title = f'Anexo {index} - {relative}'
        story.append(PageBreak()); story.append(SectionMarker(key, title))
        story.append(renderer.paragraph(title, 'h1', (key, title, True)))
        story.append(renderer.paragraph('Fuente íntegra | UTF-8 | SHA-256: `'+sha256(source_bytes[relative])+'`', 'small'))
        text = source_bytes[relative].decode('utf-8-sig')
        story.extend(renderer.code(text.splitlines(), relative))
        story.append(SectionMarker(key, end=True))
    with tempfile.TemporaryDirectory(prefix='u6-pdf-', dir=target.parent) as temporary:
        rendered = Path(temporary)/'rendered.pdf'; embedded = Path(temporary)/'embedded.pdf'
        document = U6Document(str(rendered), title='TP Unidad 6 - Mantenimiento de Food Store',
                              author='Exequiel Arancibia; Joaquin Romero')
        document.multiBuild(story, maxPasses=6)
        for key, _ in short_reports:
            section = document.sections[key]
            if section['start'] != section['end']:
                raise ValueError('One-page limit exceeded: '+key)
        writer = PdfWriter(); writer.clone_document_from_reader(PdfReader(rendered))
        for name, data in attachment_bytes.items(): writer.add_attachment(name, data)
        with embedded.open('wb') as stream: writer.write(stream)
        reader, attachment_checks = verify_embedded(embedded, attachment_bytes)
        qa = {'pdf': target.name, 'pages': len(reader.pages),
              'one_page_sections': {key: {**document.sections[key], 'passed': True}
                                    for key, _ in short_reports},
              'dry_measurements': measurements, 'attachments': attachment_checks,
              'attachment_hashes_verified': True, 'source_count': len(sources),
              'attachment_count': len(attachment_bytes),
              'visual_line_wrapping': renderer.wrapped_lines,
              'visual_qa': 'Pending inspection of all rendered final pages',
              'scope': 'Layout and byte-integrity checks only; no database execution or human approval inferred'}
        pdf_bytes = embedded.read_bytes(); qa['pdf_sha256'] = sha256(pdf_bytes)
        target.write_bytes(pdf_bytes)
    qa_path = target.with_name(target.stem+'_qa.json')
    qa_path.write_bytes((json.dumps(qa, ensure_ascii=False, indent=2)+'\n').encode('utf-8'))
    print(json.dumps({'output': str(target), 'qa': str(qa_path), 'pages': qa['pages'],
                      'source_count': len(sources), 'attachment_count': len(attachment_bytes),
                      'attachment_hashes_verified': True,
                      'one_page_limits_passed': True}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
