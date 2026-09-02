# Sistema inteligente de apoyo al control de inventario

Sistema web de apoyo al control de inventario y predicción de necesidades de
reabastecimiento para **Ferretería y Construcciones El Conejo C.A.**



## Stack tecnológico

- Python 3.10+
- Flask + Flask-SQLAlchemy + Flask-Login
- MySQL 8.0 (driver PyMySQL)
- Frontend (fases posteriores): Bootstrap 5, Chart.js
- Machine Learning (fases posteriores): pandas, scikit-learn, statsmodels

## Requisitos previos

- Python 3.10 o superior
- MySQL 8.0 en ejecución local (o accesible por red)

## Instalación y ejecución

1. Crear y activar el entorno virtual (PowerShell):

```powershell
python -m venv venv
venv\Scripts\activate
```

2. Instalar dependencias:

```powershell
pip install -r requirements.txt
```

3. Configurar variables de entorno:

```powershell
copy .env.example .env
```

Editar `.env` con las credenciales de MySQL locales (`DB_USER`, `DB_PASSWORD`, etc.).

4. Crear la base de datos, tablas y datos semilla:

```powershell
python scripts\init_db.py
```

5. Levantar el servidor de desarrollo:

```powershell
python run.py
```

6. Verificar en el navegador o con Postman:

| Ruta | Descripción |
| --- | --- |
| `http://localhost:5000/` | Información del sistema |
| `http://localhost:5000/health/db` | Estado de la conexión a MySQL |
| `http://localhost:5000/api/test/categories` | Categorías semilla en JSON |
| `http://localhost:5000/api/test/products` | Productos semilla en JSON |

## Estructura del proyecto

```
app/
├── __init__.py       # application factory (create_app)
├── config.py         # configuración desde .env
├── extensions.py     # instancias de SQLAlchemy y LoginManager
├── models/           # modelos SQLAlchemy (6 tablas)
├── routes/           # blueprints (rutas de prueba por ahora)
├── services/         # lógica de negocio de stock (próximo incremento)
├── templates/        # vistas Jinja2 (próximo incremento)
└── static/           # CSS/JS/imágenes (próximo incremento)
scripts/
└── init_db.py        # creación de BD y datos semilla
run.py                # punto de entrada
```

## Reglas de negocio del inventario

1. El stock no se modifica manualmente desde el producto.
2. Todo cambio de stock crea un registro en `stock_movements`.
3. Una entrada aumenta el stock; una salida lo disminuye.
4. Un ajuste corrige el stock y guarda el motivo.
5. No se puede registrar una salida mayor al stock disponible.
6. Al confirmar una nota de entrega se descuenta automáticamente el stock.
7. Los productos con `current_stock <= minimum_stock` se marcan como bajo stock.
