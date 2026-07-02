"""Rutas web (páginas HTML renderizadas con Jinja2).

Las rutas /api/* no se tocan: siguen devolviendo JSON puro.
Acceso al dashboard: solo admin e inventario; vendedor ve acceso denegado.
"""
from flask import Blueprint, redirect, render_template, url_for
from flask_login import current_user, login_required

from app.models.user import ROLE_ADMIN, ROLE_INVENTARIO

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


@pages_bp.get("/access-denied")
def access_denied():
    return render_template("access_denied.html")


@pages_bp.get("/dashboard")
@login_required
def dashboard():
    if current_user.role not in _DASHBOARD_ROLES:
        return redirect(url_for("pages.access_denied"))
    return render_template("dashboard.html")
