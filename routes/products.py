"""Rutas REST de productos."""
from flask import Blueprint

from app.controllers import product_controller

products_bp = Blueprint("products", __name__, url_prefix="/api")

products_bp.add_url_rule(
    "/products", view_func=product_controller.list_products, methods=["GET"]
)
products_bp.add_url_rule(
    "/products", view_func=product_controller.create_product, methods=["POST"]
)
products_bp.add_url_rule(
    "/products/low-stock",
    view_func=product_controller.list_low_stock_products,
    methods=["GET"],
)
products_bp.add_url_rule(
    "/products/<int:product_id>",
    view_func=product_controller.get_product,
    methods=["GET"],
)
products_bp.add_url_rule(
    "/products/<int:product_id>",
    view_func=product_controller.update_product,
    methods=["PUT"],
)
products_bp.add_url_rule(
    "/products/<int:product_id>",
    view_func=product_controller.deactivate_product,
    methods=["DELETE"],
)
