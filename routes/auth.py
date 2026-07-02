"""Rutas REST de autenticación."""
from flask import Blueprint

from app.controllers import auth_controller

auth_bp = Blueprint("auth", __name__, url_prefix="/api/auth")

auth_bp.add_url_rule("/register", view_func=auth_controller.register, methods=["POST"])
auth_bp.add_url_rule("/login", view_func=auth_controller.login, methods=["POST"])
auth_bp.add_url_rule("/logout", view_func=auth_controller.logout, methods=["POST"])
auth_bp.add_url_rule("/me", view_func=auth_controller.me, methods=["GET"])
