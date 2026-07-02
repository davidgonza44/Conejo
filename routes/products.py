"""Rutas REST de productos.

Lectura: roles con products:read (todos los roles).
Escritura: roles con products:write (admin, inventario).
"""
from flask import Blueprint

from app.controllers import product_controller
from app.utils.auth_decorators import permission_required
from app.utils.permissions import PRODUCTS_READ, PRODUCTS_WRITE

products_bp = Blueprint("products", __name__, url_prefix="/api")

_can_read = permission_required(PRODUCTS_READ)
_can_write = permission_required(PRODUCTS_WRITE)

products_bp.add_url_rule(
    "/products", view_func=_can_read(product_controller.list_products), methods=["GET"]
)
products_bp.add_url_rule(
    "/products", view_func=_can_write(product_controller.create_product), methods=["POST"]
)
products_bp.add_url_rule(
    "/products/low-stock",
    view_func=_can_read(product_controller.list_low_stock_products),
    methods=["GET"],
)
products_bp.add_url_rule(
    "/products/<int:product_id>",
    view_func=_can_read(product_controller.get_product),
    methods=["GET"],
)
products_bp.add_url_rule(
    "/products/<int:product_id>",
    view_func=_can_write(product_controller.update_product),
    methods=["PUT"],
)
products_bp.add_url_rule(
    "/products/<int:product_id>",
    view_func=_can_write(product_controller.deactivate_product),
    methods=["DELETE"],
)
