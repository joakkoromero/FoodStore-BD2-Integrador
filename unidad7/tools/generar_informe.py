"""Informe de cinco páginas, fuentes verificadas y adjuntos exactos."""
from pathlib import Path
from xml.sax.saxutils import escape
import hashlib,json,subprocess,textwrap
from reportlab.pdfgen import canvas
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import Paragraph,Table,TableStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from pypdf import PdfReader,PdfWriter

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/pdf';OUT.mkdir(parents=True,exist_ok=True)
W,H=A4;LEFT=43;RIGHT=W-43;WIDTH=RIGHT-LEFT
for name,file in [('Arial','arial.ttf'),('ArialB','arialbd.ttf'),('Consolas','consola.ttf')]:
    pdfmetrics.registerFont(TTFont(name,str(Path('C:/Windows/Fonts')/file)))
pdfmetrics.registerFontFamily('Arial',normal='Arial',bold='ArialB',italic='Arial',boldItalic='ArialB')
NAVY=colors.HexColor('#16324A');TEAL=colors.HexColor('#116B7B')
GRAY=colors.HexColor('#4C5A67');LIGHT=colors.HexColor('#EEF4F7')
styles={
 'body':ParagraphStyle('body',fontName='Arial',fontSize=10,leading=14.3,textColor=NAVY,spaceAfter=7),
 'small':ParagraphStyle('small',fontName='Arial',fontSize=8.7,leading=11.8,textColor=GRAY),
 'cell':ParagraphStyle('cell',fontName='Arial',fontSize=9,leading=12,textColor=NAVY),
 'headcell':ParagraphStyle('headcell',fontName='ArialB',fontSize=9,leading=12,textColor=colors.white),
 'code':ParagraphStyle('code',fontName='Consolas',fontSize=8,leading=10.2,textColor=NAVY),
}
data=json.loads((ROOT/'docs/evidencias/validacion.json').read_text(encoding='utf-8'))
raw=OUT/'_informe_sin_adjuntos.pdf'
c=canvas.Canvas(str(raw),pagesize=A4,pageCompression=1)
c.setTitle('Food Store - Unidad 7 - NoSQL y nuevas formas de almacenamiento')
c.setAuthor('Exequiel Arancibia y Joaquin Romero')
c.setSubject('Resolución de consignas 1 a 7, laboratorio real y fuentes adjuntas')
page=0;y=0
def begin(title,sub=''):
 global page,y
 if page:c.showPage()
 page+=1
 c.setFillColor(NAVY);c.rect(0,H-55,W,55,fill=1,stroke=0)
 c.setFillColor(colors.white);c.setFont('ArialB',10)
 c.drawString(LEFT,H-23,'BASES DE DATOS II  |  UNIDAD 7  |  FOOD STORE')
 c.setFont('Arial',8);c.drawRightString(RIGHT,H-40,'Arancibia / Romero - 10/11/2026')
 c.setFillColor(NAVY);c.setFont('ArialB',17);c.drawString(LEFT,H-88,title)
 y=H-106
 if sub:paragraph(sub,'small')
 c.setStrokeColor(colors.HexColor('#CBD9E1'));c.line(LEFT,39,RIGHT,39)
 c.setFillColor(GRAY);c.setFont('Arial',8)
 c.drawString(LEFT,26,'Tecnicatura Universitaria en Programación - UTN FRM')
 c.drawRightString(RIGHT,26,str(page))
def paragraph(text,style='body',after=7):
 global y
 p=Paragraph(text,styles[style]);_,height=p.wrap(WIDTH,1000)
 if y-height<52:raise RuntimeError(f'Contenido desborda pagina {page}: {text[:55]}')
 p.drawOn(c,LEFT,y-height);y-=height+after
def heading(text):
 global y
 y-=3;c.setFillColor(TEAL);c.setFont('ArialB',11.3);c.drawString(LEFT,y-12,text);y-=23
def table(rows,widths,header=True):
 global y
 ts=[]
 for i,row in enumerate(rows):
  ts.append([Paragraph(escape(str(v)),styles['headcell' if i==0 and header else 'cell']) for v in row])
 t=Table(ts,colWidths=widths,hAlign='LEFT')
 spec=[('VALIGN',(0,0),(-1,-1),'TOP'),('LEFTPADDING',(0,0),(-1,-1),7),('RIGHTPADDING',(0,0),(-1,-1),7),('TOPPADDING',(0,0),(-1,-1),6),('BOTTOMPADDING',(0,0),(-1,-1),6),('LINEBELOW',(0,0),(-1,0),.5,colors.HexColor('#CFDBE3'))]
 if header:spec += [('BACKGROUND',(0,0),(-1,0),NAVY)]
 for i in range(1 if header else 0,len(rows)):
  if i%2:spec.append(('BACKGROUND',(0,i),(-1,i),LIGHT))
 t.setStyle(TableStyle(spec));_,height=t.wrap(WIDTH,1000)
 if y-height<52:raise RuntimeError(f'Tabla desborda pagina {page}')
 t.drawOn(c,LEFT,y-height);y-=height+10
