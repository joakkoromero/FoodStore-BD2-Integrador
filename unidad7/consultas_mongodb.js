// Food Store - Unidad 7 - Arancibia / Romero
// mongosh <conexion propia> --quiet --file consultas_mongodb.js
// Ejecutar desde esta carpeta, junto a pedidos_migrados.ejson.
// No elimina bases ni colecciones. Si la coleccion existe, exige mismos datos.
const fs = require('fs');
const lab = db.getSiblingDB('foodstore_u7');
const nombre = 'pedidos';
const docs = EJSON.parse(fs.readFileSync('pedidos_migrados.ejson', 'utf8'), {relaxed:false});
const canon = value => EJSON.stringify(value, null, 0, {relaxed:false});
const emitir = (tipo, valor) => print(JSON.stringify({tipo, ...valor}));

// 1-3: tipos exactos y reglas de cantidades, precios y coherencia matematica.
const opciones = {
    validator: {$and: [
      {$jsonSchema: {
        bsonType:'object', additionalProperties:false,
        required:['_id','fecha','estado','forma_pago','total','cliente','lineas'],
        properties: {
          _id:{bsonType:'long'}, fecha:{bsonType:'date'},
          estado:{enum:['PENDIENTE','CONFIRMADO','ENTREGADO','CANCELADO']},
          forma_pago:{enum:['EFECTIVO','TARJETA','TRANSFERENCIA']},
          total:{bsonType:'decimal',minimum:0},
          cliente:{bsonType:'object',additionalProperties:false,
            required:['usuario_id','alias'],properties:{
              usuario_id:{bsonType:'long'},alias:{bsonType:'string'}}},
          lineas:{bsonType:'array',minItems:1,items:{
            bsonType:'object',additionalProperties:false,
            required:['producto_id','nombre_al_migrar','cantidad','precio_unitario','subtotal'],
            properties:{producto_id:{bsonType:'long'},nombre_al_migrar:{bsonType:'string'},
              cantidad:{bsonType:'int',minimum:1},
              precio_unitario:{bsonType:'decimal',minimum:0,exclusiveMinimum:true},
              subtotal:{bsonType:'decimal',minimum:0}}}}
        }
      }},
      {$expr:{$and:[
        {$eq:['$total',{$sum:'$lineas.subtotal'}]},
        {$allElementsTrue:{$map:{input:'$lineas',as:'l',in:
          {$eq:['$$l.subtotal',{$multiply:['$$l.cantidad','$$l.precio_unitario']}]}}}},
        {$eq:[{$size:'$lineas'},{$size:{$setUnion:['$lineas.producto_id',[]]}}]}
      ]}}
    ]}, validationLevel:'strict',validationAction:'error'
  };
if (!lab.getCollectionNames().includes(nombre)) {
  lab.createCollection(nombre, opciones);
}
const pedidos = lab.getCollection(nombre);
if (pedidos.countDocuments({}) === 0) pedidos.insertMany(docs, {ordered:true});
const existentes = pedidos.find({}).sort({_id:1}).toArray();
if (canon(existentes)!==canon(docs)) throw new Error('La coleccion no coincide con la muestra; no se reemplaza');
// Reaplicar unicamente a esta coleccion de laboratorio si ya existia.
const cambio = lab.runCommand({collMod:nombre,...opciones});
if (cambio.ok!==1) throw new Error('No se pudo aplicar el validador');
pedidos.createIndex({estado:1},{name:'idx_estado'});
pedidos.createIndex({'lineas.producto_id':1},{name:'idx_producto'});
emitir('entorno',{motor:db.version(),base:lab.getName(),coleccion:nombre,
  documentos:pedidos.countDocuments({}),lineas:existentes.reduce((n,p)=>n+p.lineas.length,0),
  contenido_igual_exportacion:true,bytes_documentos:pedidos.aggregate([
    {$sort:{_id:1}},{$project:{_id:0,bytes:{$bsonSize:'$$ROOT'}}}
  ]).toArray().map(p=>p.bytes)});

// 4a: todos los pedidos, incluidos identificador, estado y documento completo.
const a = pedidos.find({}).sort({_id:1}).toArray();
emitir('a_todos',{cantidad:a.length,documentos:EJSON.serialize(a,{relaxed:false})});
// 4b: estado presente en los datos.
const b = pedidos.find({estado:'ENTREGADO'},{_id:1,estado:1}).sort({_id:1}).toArray();
emitir('b_estado',{estado:'ENTREGADO',cantidad:b.length,ids:b.map(p=>p._id.toString())});
// 4c: notacion por puntos sobre el arreglo embebido.
const c = pedidos.find({'lineas.producto_id':Long('1')},{_id:1}).sort({_id:1}).toArray();
emitir('c_producto',{producto_id:'1',cantidad:c.length,ids:c.map(p=>p._id.toString())});
// 4d: $gt es estricto; 3000 separa dos pedidos altos de tres pedidos menores.
const d = pedidos.find({total:{$gt:Decimal128('3000.00')}},{_id:1,total:1}).sort({_id:1}).toArray();
emitir('d_total',{umbral:'3000.00',operador:'>',cantidad:d.length,
  pedidos:d.map(p=>({id:p._id.toString(),total:p.total.toString()}))});

// Pruebas negativas: ninguna insercion invalida puede persistir.
const casos = [
  ['total_incoherente', p=>{p._id=Long('900000001');p.total=Decimal128('0.00');},121],
  ['cantidad_cero', p=>{p._id=Long('900000002');p.lineas[0].cantidad=Int32(0);
    p.lineas[0].subtotal=Decimal128('0.00');p.total=Decimal128('800.00');},121],
  ['producto_duplicado', p=>{p._id=Long('900000003');p.lineas.push(p.lineas[0]);
    p.total=Decimal128('4800.00');},121],
  ['id_duplicado', p=>{},11000]
];
for (const [caso,cambiar,codigo] of casos) {
  const p = EJSON.parse(canon(docs[0]), {relaxed:false}); cambiar(p);
  let rechazado=false,obtenido=null;
  try {pedidos.insertOne(p);} catch(e) {obtenido=e.code;rechazado=e.code===codigo;}
  if (!rechazado) throw new Error('Prueba negativa fallida: '+caso);
  emitir('prueba_negativa',{caso,codigo:obtenido,rechazado});
}
if (pedidos.countDocuments({})!==5) throw new Error('La cantidad final cambio');
emitir('cierre',{documentos:5,invalidos_persistidos:0});
