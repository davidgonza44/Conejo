"""Rutas REST de gestión de usuarios (solo admin)."""
from flask import Blueprint

from app.controllers import user_controller
from app.models.user import ROLE_ADMIN
from app.utils.auth_decorators import role_required

users_bp = Blueprint("users", __name__, url_prefix="/api/users")

_admin_only = role_required(ROLE_ADMIN)

users_bp.add_url_rule(
    "", view_func=_admin_only(user_controller.list_users), methods=["GET"]
)
users_bp.add_url_rule(
    "", view_func=_admin_only(user_controller.create_user), methods=["POST"]
)
users_bp.add_url_rule(
    "/<int:user_id>", view_func=_admin_only(user_controller.get_user), methods=["GET"]
)
users_bp.add_url_rule(
    "/<int:user_id>",
    view_func=_admin_only(user_controller.update_user),
    methods=["PUT"],
)