def code(text):
 global y
 lines=[]
 for line in text.strip('\n').splitlines():
  lines.extend(textwrap.wrap(line,93,replace_whitespace=False,drop_whitespace=False) or [''])
 height=len(lines)*10.2+12
 if y-height<52:raise RuntimeError(f'Código desborda pagina {page}')
 c.setFillColor(LIGHT);c.rect(LEFT,y-height,WIDTH,height,fill=1,stroke=0)
 c.setFillColor(NAVY);c.setFont('Consolas',8)
 for i,line in enumerate(lines):c.drawString(LEFT+7,y-13-i*10.2,line)
 y-=height+9
def link(label,url):
 return f'<link href="{escape(url)}" color="#116B7B">{escape(label)}</link>'

begin('Modelo documental y continuidad','Integrantes: Exequiel Arancibia y Joaquin Romero. Informe de cinco páginas; fuentes y evidencias adjuntas.')
paragraph('<b>Objetivo.</b> Representar pedidos existentes de Food Store en MongoDB y comprobar sus resultados contra PostgreSQL. Se resuelven las siete consignas de la guía, conservando identificadores, estados, cantidades y precios históricos.')
heading('1. Subconjunto y correspondencia de claves')
paragraph('Se utiliza <b>foodstore</b>, la base acumulada de las unidades 4 a 6: FNBC, vistas e índices de U4, seguridad de U5 y continuidad verificada en U6. El cliente se llama <b>usuario</b> en nuestro esquema. Se seleccionan los pedidos <b>1, 2, 3, 4 y 5</b>, ya existentes; no se crean registros en PostgreSQL.')
table([
 ['Origen PostgreSQL','Destino MongoDB / significado'],
 ['pedido.id (PK)','_id Long: mismo identificador del pedido'],
 ['pedido.usuario_id -> usuario.id','cliente.usuario_id Long + alias de presentación'],
 ['detalle_pedido PK (pedido_id, producto_id)','lineas[] dentro de cada pedido; producto_id Long'],
 ['detalle_pedido.producto_id -> producto.id','Nombre del producto al exportar; no es un nombre histórico'],
 ['fecha, estado, forma_pago, total','Date UTC, estados originales y total Decimal128']
],[180,WIDTH-180])
code('''foodstore_u7.pedidos = {
  _id: Long, fecha: Date, estado: String, forma_pago: String,
  cliente: { usuario_id: Long, alias: String },
  lineas: [{ producto_id: Long, nombre_al_migrar: String,
    cantidad: Int32, precio_unitario: Decimal128, subtotal: Decimal128 }],
  total: Decimal128
}''')
heading('2-3. Por qué se embeben los datos')
paragraph('Las líneas pertenecen al pedido y normalmente se consultan juntas. Embebidas, el pedido completo se recupera de una colección, sin reconstruirlo con uniones. Cada documento conserva su total y los precios de <b>detalle_pedido.precio_unitario</b>; no toma el precio actual del catálogo.')
paragraph('El cliente esencial se representa con su ID y una etiqueta nueva, por ejemplo <b>Cliente 1</b>. No se exportan nombre, apellido, email, teléfono ni hash. El alias no sustituye ni modifica al usuario original. Cliente y nombre del producto son una copia al momento de exportación; no se implementa sincronización automática. [1]')

