"""Rutas REST de movimientos de inventario."""
from flask import Blueprint

from app.controllers import inventory_controller

inventory_bp = Blueprint("inventory", __name__, url_prefix="/api/inventory")

inventory_bp.add_url_rule(
    "/entry", view_func=inventory_controller.register_entry, methods=["POST"]
)
inventory_bp.add_url_rule(
    "/exit", view_func=inventory_controller.register_exit, methods=["POST"]
)
inventory_bp.add_url_rule(
    "/adjustment", view_func=inventory_controller.register_adjustment, methods=["POST"]
)
inventory_bp.add_url_rule(
    "/movements", view_func=inventory_controller.list_movements, methods=["GET"]
)
inventory_bp.add_url_rule(
    "/products/<int:product_id>/movements",
    view_func=inventory_controller.list_product_movements,
    methods=["GET"],
)
inventory_bp.add_url_rule(
    "/low-stock",
    view_func=inventory_controller.list_low_stock_products,
    methods=["GET"],
)
