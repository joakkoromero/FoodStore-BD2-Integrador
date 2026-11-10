"""Render the verified Markdown reports as a complementary, readable PDF.

SQL sources, complete AI transcripts, Git history and machine evidence remain
in the repository. This document does not replace those reproducible sources.
"""
from __future__ import annotations

import argparse
import re
import textwrap
from pathlib import Path
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak,
    Preformatted,
)

ROOT = Path(__file__).resolve().parents[1]
BLUE = colors.HexColor('#153956')
TEAL = colors.HexColor('#087F8C')
PALE = colors.HexColor('#EDF4F7')
INK = colors.HexColor('#243443')
WIDTH = A4[0]-100


def table_cells(line):
    """Split a Markdown row without treating escaped/code pipes as borders."""
    line=line.strip()
    if line.startswith('|'): line=line[1:]
    if line.endswith('|') and not line.endswith('\\|'): line=line[:-1]
    cells=[];current=[];in_code=False;i=0
    while i<len(line):
        char=line[i]
        if char=='\\' and i+1<len(line) and line[i+1]=='|':
            current.append('|');i+=2;continue
        if char=='`': in_code=not in_code
        if char=='|' and not in_code:
            cells.append(''.join(current).strip());current=[]
        else: current.append(char)
        i+=1
    cells.append(''.join(current).strip())
    return cells