begin('Migración e integridad verificadas','Consignas 2 y 3 - Ejecución real del 10/11/2026, con salida y archivos exactos adjuntos.')
heading('Procedimiento ejecutado')
paragraph('<b>1.</b> PostgreSQL 17.11: transacción <b>REPEATABLE READ READ ONLY</b>; selección explícita de los cinco IDs y exportación Extended JSON. Se comprueban las siete líneas y la igualdad entre cada total y la suma de subtotales.')
paragraph('<b>2.</b> Se conservan IDs como Long, cantidades Int32 e importes Decimal128, sin pasar dinero a Double. Las cinco fechas no contienen fracciones submilisegundo: Date UTC conserva sus instantes; por ejemplo, 01/03/2026 12:00 UTC-03 corresponde a 15:00Z.')
paragraph('<b>3.</b> MongoDB Community <b>8.0.34</b> y mongosh <b>2.14.1</b>: creación de <b>foodstore_u7.pedidos</b> con validador estricto e <b>insertMany()</b>. Se usaron binarios oficiales portátiles con SHA256 oficial coincidente, autenticación y acceso exclusivo por loopback.')
paragraph('<b>4.</b> Se compara el contenido BSON de los cinco documentos contra el EJSON exportado. Se crean índices por <b>estado</b> y <b>lineas.producto_id</b>. Este último es multikey por indexar un arreglo; no se midió una mejora temporal. [2]')
code('''Salida: motor=8.0.34; base=foodstore_u7; colección=pedidos
documentos=5; lineas=7; contenido_igual_exportacion=true
tamaños BSON por ID: [440,305,311,440,306] bytes
integridad_origen: lineas_invalidas=0; pedidos_total_incorrecto=0
psql exit=0; mongosh exit=0''')
heading('Dos reglas de integridad conservadas')
table([
 ['Regla','Aplicación en la migración'],
 ['1. Dominio e identidad','Cantidad entera > 0, precio histórico > 0, IDs originales y producto sin repetir en un pedido. _id único y enums reales del origen.'],
 ['2. Coherencia monetaria','subtotal = cantidad x precio_unitario; total = suma(subtotales). $jsonSchema + $expr, validationAction:error. No recalcular precios desde producto.']
],[145,WIDTH-145])
paragraph('<b>Pruebas negativas reales.</b> Total incoherente, cantidad cero (ajustando subtotal/total para aislar esa regla) y producto repetido con total correcto: rechazados con <b>código 121</b>. ID duplicado: <b>11000</b>. Persisten exactamente cinco documentos y ningún registro inválido. El validador expresa estas reglas; no equivale a todas las FK, transiciones y permisos del sistema relacional. [3]')
paragraph('<b>Conservación del origen.</b> Las huellas de filas completas antes/después coinciden: categoria 2; producto 50.000; usuario 20.001; pedido 225.000; detalle_pedido 499.997. PostgreSQL no recibe escrituras de este práctico. Las evidencias incluyen esos controles y hashes de las fuentes ejecutadas.','small')

begin('Consultas y equivalencia de resultados','Consignas 4 y 5 - Todas las comparaciones se restringen a los mismos pedidos [1,2,3,4,5].')
heading('4. Cuatro consultas ejecutadas en MongoDB')
code('''a) pedidos.find({}).sort({_id:1})
b) pedidos.find({estado:'ENTREGADO'},{_id:1,estado:1})
c) pedidos.find({'lineas.producto_id':Long('1')},{_id:1})
d) pedidos.find({total:{$gt:Decimal128('3000.00')}},{_id:1,total:1})''')
table([
 ['a) ID','Estado','Total','Productos / cantidades'],
 ['1','ENTREGADO','2800.00','1 x 2; 2 x 1'],
 ['2','ENTREGADO','1500.00','3 x 1'],
 ['3','ENTREGADO','3150.00','1 x 3'],
 ['4','ENTREGADO','6200.00','2 x 4; 3 x 2'],
 ['5','CONFIRMADO','1050.00','1 x 1']
],[38,119,87,WIDTH-244])
paragraph('La consulta <b>a</b> devuelve documentos completos, incluidos ID y estado; su salida integra la evidencia adjunta. <b>b</b> devuelve [1,2,3,4]. <b>c</b> busca el producto 1 dentro del arreglo y devuelve [1,3,5]. <b>d</b> devuelve [3,4], con totales 3150.00 y 6200.00. Se elige <b>3000.00</b> porque separa dos pedidos de mayor importe de los tres restantes; es un umbral exploratorio de la muestra, no una regla comercial.')
heading('5. Equivalentes ejecutados en PostgreSQL')
code('''SELECT id FROM public.pedido
WHERE id IN (1,2,3,4,5) AND estado='ENTREGADO';

SELECT p.id FROM public.pedido p
WHERE p.id IN (1,2,3,4,5) AND EXISTS (
  SELECT 1 FROM public.detalle_pedido d
  WHERE d.pedido_id=p.id AND d.producto_id=1);''')
