"""Rutas REST de categorías."""
from flask import Blueprint

from app.controllers import category_controller

categories_bp = Blueprint("categories", __name__, url_prefix="/api")

categories_bp.add_url_rule(
    "/categories", view_func=category_controller.list_categories, methods=["GET"]
)
categories_bp.add_url_rule(
    "/categories", view_func=category_controller.create_category, methods=["POST"]
)
categories_bp.add_url_rule(
    "/categories/<int:category_id>",
    view_func=category_controller.get_category,
    methods=["GET"],
)
categories_bp.add_url_rule(
    "/categories/<int:category_id>",
    view_func=category_controller.update_category,
    methods=["PUT"],
)
categories_bp.add_url_rule(
    "/categories/<int:category_id>",
    view_func=category_controller.delete_category,
    methods=["DELETE"],
)
