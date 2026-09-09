"""Rutas web (páginas HTML renderizadas con Jinja2).

Las rutas /api/* no se tocan: siguen devolviendo JSON puro.
Acceso al dashboard: solo admin e inventario; vendedor ve acceso denegado.
"""
from flask import Blueprint, redirect, render_template, url_for
from flask_login import current_user, login_required
from flask_wtf.csrf import generate_csrf

from app.models.user import ROLE_ADMIN, ROLE_INVENTARIO
from app.utils.permissions import (
    CATEGORIES_WRITE,
    DELIVERY_NOTES_CANCEL,
    DELIVERY_NOTES_CREATE,
    DELIVERY_NOTES_READ,
    HISTORICAL_IMPORTS_CONFIRM,
    HISTORICAL_IMPORTS_EXPORT,
    HISTORICAL_IMPORTS_READ,
    HISTORICAL_IMPORTS_REVERT,
    HISTORICAL_IMPORTS_REVIEW,
    HISTORICAL_IMPORTS_UPLOAD,
    INVENTORY_MOVE,
    INVENTORY_READ,
    PREDICTIONS_READ,
    PRODUCTS_READ,
    PRODUCTS_WRITE,
    role_has_permission,
)

pages_bp = Blueprint("pages", __name__)

_DASHBOARD_ROLES = (ROLE_ADMIN, ROLE_INVENTARIO)


@pages_bp.get("/login")
def login():
    if current_user.is_authenticated:
        if current_user.role in _DASHBOARD_ROLES:
            return redirect(url_for("pages.dashboard"))
        return redirect(url_for("pages.delivery_notes"))
    return render_template("login.html")


@pages_bp.get("/forgot-password")
def forgot_password():
    return render_template("forgot_password.html")


@pages_bp.get("/reset-password")
def reset_password():
    # El token llega en el query string (?token=...) y lo lee el JS.
    return render_template("reset_password.html")


@pages_bp.get("/products")
@login_required
def products():
    # Lectura permitida a todos los roles autenticados (igual que la API).
    # can_write controla los botones de crear/editar; la API valida igual.
    return render_template(
        "products.html",
        can_write=role_has_permission(current_user.role, PRODUCTS_WRITE),
    )


@pages_bp.get("/categories")
@login_required
def categories():
    return render_template(
        "categories.html",
        can_write=role_has_permission(current_user.role, CATEGORIES_WRITE),
    )


@pages_bp.get("/catalog")
@login_required
def catalog():
    """Catálogo visual de solo consulta para los roles autenticados."""
    return render_template("catalog.html")


@pages_bp.get("/chatbot")
@login_required
def chatbot():
    """Asistente interno de consulta para roles con lectura de productos."""
    if not role_has_permission(current_user.role, PRODUCTS_READ):
        return redirect(url_for("pages.access_denied"))
    return render_template(
        "chatbot.html",
        can_view_stock=current_user.role in _DASHBOARD_ROLES,
    )


@pages_bp.get("/profile")
@login_required
def profile():
    return render_template("profile.html")


@pages_bp.get("/inventory")
@login_required
def inventory():
    if not role_has_permission(current_user.role, INVENTORY_READ):
        return redirect(url_for("pages.access_denied"))
    return render_template(
        "inventory.html",
        can_move=role_has_permission(current_user.role, INVENTORY_MOVE),
    )


@pages_bp.get("/delivery-notes")
@login_required
def delivery_notes():
    if not role_has_permission(current_user.role, DELIVERY_NOTES_READ):
        return redirect(url_for("pages.access_denied"))
    return render_template(
        "delivery_notes.html",
        can_create=role_has_permission(current_user.role, DELIVERY_NOTES_CREATE),
        can_cancel=role_has_permission(current_user.role, DELIVERY_NOTES_CANCEL),
    )


@pages_bp.get("/historical-imports")
@login_required
def historical_imports():
    if not role_has_permission(current_user.role, HISTORICAL_IMPORTS_READ):
        return redirect(url_for("pages.access_denied"))
    return render_template(
        "historical_imports.html",
        can_upload=role_has_permission(
            current_user.role, HISTORICAL_IMPORTS_UPLOAD
        ),
        can_review=role_has_permission(
            current_user.role, HISTORICAL_IMPORTS_REVIEW
        ),
        can_confirm=role_has_permission(
            current_user.role, HISTORICAL_IMPORTS_CONFIRM
        ),
        can_revert=role_has_permission(
            current_user.role, HISTORICAL_IMPORTS_REVERT
        ),
        can_export=role_has_permission(
            current_user.role, HISTORICAL_IMPORTS_EXPORT
        ),
        historical_csrf_token=generate_csrf(),
    )


@pages_bp.get("/predictions")
@login_required
def predictions():
    if not role_has_permission(current_user.role, PREDICTIONS_READ):
        return redirect(url_for("pages.access_denied"))
    return render_template("predictions.html")


@pages_bp.get("/access-denied")
def access_denied():
    return render_template("access_denied.html")


@pages_bp.get("/dashboard")
@login_required
def dashboard():
    if current_user.role not in _DASHBOARD_ROLES:
        return redirect(url_for("pages.access_denied"))
    return render_template("dashboard.html")

