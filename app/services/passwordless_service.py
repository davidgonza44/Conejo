"""Login passwordless mediante token temporal de un solo uso.

Seguridad:
- Solo se guarda el hash SHA-256 del token; el token plano nunca toca la BD.
- El endpoint de solicitud responde siempre lo mismo (respuesta neutra) para
  no revelar si un correo está registrado (evita enumeración de usuarios).
- El token expira (PASSWORDLESS_TOKEN_MINUTES) y se invalida al usarse.
"""
import hashlib
import logging
import re
import secrets
from datetime import datetime, timedelta

from flask import current_app
from flask_login import login_user

from app.extensions import db
from app.models import AuthIdentity, PasswordlessToken, User
from app.models.auth_identity import PROVIDER_PASSWORDLESS
from app.services import email_service
from app.services.exceptions import ValidationError

logger = logging.getLogger(__name__)

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

NEUTRAL_MESSAGE = (
    "Si el correo está registrado, recibirá un código de acceso temporal."
)


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _clean_email(data: dict) -> str:
    email = (data.get("email") or "").strip().lower()
    if not _EMAIL_RE.match(email):
        raise ValidationError("El campo 'email' no tiene un formato válido.")
    return email


def _send_token_email(user: User, token: str, minutes: int) -> None:
    """Envía el código passwordless por correo real cuando MAIL_ENABLED=true.

    En development los errores de correo se propagan como JSON claro para
    poder diagnosticarlos; en production solo se registran y la respuesta
    sigue siendo neutra (anti-enumeración).
    """
    if not email_service.is_enabled():
        return
    base_url = current_app.config["APP_BASE_URL"].rstrip("/")
    try:
        email_service.send_template_email(
            to=user.email,
            subject=f"Su código de acceso — {current_app.config['MAIL_FROM_NAME']}",
            template="passwordless",
            user_name=user.name,
            token=token,
            expires_minutes=minutes,
            login_url=f"{base_url}/login",
        )
    except email_service.EmailError:
        if current_app.config["APP_ENV"] == "development":
            raise
        logger.warning(
            "No se pudo enviar el código passwordless a %s.",
            email_service.mask_email(user.email),
        )


def request_token(data: dict) -> dict:
    """Genera un token temporal si el email pertenece a un usuario activo.

    La respuesta es neutra en todos los casos. En APP_ENV=development se
    incluye el token para pruebas; en producción se enviaría por correo.
    """
    email = _clean_email(data)
    response: dict = {"message": NEUTRAL_MESSAGE}

    user = User.query.filter_by(email=email).first()
    if user is None or not user.is_active:
        # Respuesta idéntica a la del caso exitoso: no revelar nada.
        return response

    # Invalida tokens anteriores no usados de este correo (solo vale el último).
    PasswordlessToken.query.filter(
        PasswordlessToken.email == email,
        PasswordlessToken.used_at.is_(None),
    ).update({PasswordlessToken.used_at: datetime.utcnow()})

    token = secrets.token_urlsafe(32)
    minutes = current_app.config["PASSWORDLESS_TOKEN_MINUTES"]
    db.session.add(
        PasswordlessToken(
            user_id=user.id,
            email=email,
            token_hash=_hash_token(token),
            expires_at=datetime.utcnow() + timedelta(minutes=minutes),
        )
    )
    db.session.commit()

    # Envío por correo real (si MAIL_ENABLED=true). La lógica de seguridad
    # del token (hash, un solo uso, expiración) no cambia.
    _send_token_email(user, token, minutes)

    if current_app.config["APP_ENV"] == "development":
        response["dev_token"] = token
        response["expires_in_minutes"] = minutes

    return response


def verify(data: dict) -> User:
    """Valida email + token; si es correcto inicia la sesión del usuario."""
    email = _clean_email(data)
    token = (data.get("token") or "").strip()
    if not token:
        raise ValidationError("El campo 'token' es obligatorio.")

    record = PasswordlessToken.query.filter_by(
        email=email, token_hash=_hash_token(token)
    ).first()

    if record is None:
        raise ValidationError("Token inválido.", status_code=401)
    if record.is_used:
        raise ValidationError("El token ya fue utilizado.", status_code=401)
    if record.is_expired:
        raise ValidationError("El token ha expirado. Solicite uno nuevo.", status_code=401)

    user = db.session.get(User, record.user_id) if record.user_id else None
    if user is None:
        raise ValidationError("Token inválido.", status_code=401)
    if not user.is_active:
        raise ValidationError(
            "El usuario está inactivo. Contacte al administrador.", status_code=401
        )

    record.used_at = datetime.utcnow()
    user.email_verified = True

    identity_exists = AuthIdentity.query.filter_by(
        provider=PROVIDER_PASSWORDLESS, provider_user_id=user.email
    ).first()
    if identity_exists is None:
        db.session.add(
            AuthIdentity(
                user_id=user.id,
                provider=PROVIDER_PASSWORDLESS,
                provider_user_id=user.email,
                email=user.email,
            )
        )

    db.session.commit()
    login_user(user)
    return user
