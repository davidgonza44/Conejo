"""Controlador de movimientos de inventario: traduce HTTP <-> servicio."""
from flask import jsonify, request

from app.services import inventory_service, product_service
from app.services.exceptions import ValidationError


def _json_body() -> dict:
    data = request.get_json(silent=True)
    if data is None or not isinstance(data, dict):
        raise ValidationError("El cuerpo de la petición debe ser un JSON válido.")
    return data


def _movement_response(movement, status_code: int = 201):
    """Devuelve el movimiento creado junto con el producto actualizado."""
    return (
        jsonify(
            {
                "movement": movement.to_dict(),
                "product": movement.product.to_dict(),
            }
        ),
        status_code,
    )


def register_entry():
    movement = inventory_service.register_entry(_json_body())
    return _movement_response(movement)


def register_exit():
    movement = inventory_service.register_exit(_json_body())
    return _movement_response(movement)


def register_adjustment():
    movement = inventory_service.register_adjustment(_json_body())
    return _movement_response(movement)


def list_movements():
    movements = inventory_service.list_movements(
        movement_type=request.args.get("movement_type"),
        product_id=request.args.get("product_id", type=int),
        limit=request.args.get("limit", type=int),
    )
    return jsonify({"count": len(movements), "items": [m.to_dict() for m in movements]})


def list_product_movements(product_id: int):
    movements = inventory_service.list_movements(
        movement_type=request.args.get("movement_type"),
        product_id=product_id,
        limit=request.args.get("limit", type=int),
    )
    return jsonify({"count": len(movements), "items": [m.to_dict() for m in movements]})


def list_low_stock_products():
    products = product_service.list_products(low_stock=True)
    return jsonify({"count": len(products), "items": [p.to_dict() for p in products]})
