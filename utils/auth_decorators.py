"""Decoradores de autenticación y autorización para las rutas de la API."""
from functools import wraps

from flask import jsonify
from flask_login import current_user
from flask_login import login_required as _flask_login_required

from app.utils.permissions import role_has_permission

# Reexportado: el manejador unauthorized de la app lo convierte en JSON 401.
login_required = _flask_login_required


def role_required(*roles: str):
    """Permite el acceso solo a los roles indicados (401 sin sesión, 403 sin rol)."""

    def decorator(view):
        @wraps(view)
        def wrapper(*args, **kwargs):
            if not current_user.is_authenticated:
                return jsonify({"error": "Autenticación requerida."}), 401
            if current_user.role not in roles:
                return (
                    jsonify(
                        {
                            "error": (
                                f"Acceso denegado: se requiere rol "
                                f"{' o '.join(roles)}."
                            )
                        }
                    ),
                    403,
                )
            return view(*args, **kwargs)

        return wrapper

    return decorator


def permission_required(permission: str):
    """Permite el acceso solo a roles que tengan el permiso indicado."""

    def decorator(view):
        @wraps(view)
        def wrapper(*args, **kwargs):
            if not current_user.is_authenticated:
                return jsonify({"error": "Autenticación requerida."}), 401
            if not role_has_permission(current_user.role, permission):
                return (
                    jsonify(
                        {"error": f"Acceso denegado: falta el permiso '{permission}'."}
                    ),
                    403,
                )
            return view(*args, **kwargs)

        return wrapper

    return decorator
