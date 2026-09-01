"""API de diagnóstico de suficiencia histórica (solo lectura).

No ejecuta modelos, no genera pronósticos y no reabastece.
"""
from flask import Blueprint

from app.controllers import predictions_controller
from app.utils.auth_decorators import permission_required
from app.utils.permissions import PREDICTIONS_READ

predictions_bp = Blueprint("predictions", __name__, url_prefix="/api/predictions")

_can_read = permission_required(PREDICTIONS_READ)

predictions_bp.add_url_rule(
    "/readiness",
    view_func=_can_read(predictions_controller.readiness_summary),
    methods=["GET"],
)
predictions_bp.add_url_rule(
    "/products",
    view_func=_can_read(predictions_controller.list_products),
    methods=["GET"],
)
predictions_bp.add_url_rule(
    "/products/<int:product_id>",
    view_func=_can_read(predictions_controller.get_product),
    methods=["GET"],
)
