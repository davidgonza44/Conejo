# Módulos web cerrados

No modificar salvo error real o necesidad estrictamente justificada.

| Módulo | Ruta | Fecha cierre | Script verificación |
|--------|------|--------------|---------------------|
| Inventario web | `/inventory` | 2026-07-03 | `scripts/test_inventory.py` |
| Notas de entrega web | `/delivery-notes` | 2026-07-03 | `scripts/verify_delivery_notes_closure.py` |
| Catálogo visual | `GET /catalog` | 2026-07-22 | `scripts/test_catalog.py` |
| Chatbot interno de apoyo | `GET /chatbot` | 2026-07-22 | `scripts/test_chatbot.py` |

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

## Datos TEST

- Notas identificables: `customer_name` contiene `TEST WEB`.
- Productos de prueba: `code` LIKE `TEST-%` (p. ej. `TEST-DN-<pid>`).
- Limpieza opcional: `scripts/cleanup_test_delivery_notes.py` (no ejecutado por defecto).
