"""Lógica de negocio de los movimientos de inventario.

Este módulo es el ÚNICO camino permitido para modificar el stock de un
producto (regla 1): cada cambio crea un registro en stock_movements y
actualiza current_stock dentro de la misma transacción.
"""
from flask_login import current_user

from app.extensions import db
from app.models import Product, StockMovement
from app.models.stock_movement import (
    MOVEMENT_AJUSTE,
    MOVEMENT_ENTRADA,
    MOVEMENT_SALIDA,
    MOVEMENT_TYPES,
)
from app.services.exceptions import ConflictError, NotFoundError, ValidationError


def _get_active_product_locked(product_id) -> Product:
    """Obtiene el producto con bloqueo de fila para actualizar stock sin carreras."""
    try:
        product_id = int(product_id)
    except (TypeError, ValueError):
        raise ValidationError("El campo 'product_id' es obligatorio y debe ser un entero.")

    product = (
        db.session.query(Product)
        .filter(Product.id == product_id)
        .with_for_update()
        .first()
    )
    if product is None:
        raise NotFoundError(f"El producto con id {product_id} no existe.")
    if not product.is_active:
        raise ConflictError(
            f"El producto '{product.name}' está inactivo; no admite movimientos de inventario."
        )
    return product


def _current_user_id(data: dict) -> int:
    """El user_id se toma SIEMPRE del usuario autenticado, nunca del body."""
    if "user_id" in data:
        raise ValidationError(
            "El campo 'user_id' no se acepta en el body: el movimiento se "
            "registra a nombre del usuario autenticado."
        )
    return current_user.id


def _positive_quantity(data: dict) -> int:
    """Regla 6: cantidades de entradas y salidas deben ser enteros mayores a cero."""
    quantity = data.get("quantity")
    try:
        quantity = int(quantity)
    except (TypeError, ValueError):
        raise ValidationError("El campo 'quantity' es obligatorio y debe ser un entero.")
    if quantity <= 0:
        raise ValidationError("El campo 'quantity' debe ser mayor a cero.")
    return quantity


def _create_movement(
    product: Product,
    movement_type: str,
    quantity: int,
    new_stock: int,
    reason: str | None,
    user_id: int | None,
) -> StockMovement:
    movement = StockMovement(
        product_id=product.id,
        movement_type=movement_type,
        quantity=quantity,
        previous_stock=product.current_stock,
        new_stock=new_stock,
        reason=reason,
        user_id=user_id,
    )
    product.current_stock = new_stock
    db.session.add(movement)
    db.session.commit()
    return movement


def register_entry(data: dict) -> StockMovement:
    """Regla 2: una entrada aumenta el stock."""
    product = _get_active_product_locked(data.get("product_id"))
    quantity = _positive_quantity(data)
    user_id = _current_user_id(data)
    reason = (data.get("reason") or "").strip() or None

    new_stock = product.current_stock + quantity
    return _create_movement(product, MOVEMENT_ENTRADA, quantity, new_stock, reason, user_id)


def register_exit(data: dict) -> StockMovement:
    """Regla 3: una salida disminuye el stock. Regla 5: nunca por debajo de cero."""
    product = _get_active_product_locked(data.get("product_id"))
    quantity = _positive_quantity(data)
    user_id = _current_user_id(data)
    reason = (data.get("reason") or "").strip() or None

    if quantity > product.current_stock:
        raise ConflictError(
            f"Stock insuficiente para '{product.name}': disponible "
            f"{product.current_stock}, solicitado {quantity}."
        )

    new_stock = product.current_stock - quantity
    return _create_movement(product, MOVEMENT_SALIDA, quantity, new_stock, reason, user_id)


def register_adjustment(data: dict) -> StockMovement:
    """Regla 4: un ajuste establece un nuevo valor de stock y exige motivo."""
    product = _get_active_product_locked(data.get("product_id"))
    user_id = _current_user_id(data)

    reason = (data.get("reason") or "").strip()
    if not reason:
        raise ValidationError("El campo 'reason' (motivo) es obligatorio en los ajustes.")

    new_stock = data.get("new_stock")
    try:
        new_stock = int(new_stock)
    except (TypeError, ValueError):
        raise ValidationError("El campo 'new_stock' es obligatorio y debe ser un entero.")
    if new_stock < 0:
        raise ValidationError("El campo 'new_stock' no puede ser negativo.")
    if new_stock == product.current_stock:
        raise ValidationError(
            f"El ajuste no tiene efecto: el stock actual ya es {new_stock}."
        )

    quantity = abs(new_stock - product.current_stock)
    return _create_movement(product, MOVEMENT_AJUSTE, quantity, new_stock, reason, user_id)


def list_movements(
    movement_type: str | None = None,
    product_id: int | None = None,
    limit: int | None = None,
) -> list[StockMovement]:
    query = StockMovement.query

    if movement_type:
        movement_type = movement_type.strip().lower()
        if movement_type not in MOVEMENT_TYPES:
            raise ValidationError(
                f"Tipo de movimiento inválido: '{movement_type}'. "
                f"Valores permitidos: {', '.join(MOVEMENT_TYPES)}."
            )
        query = query.filter(StockMovement.movement_type == movement_type)

    if product_id is not None:
        if db.session.get(Product, product_id) is None:
            raise NotFoundError(f"El producto con id {product_id} no existe.")
        query = query.filter(StockMovement.product_id == product_id)

    query = query.order_by(StockMovement.created_at.desc(), StockMovement.id.desc())

    if limit is not None:
        if limit <= 0:
            raise ValidationError("El parámetro 'limit' debe ser mayor a cero.")
        query = query.limit(limit)

    return query.all()
