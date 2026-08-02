"""API de importación histórica CSV v1.

Endpoint adicional mínimo de revisión:
POST /<id>/records/<record_id>/review
Body: {"product_id": int?, "related_record_id": int?,
       "approve": ["weak_duplicate", "inactive_product", "negative_net"]?}
Solo historical_imports:review (admin).
"""
from flask import Blueprint, jsonify
from werkzeug.exceptions import RequestEntityTooLarge

from app.controllers import historical_imports_controller
from app.utils.auth_decorators import permission_required
from app.utils.permissions import (
    HISTORICAL_IMPORTS_CONFIRM,
    HISTORICAL_IMPORTS_EXPORT,
    HISTORICAL_IMPORTS_READ,
    HISTORICAL_IMPORTS_REVERT,
    HISTORICAL_IMPORTS_REVIEW,
    HISTORICAL_IMPORTS_UPLOAD,
)

historical_imports_bp = Blueprint(
    "historical_imports",
    __name__,
    url_prefix="/api/historical-imports",
)

historical_imports_bp.add_url_rule(
    "",
    view_func=permission_required(HISTORICAL_IMPORTS_READ)(
        historical_imports_controller.list_imports
    ),
    methods=["GET"],
)
historical_imports_bp.add_url_rule(
    "/upload",
    view_func=permission_required(HISTORICAL_IMPORTS_UPLOAD)(
        historical_imports_controller.upload_import
    ),
    methods=["POST"],
)
historical_imports_bp.add_url_rule(
    "/template.csv",
    view_func=permission_required(HISTORICAL_IMPORTS_EXPORT)(
        historical_imports_controller.download_template
    ),
    methods=["GET"],
)
historical_imports_bp.add_url_rule(
    "/<string:import_id>",
    view_func=permission_required(HISTORICAL_IMPORTS_READ)(
        historical_imports_controller.get_import
    ),
    methods=["GET"],
)
historical_imports_bp.add_url_rule(
    "/<string:import_id>/records",
    view_func=permission_required(HISTORICAL_IMPORTS_READ)(
        historical_imports_controller.list_records
    ),
    methods=["GET"],
)
historical_imports_bp.add_url_rule(
    "/<string:import_id>/errors",
    view_func=permission_required(HISTORICAL_IMPORTS_READ)(
        historical_imports_controller.list_errors
    ),
    methods=["GET"],
)
historical_imports_bp.add_url_rule(
    "/<string:import_id>/preview",
    view_func=permission_required(HISTORICAL_IMPORTS_REVIEW)(
        historical_imports_controller.preview_import
    ),
    methods=["POST"],
)
historical_imports_bp.add_url_rule(
    "/<string:import_id>/dry-run",
    view_func=permission_required(HISTORICAL_IMPORTS_REVIEW)(
        historical_imports_controller.dry_run_import
    ),
    methods=["POST"],
)
historical_imports_bp.add_url_rule(
    "/<string:import_id>/confirm",
    view_func=permission_required(HISTORICAL_IMPORTS_CONFIRM)(
        historical_imports_controller.confirm_import
    ),
    methods=["POST"],
)
historical_imports_bp.add_url_rule(
    "/<string:import_id>/revert",
    view_func=permission_required(HISTORICAL_IMPORTS_REVERT)(
        historical_imports_controller.revert_import
    ),
    methods=["POST"],
)
historical_imports_bp.add_url_rule(
    "/<string:import_id>/errors.csv",
    view_func=permission_required(HISTORICAL_IMPORTS_EXPORT)(
        historical_imports_controller.export_errors_csv
    ),
    methods=["GET"],
)
historical_imports_bp.add_url_rule(
    "/<string:import_id>/records/<int:record_id>/review",
    view_func=permission_required(HISTORICAL_IMPORTS_REVIEW)(
        historical_imports_controller.review_record
    ),
    methods=["POST"],
)


@historical_imports_bp.errorhandler(RequestEntityTooLarge)
def handle_historical_payload_too_large(_):
    return jsonify({"error": "El multipart excede el máximo de 12 MiB."}), 413


@historical_imports_bp.errorhandler(500)
def handle_historical_internal_error(_):
    return jsonify({"error": "No se pudo procesar la importación histórica."}), 500
