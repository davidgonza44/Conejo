"""Controlador de autenticación: traduce HTTP <-> servicio."""
from flask import jsonify, request
from flask_login import current_user

from app.services import auth_service
from app.services.exceptions import ValidationError


def _json_body() -> dict:
    data = request.get_json(silent=True)
    if data is None or not isinstance(data, dict):
        raise ValidationError("El cuerpo de la petición debe ser un JSON válido.")
    return data


def register():
    user = auth_service.register(_json_body())
    return jsonify({"message": "Usuario registrado correctamente.", "user": user.to_dict()}), 201


def login():
    user = auth_service.login(_json_body())
    return jsonify({"message": f"Bienvenido, {user.name}.", "user": user.to_dict()})


def logout():
    auth_service.logout()
    return jsonify({"message": "Sesión cerrada correctamente."})


def me():
    if not current_user.is_authenticated:
        return jsonify({"error": "No hay sesión activa."}), 401
    return jsonify(current_user.to_dict())
