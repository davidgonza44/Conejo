"""Controlador de autenticación: traduce HTTP <-> servicio."""
from flask import current_app, jsonify, request
from flask_login import current_user

from app.extensions import oauth
from app.services import auth_service, google_auth_service, passwordless_service
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


def passwordless_request():
    response = passwordless_service.request_token(_json_body())
    return jsonify(response)


def passwordless_verify():
    user = passwordless_service.verify(_json_body())
    return jsonify({"message": f"Bienvenido, {user.name}.", "user": user.to_dict()})


def google_login():
    """Redirige al consentimiento de Google (flujo Authorization Code + OIDC)."""
    google_auth_service.ensure_configured()
    redirect_uri = current_app.config["GOOGLE_REDIRECT_URI"]
    return oauth.google.authorize_redirect(redirect_uri)


def google_callback():
    """Recibe el code de Google, valida el id_token e inicia la sesión."""
    google_auth_service.ensure_configured()
    # authorize_access_token valida firma, audiencia, emisor, expiración y
    # nonce del id_token según la metadata OIDC de Google.
    token = oauth.google.authorize_access_token()
    userinfo = token.get("userinfo")
    if not userinfo:
        raise ValidationError("Google no devolvió el id_token esperado.", status_code=401)

    user, action = google_auth_service.login_from_userinfo(dict(userinfo))
    messages = {
        "login": f"Bienvenido, {user.name}.",
        "linked": f"Cuenta de Google vinculada. Bienvenido, {user.name}.",
        "created": f"Usuario creado con Google. Bienvenido, {user.name}.",
    }
    return jsonify({"message": messages[action], "action": action, "user": user.to_dict()})
