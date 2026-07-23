"""Rutas JSON del chatbot interno de inventario."""
from flask import Blueprint

from app.controllers import chatbot_controller
from app.utils.auth_decorators import permission_required
from app.utils.permissions import PRODUCTS_READ


chatbot_bp = Blueprint("chatbot", __name__, url_prefix="/api/chatbot")

chatbot_bp.add_url_rule(
    "/message",
    view_func=permission_required(PRODUCTS_READ)(chatbot_controller.post_message),
    methods=["POST"],
)