table([
 ['Filtro','PostgreSQL','MongoDB','IDs en ambos / coinciden'],
 ['ENTREGADO','4','4','[1,2,3,4] / Sí'],
 ['Producto 1','3','3','[1,3,5] / Sí']
],[116,86,86,WIDTH-288])
paragraph('No se detectaron diferencias. <b>EXISTS</b> conserva una fila por pedido, como find() devuelve un documento por pedido. Comparar MongoDB con los 225.000 pedidos del origen completo daría una diferencia de alcance; por eso ambas consultas SQL usan la muestra explícita. No fue necesario modificar datos para obtener equivalencia.')

begin('Evaluación de tecnología y asistencia de IA','Consignas 6 y 7 - Propuestas de IA contrastadas con documentación oficial y ejecución propia.')
heading('6. Consulta realizada y trazabilidad')
paragraph('Se consultó <b>Codex, agente IA de comparación</b>, el 10/11/2026. El prompt describió pedido, detalle_pedido, usuario y producto; indicó claves foráneas, subtotal generado y triggers, el acceso frecuente al pedido completo y la necesidad de conservar coherencia de cantidades, precios históricos y total. Se solicitaron dos afirmaciones verificables y una recomendación, evitando suponer benchmarks o que MongoDB carece de transacciones.')
paragraph('El prompt exacto y la respuesta original breve se conservan en <b>docs/ia/consulta_respuesta.md</b>, adjunto al PDF. Se compartió un resumen del esquema y del problema; no filas ni datos personales. La respuesta de IA se utilizó como propuesta y se comprobó antes de adoptar decisiones.')
heading('7. Contraste de dos afirmaciones concretas')
paragraph('<b>Afirmación 1 de IA:</b> un pedido con líneas embebidas puede recuperarse como un documento sin unir colecciones. <b>Contraste:</b> la documentación oficial de embebidos describe ese acceso conjunto [1]. En el laboratorio, la consulta a recuperó los cinco pedidos con sus siete líneas desde pedidos; el ID 1 contiene dos productos. El almacenamiento y el filtro por producto usan el arreglo del mismo documento. <b>Resultado: aceptada</b> como diferencia de estructura. No se afirma que MongoDB sea más rápido: cinco documentos y equivalencia de IDs no constituyen un benchmark.')
paragraph('<b>Afirmación 2 de IA:</b> una escritura documental es atómica, pero embeber líneas no garantiza automáticamente coherencia matemática. <b>Contraste:</b> MongoDB documenta la atomicidad por documento y admite transacciones entre documentos en despliegues compatibles [4]. Su validación de esquema permite tipos/rangos y rechaza documentos inválidos [3]. Se implementaron reglas explícitas: el total incoherente y la cantidad cero fueron rechazados con código 121. <b>Resultado: aceptada.</b> Atomicidad y validez de reglas de negocio son propiedades distintas. Nuestro servidor standalone no ejecuta transacciones multidocumento.')
heading('Comparación aplicada a Food Store')
table([
 ['Criterio','PostgreSQL acumulado','MongoDB de este laboratorio'],
 ['Pedido completo','JOIN o proyección JSON; integridad y triggers ya implementados','Un documento con líneas; copia orientada a lectura'],
 ['Coherencia','FK, restricciones, subtotal generado y triggers existentes [5]','Validador explícito; no replica toda la política relacional'],
 ['Costo operativo','Se mantiene una fuente de verdad','Combinar exige sincronización y controlar copias obsoletas']
],[99,207,WIDTH-306])