def starts_block(line):
    line=line.lstrip()
    return (line.startswith(('#','|','```','~~~','- ','* '))
            or bool(re.match(r'^\d+[.)]\s+',line))
            or line in ('---','***'))


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,
                        help='Explicit PDF destination for review or final delivery')
    args=parser.parse_args(argv)
    for name, filename in [('Arial','arial.ttf'),('ArialBold','arialbd.ttf'),
                           ('Consolas','consola.ttf')]:
        pdfmetrics.registerFont(TTFont(name, 'C:/Windows/Fonts/'+filename))
    pdfmetrics.registerFontFamily('Arial',normal='Arial',bold='ArialBold')
    styles = {
        'title': ParagraphStyle('title',fontName='ArialBold',fontSize=26,leading=31,textColor=BLUE,spaceAfter=18),
        'h1': ParagraphStyle('h1',fontName='ArialBold',fontSize=17,leading=21,textColor=BLUE,spaceAfter=12,keepWithNext=True),
        'h2': ParagraphStyle('h2',fontName='ArialBold',fontSize=12,leading=16,textColor=TEAL,spaceBefore=12,spaceAfter=7,keepWithNext=True),
        'body': ParagraphStyle('body',fontName='Arial',fontSize=10,leading=14.1,textColor=INK,spaceAfter=8,splitLongWords=True),
        'small': ParagraphStyle('small',fontName='Arial',fontSize=8.1,leading=10.8,textColor=INK,spaceAfter=5),
        'cell': ParagraphStyle('cell',fontName='Arial',fontSize=8.4,leading=11,textColor=INK,splitLongWords=True),
        'headcell': ParagraphStyle('headcell',fontName='ArialBold',fontSize=8.4,leading=11,textColor=colors.white,splitLongWords=True),
        'code': ParagraphStyle('code',fontName='Consolas',fontSize=8,leading=10.6,textColor=INK,spaceAfter=0),
    }
    story=[]

    def markup(value):
        value=escape(value)
        value=re.sub(r'\[([^\]]+)\]\(([^)]+)\)',r'\1 (\2)',value)
        value=re.sub(r'\*\*([^*]+)\*\*',r'<b>\1</b>',value)
        value=re.sub(r'`([^`]+)`',r'<font name="Consolas">\1</font>',value)
        return value

    def paragraph(value,sty='body'):
        story.append(Paragraph(markup(value),styles[sty]))

    def code(lines):
        wrapped=[]
        for line in lines:
            wrapped.extend(textwrap.wrap(line,width=100,replace_whitespace=False,
                           break_long_words=True,break_on_hyphens=False,subsequent_indent='  ') or [''])
        # Individual lines let the page engine split long SQL/log blocks.
        for line in wrapped:
            story.append(Preformatted(line,styles['code']))
        story.append(Spacer(1,8))

    def table(rows):
        cells=[[Paragraph(markup(x),styles['headcell' if i==0 else 'cell'])
                for x in row] for i,row in enumerate(rows)]
        n=len(cells[0])
        widths=[WIDTH/n]*n
        if n==3: widths=[WIDTH*.29,WIDTH*.31,WIDTH*.40]
        t=Table(cells,colWidths=widths,repeatRows=1,hAlign='LEFT',splitInRow=0)
        t.setStyle(TableStyle([
            ('BACKGROUND',(0,0),(-1,0),BLUE),('VALIGN',(0,0),(-1,-1),'TOP'),
            ('ROWBACKGROUNDS',(0,1),(-1,-1),[colors.white,PALE]),
            ('LEFTPADDING',(0,0),(-1,-1),7),('RIGHTPADDING',(0,0),(-1,-1),7),
            ('TOPPADDING',(0,0),(-1,-1),6),('BOTTOMPADDING',(0,0),(-1,-1),6),
            ('LINEBELOW',(0,0),(-1,0),.5,TEAL),
        ]))
        story.extend([t,Spacer(1,9)])

    def markdown(path):
        lines=path.read_text(encoding='utf-8-sig').splitlines()
        i=0
        while i<len(lines):
            line=lines[i].strip()
            if not line:
                i+=1;continue
            fence=re.match(r'^(`{3,}|~{3,})',line)
            if fence:
                delimiter=fence.group(1);block=[];i+=1
                close=re.compile(r'^'+re.escape(delimiter[0])+'{'+str(len(delimiter))+r',}\s*$')
                while i<len(lines) and not close.fullmatch(lines[i].strip()):
                    block.append(lines[i]);i+=1
                if i==len(lines):
                    raise ValueError(f'Unclosed code fence in {path}')
                code(block);i+=1;continue
            if line.startswith('|'):
                rows=[]
                while i<len(lines) and lines[i].strip().startswith('|'):
                    cells=table_cells(lines[i])
                    if not all(re.fullmatch(r':?-{3,}:?',x) for x in cells): rows.append(cells)
                    i+=1
                if rows and len({len(row) for row in rows})==1: table(rows)
                else:
                    for row in rows: paragraph(' / '.join(row),'small')
                continue
            if line.startswith('#'):
                level=len(line)-len(line.lstrip('#'))
                paragraph(line.lstrip('#').strip(),'h1' if level==1 else 'h2')
                i+=1;continue
            if line.startswith(('- ','* ')) or re.match(r'^\d+[.)]\s+',line):
                paragraph(line);i+=1;continue
            if line in ('---','***'):
                i+=1;continue
            block=[line];i+=1
            while i<len(lines) and lines[i].strip() and not starts_block(lines[i]):
                block.append(lines[i].strip());i+=1
            paragraph(' '.join(block))

    paragraph('TECNICATURA UNIVERSITARIA EN PROGRAMACIÓN','small')
    story.append(Spacer(1,25))
    paragraph('Administración y seguridad de Food Store','title')
    paragraph('Trabajo práctico - Unidad 5 | Base de Datos II','h2')
    paragraph('Exequiel Arancibia · Joaquin Romero')
    paragraph('Ciclo lectivo 2026 · PostgreSQL 17.11')
    story.append(Spacer(1,16))
    paragraph('Roles, auditoría, reconstrucción de incidentes y protección de datos personales. Resolución sobre la base acumulada de los TP1 a TP5 y la Unidad 4.')
    paragraph('Este informe acompaña al repositorio entregado como ZIP. Allí se incluyen SQL, herramientas, respuestas completas de IA, resultados de ejecución e historial Git. Las credenciales y los logs originales se conservan fuera del repositorio.')
    sections=[
        ('Continuidad con los trabajos anteriores','docs/continuidad_y_alcance.md'),
        ('Parte A - Especificación y permisos','docs/informe_roles.md'),
        ('Parte B - Auditoría','docs/informe_auditoria.md'),
        ('Parte C - Simulacro e interpretación','docs/informe_incidente.md'),
        ('Parte D - Anonimización y equivalencia','docs/verificacion_equivalencia.md'),
        ('Parte E - Bitácora de IA','BITACORA.md'),
        ('Conformidad de cierre','docs/validacion_humana.md'),
        ('Ejecución y archivos de entrega','README.md'),
    ]
    for title,filename in sections:
        path=ROOT/filename
        if not path.is_file(): raise FileNotFoundError(f'Required report missing: {filename}')
        story.append(PageBreak())
        paragraph(title,'small')
        markdown(path)

    def footer(canvas,doc):
        canvas.saveState()
        canvas.setStrokeColor(colors.HexColor('#D3E0E7'))
        canvas.line(50,43,A4[0]-50,43)
        canvas.setFont('Arial',8)
        canvas.setFillColor(INK)
        canvas.drawString(50,29,'Food Store · Unidad 5 · Arancibia / Romero')
        canvas.drawRightString(A4[0]-50,29,str(doc.page))
        canvas.restoreState()

    target=args.output or ROOT/'docs'/'TP_U5_FoodStore_Arancibia_Romero.pdf'
    target=target.resolve()
    target.parent.mkdir(parents=True,exist_ok=True)
    SimpleDocTemplate(str(target),pagesize=A4,rightMargin=50,leftMargin=50,
        topMargin=48,bottomMargin=57,title='TP Unidad 5 - Food Store',
        author='Exequiel Arancibia; Joaquin Romero').build(story,onFirstPage=footer,onLaterPages=footer)
    print(target)


if __name__=='__main__': main()
