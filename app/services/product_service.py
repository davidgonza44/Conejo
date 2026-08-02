"""Lógica de negocio de productos.

Regla clave: el stock (current_stock) solo se define al crear el producto.
Después de eso, únicamente los movimientos de inventario pueden modificarlo.
"""
from decimal import Decimal, InvalidOperation

from app.extensions import db
from app.models import Category, Product
from app.services.exceptions import ConflictError, NotFoundError, ValidationError

# Campos que el CRUD acepta al editar. current_stock queda excluido a propósito.
_UPDATABLE_FIELDS = {
    "code",
    "name",
    "description",
    "category_id",
    "unit",
    "minimum_stock",
    "purchase_price",
    "sale_price",
    "image_url",
    "is_active",
}


def _non_negative_int(data: dict, field: str, default: int | None = None) -> int:
    value = data.get(field, default)
    if value is None:
        value = default
    try:
        value = int(value)
    except (TypeError, ValueError):
        raise ValidationError(f"El campo '{field}' debe ser un número entero.")
    if value < 0:
        raise ValidationError(f"El campo '{field}' no puede ser negativo.")
    return value


def _non_negative_price(data: dict, field: str, default: str = "0") -> Decimal:
    value = data.get(field, default)
    if value is None:
        value = default
    try:
        value = Decimal(str(value))
    except (InvalidOperation, ValueError):
        raise ValidationError(f"El campo '{field}' debe ser un número.")
    if value < 0:
        raise ValidationError(f"El campo '{field}' no puede ser negativo.")
    return value


def _validate_code(code: str | None, exclude_id: int | None = None) -> str:
    code = (code or "").strip()
    if not code:
        raise ValidationError("El código del producto es obligatorio.")

    query = Product.query.filter(Product.code == code)
    if exclude_id is not None:
        query = query.filter(Product.id != exclude_id)
    if query.first() is not None:
        raise ConflictError(f"Ya existe un producto con el código '{code}'.")
    return code


def _validate_category(category_id) -> int:
    try:
        category_id = int(category_id)
    except (TypeError, ValueError):
        raise ValidationError("El campo 'category_id' es obligatorio y debe ser un entero.")
    if db.session.get(Category, category_id) is None:
        raise ValidationError(f"La categoría con id {category_id} no existe.")
    return category_id


def get_product_or_404(product_id: int) -> Product:
    product = db.session.get(Product, product_id)
    if product is None:
        raise NotFoundError(f"El producto con id {product_id} no existe.")
    return product


def list_products(
    search: str | None = None,
    category_id: int | None = None,
    low_stock: bool = False,
    include_inactive: bool = False,
) -> list[Product]:
    query = Product.query

    if not include_inactive:
        query = query.filter(Product.is_active.is_(True))

    if search:
        term = f"%{search.strip()}%"
        query = query.filter(
            db.or_(Product.name.ilike(term), Product.code.ilike(term))
        )

    if category_id is not None:
        query = query.filter(Product.category_id == category_id)

    if low_stock:
        query = query.filter(Product.current_stock <= Product.minimum_stock)

    return query.order_by(Product.name).all()


def create_product(data: dict) -> Product:
    code = _validate_code(data.get("code"))

    name = (data.get("name") or "").strip()
    if not name:
        raise ValidationError("El nombre del producto es obligatorio.")

    category_id = _validate_category(data.get("category_id"))

    # El stock inicial solo se acepta aquí, al crear el producto (regla 1).
    current_stock = _non_negative_int(data, "current_stock", default=0)
    minimum_stock = _non_negative_int(data, "minimum_stock", default=0)
    purchase_price = _non_negative_price(data, "purchase_price")
    sale_price = _non_negative_price(data, "sale_price")

    product = Product(
        code=code,
        name=name,
        description=(data.get("description") or "").strip() or None,
        category_id=category_id,
        unit=(data.get("unit") or "unidad").strip(),
        current_stock=current_stock,
        minimum_stock=minimum_stock,
        purchase_price=purchase_price,
        sale_price=sale_price,
        image_url=(data.get("image_url") or "").strip() or None,
        is_active=bool(data.get("is_active", True)),
    )
    db.session.add(product)
    db.session.commit()
    return product


def update_product(product_id: int, data: dict) -> Product:
    product = get_product_or_404(product_id)

    if "current_stock" in data:
        raise ValidationError(
            "El stock no puede modificarse desde el CRUD de productos. "
            "Use el módulo de movimientos de inventario (entradas, salidas y ajustes)."
        )

    unknown = set(data.keys()) - _UPDATABLE_FIELDS
    if unknown:
        raise ValidationError(
            f"Campos no permitidos en la edición: {', '.join(sorted(unknown))}."
        )

    if "code" in data:
        product.code = _validate_code(data.get("code"), exclude_id=product.id)

    if "name" in data:
        name = (data.get("name") or "").strip()
        if not name:
            raise ValidationError("El nombre del producto es obligatorio.")
        product.name = name

    if "category_id" in data:
        product.category_id = _validate_category(data.get("category_id"))

    if "description" in data:
        product.description = (data.get("description") or "").strip() or None

    if "unit" in data:
        unit = (data.get("unit") or "").strip()
        if not unit:
            raise ValidationError("El campo 'unit' no puede estar vacío.")
        product.unit = unit

    if "minimum_stock" in data:
        product.minimum_stock = _non_negative_int(data, "minimum_stock")

    if "purchase_price" in data:
        product.purchase_price = _non_negative_price(data, "purchase_price")

    if "sale_price" in data:
        product.sale_price = _non_negative_price(data, "sale_price")

    if "image_url" in data:
        product.image_url = (data.get("image_url") or "").strip() or None

    if "is_active" in data:
        product.is_active = bool(data.get("is_active"))

    db.session.commit()
    return product


def deactivate_product(product_id: int) -> Product:
    """Baja lógica: el producto se desactiva, no se elimina (conserva historial)."""
    product = get_product_or_404(product_id)
    product.is_active = False
    db.session.commit()
    return product