begin('Conclusión, reproducción y fuentes','Cierre del informe - Código y evidencias adjuntos al PDF y disponibles como archivos separados.')
heading('Conclusión (menos de 200 palabras)')
conclusión='''Conviene mantener PostgreSQL como fuente principal de Food Store. El primer criterio es la integridad: las claves foráneas, restricciones, subtotal generado y triggers ya protegen relaciones y reglas que no se trasladan automáticamente al documento. El segundo es el costo de operación: sumar otro motor obliga a definir sincronización, manejo de cambios y recuperación de copias obsoletas.
MongoDB representa bien el pedido completo con sus líneas y permite filtrar por estado o producto sin reconstruir el agregado. La muestra migró sin diferencias de identificadores ni cantidades, conservando importes decimales y precios históricos. Esto valida el modelo y las consultas del laboratorio, pero no demuestra una mejora de rendimiento ni justifica sustituir PostgreSQL.
Una proyección MongoDB podría incorporarse para lecturas específicas si mediciones y requisitos reales la justifican, manteniendo PostgreSQL como autoridad y definiendo un mecanismo verificable de actualización. En este práctico se implementa una copia puntual de cinco pedidos, sin sincronización ni cambio del sistema principal.'''
assert len(conclusión.split())<=200
paragraph(conclusión.replace('\n',' '))
heading('Cómo reproducir y comprobar')
paragraph('<b>1.</b> Ejecutar consultas_postgresql.sql con psql sobre foodstore acumulada; requiere la conexión propia del laboratorio. <b>2.</b> Extraer consultas_mongodb.js y pedidos_migrados.ejson a una misma carpeta. Desde ella ejecutar mongosh con la conexión autenticada propia y <b>--file consultas_mongodb.js</b>. <b>3.</b> Comprobar cinco documentos, siete líneas, IDs b/c iguales y cuatro rechazos esperados. Los archivos no contienen credenciales.')
try:commit=subprocess.check_output(['git','-C',str(ROOT),'rev-parse','--short','HEAD'],text=True,stderr=subprocess.DEVNULL).strip()
except Exception:raise RuntimeError('Se requiere commit real de fuentes antes de generar el informe')
paragraph('<b>Repositorio de trabajo:</b> Git local Arancibia_Romero_U7, sin remoto. Commit de fuentes: <b>'+escape(commit)+'</b>. Asistencia de IA declarada y validada mediante fuentes oficiales y pruebas reales. Los commits técnicos se identifican como Codex. README y evidencia incluyen comandos, alcance, salidas y hashes.','small')
heading('Fuentes oficiales y material de la asignatura')
refs=[
 ('[1] MongoDB: Embedded Data in Your MongoDB Schema','https://www.mongodb.com/docs/manual/data-modeling/embedding/'),
 ('[2] MongoDB: Multikey Indexes','https://www.mongodb.com/docs/manual/core/indexes/index-types/index-multikey/'),
 ('[3] MongoDB: Schema Validation','https://www.mongodb.com/docs/manual/core/schema-validation/'),
 ('[4] MongoDB: Atomicity and Transactions','https://www.mongodb.com/docs/manual/core/write-operations-atomicity/'),
 ('[5] PostgreSQL 17: Constraints','https://www.postgresql.org/docs/17/ddl-constraints.html')]
for label,url in refs:paragraph(link(label,url),'small',after=4)
paragraph('Material UTN FRM: Trabajo Práctico Unidad 7 y apunte <i>NoSQL y nuevas formas de almacenamiento</i>, edición octubre 2026, apartados 4-10, 17 y 20-22. Se adaptó su ejemplo a usuario, lineas y estados del esquema real. Antecedentes: entregas U4-U6 del equipo. Consulta oficial: 10/11/2026.','small')
paragraph('<b>Adjuntos exactos:</b> JS, SQL, EJSON, README, respuesta IA y evidencias de ejecución/conservación. Las tres fuentes necesarias para reproducir también se entregan como archivos separados.','small')
assert page==5

sources=[ROOT/'consultas_mongodb.js',ROOT/'consultas_postgresql.sql',ROOT/'pedidos_migrados.ejson']
c.save()

attachments=[*sources,ROOT/'README.md',ROOT/'docs/ia/consulta_respuesta.md',*sorted((ROOT/'docs/evidencias').glob('*'))]
reader=PdfReader(raw);writer=PdfWriter();writer.clone_document_from_reader(reader)
manifest=[]
for source in attachments:
 payload=source.read_bytes();name=str(source.relative_to(ROOT)).replace('\\','/')
 writer.add_attachment(name,payload)
 manifest.append({'nombre':name,'bytes':len(payload),'sha256':hashlib.sha256(payload).hexdigest()})
final=OUT/'TP_U7_FoodStore_Arancibia_Romero.pdf'
with final.open('wb') as f:writer.write(f)
check=PdfReader(final)
assert len(check.pages)==page
assert len(check.attachments)==len(attachments)
for entry in manifest:
 assert hashlib.sha256(check.attachments[entry['nombre']][0]).hexdigest()==entry['sha256']
alltext='\n'.join(p.extract_text() or '' for p in check.pages)
assert 'Consignas 4 y 5' in alltext and 'Afirmación 2 de IA' in alltext
qa={'informe_paginas':5,'paginas_totales':page,'conclusion_palabras':len(conclusión.split()),'fuentes_commit':commit,'adjuntos_exactos':manifest,'sha256_pdf':hashlib.sha256(final.read_bytes()).hexdigest(),'visual_qa':'pendiente'}
(OUT/'verificacion_pdf.json').write_text(json.dumps(qa,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
raw.unlink()
print(json.dumps({'pdf':str(final),'paginas_informe':5,'paginas_totales':page,'conclusion_palabras':len(conclusión.split()),'adjuntos':len(attachments)},ensure_ascii=False))
