"""Rutas REST de categorías.

Lectura: cualquier usuario autenticado.
Escritura: roles con permiso categories:write (admin, inventario).
"""
from flask import Blueprint

from app.controllers import category_controller
from app.utils.auth_decorators import login_required, permission_required
from app.utils.permissions import CATEGORIES_WRITE

categories_bp = Blueprint("categories", __name__, url_prefix="/api")

_can_write = permission_required(CATEGORIES_WRITE)

categories_bp.add_url_rule(
    "/categories",
    view_func=login_required(category_controller.list_categories),
    methods=["GET"],
)
categories_bp.add_url_rule(
    "/categories",
    view_func=_can_write(category_controller.create_category),
    methods=["POST"],
)
categories_bp.add_url_rule(
    "/categories/<int:category_id>",
    view_func=login_required(category_controller.get_category),
    methods=["GET"],
)
categories_bp.add_url_rule(
    "/categories/<int:category_id>",
    view_func=_can_write(category_controller.update_category),
    methods=["PUT"],
)
categories_bp.add_url_rule(
    "/categories/<int:category_id>",
    view_func=_can_write(category_controller.delete_category),
    methods=["DELETE"],
)
