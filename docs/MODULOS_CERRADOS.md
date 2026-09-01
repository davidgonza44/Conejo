# Módulos web cerrados

No modificar salvo error real o necesidad estrictamente justificada.

| Módulo | Ruta | Fecha cierre | Script verificación |
|--------|------|--------------|---------------------|
| Inventario web | `/inventory` | 2026-07-03 | `scripts/test_inventory.py` |
| Notas de entrega web | `/delivery-notes` | 2026-07-03 | `scripts/verify_delivery_notes_closure.py` |
| Catálogo visual | `GET /catalog` | 2026-07-22 | `scripts/test_catalog.py` |
| Chatbot interno de apoyo | `GET /chatbot` | 2026-07-22 | `scripts/test_chatbot.py` |
| Importación histórica CSV | `/historical-imports` | 2026-08-02 | `scripts/test_historical_imports.py` |
| Diagnóstico predictivo / readiness | `GET /predictions` | 2026-08-18 | `scripts/test_prediction_readiness.py` |

## Notas de entrega — alcance cerrado

- Listado, filtros, KPIs, crear, detalle, cancelar (vía API existente).
- Archivos: `delivery_notes.html`, `delivery_notes.js`, `delivery_notes.css`, ruta en `pages.py`.
- No incluye: PDF formal, catálogo visual, chatbot, predicción.

## Catálogo visual — alcance cerrado

- Función: consulta visual de productos.
- Roles: `admin`, `inventario` y `vendedor`.
- Naturaleza: solo lectura.
- Pruebas: 29/29 verificaciones aprobadas.
- Sin modificaciones de stock, movimientos, notas, productos o categorías.

## Chatbot interno de apoyo — alcance cerrado

- Módulo: Chatbot interno de apoyo.
- Ruta web: `GET /chatbot`.
- Endpoint: `POST /api/chatbot/message`.
- Roles: `admin`, `inventario` y `vendedor`, con matriz autorizada.
- Función: consultas deterministas internas sobre productos, categorías, precio, disponibilidad y stock según rol.
- Naturaleza: solo lectura, sin conversaciones persistidas ni servicios externos.
- Pruebas: 104/104 aprobadas; snapshots operativos idénticos.
- `purchase_price` excluido.
- Sin modificaciones operativas de stock, movimientos, notas, productos, categorías o usuarios.
- Deuda técnica posterior: CSRF/rate limiting transversal y exposición preexistente de `/api/test/products` y `/api/test/categories`; no se modificaron ahora.
- No incluye: módulo predictivo.

## Importación histórica CSV — alcance cerrado

- Migración manual probada en MariaDB 10.4.32 real de XAMPP.
- Ejecución idempotente verificada: la segunda pasada no duplicó columnas,
  índices, claves foráneas, restricciones ni triggers.
- Esquema histórico verificado mediante `information_schema`: InnoDB,
  `utf8mb4`, columnas y tipos canónicos, índices, FKs, CHECKs y dos triggers
  de inmutabilidad compatibles.
- Flujo real aprobado sin confirmación: plantilla, upload privado, preview,
  validación, matching exacto, consulta de errores, exportación y dry run.
- Pruebas del importador: 120/120 verificaciones aprobadas.
- Regresión adicional: catálogo 29/29 y chatbot 104/104 aprobadas.
- Snapshots MySQL antes/después idénticos; sin cambios de stock, productos,
  categorías, usuarios, movimientos, notas de entrega ni KPIs operativos.
- Lote, registro y archivo privado temporales eliminados; sin datos TEST
  residuales.
- No incluye modelos predictivos, pronósticos ni recomendaciones de
  reabastecimiento.

## Diagnóstico predictivo / readiness — incremento cerrado

- Alcance cerrado: infraestructura de diagnóstico de suficiencia histórica.
- El módulo predictivo completo **no** está cerrado.
- Ruta web: `GET /predictions` (Análisis predictivo).
- API solo lectura: `GET /api/predictions/readiness`,
  `GET /api/predictions/products`, `GET /api/predictions/products/<id>`.
- Permiso: `predictions:read` (admin e inventario; vendedor no).
- No entrena modelos, no genera pronósticos, no calcula reabastecimiento,
  no crea `POST /api/predictions/run` ni tablas de corridas.
- Pruebas: 53/53 aprobadas (incluye los 48 puntos exigidos) en SQLite aislado.
- Snapshots de la BD aislada idénticos antes/después; sin cambios de stock,
  movimientos, notas, históricos ni productos.
- Sin datos TEST residuales ni archivos temporales.
- Ver `docs/PREDICTION_READINESS.md`.

## Datos TEST

- Notas identificables: `customer_name` contiene `TEST WEB`.
- Productos de prueba: `code` LIKE `TEST-%` (p. ej. `TEST-DN-<pid>`).
- Limpieza opcional: `scripts/cleanup_test_delivery_notes.py` (no ejecutado por defecto).
