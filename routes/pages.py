"""Rutas web (páginas HTML renderizadas con Jinja2).

Las rutas /api/* no se tocan: siguen devolviendo JSON puro.
Acceso al dashboard: solo admin e inventario; vendedor ve acceso denegado.
"""
from flask import Blueprint, redirect, render_template, url_for
from flask_login import current_user, login_required

from app.models.user import ROLE_ADMIN, ROLE_INVENTARIO
from app.utils.permissions import (
    CATEGORIES_WRITE,
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
        return redirect(url_for("pages.access_denied"))
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


@pages_bp.get("/access-denied")
def access_denied():
    return render_template("access_denied.html")


@pages_bp.get("/dashboard")
@login_required
def dashboard():
    if current_user.role not in _DASHBOARD_ROLES:
        return redirect(url_for("pages.access_denied"))
    return render_template("dashboard.html")
