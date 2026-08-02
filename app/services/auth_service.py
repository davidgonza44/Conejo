"""Lógica de negocio de autenticación local (email/username + contraseña)."""
import re

from flask_login import login_user, logout_user

from app.extensions import db
from app.models import AuthIdentity, User
from app.models.auth_identity import PROVIDER_LOCAL
from app.models.user import ROLE_VENDEDOR, ROLES
from app.services.exceptions import ConflictError, ValidationError

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
_USERNAME_RE = re.compile(r"^[a-zA-Z0-9_.-]{3,50}$")
_MIN_PASSWORD_LENGTH = 6


def register(data: dict) -> User:
    """Crea un usuario local. El rol por defecto es 'vendedor' (menor privilegio)."""
    name = (data.get("name") or "").strip()
    if not name:
        raise ValidationError("El campo 'name' es obligatorio.")

    email = (data.get("email") or "").strip().lower()
    if not _EMAIL_RE.match(email):
        raise ValidationError("El campo 'email' no tiene un formato válido.")

    username = (data.get("username") or "").strip().lower()
    if not _USERNAME_RE.match(username):
        raise ValidationError(
            "El campo 'username' debe tener entre 3 y 50 caracteres "
            "(letras, números, punto, guion o guion bajo)."
        )

    password = data.get("password") or ""
    if len(password) < _MIN_PASSWORD_LENGTH:
        raise ValidationError(
            f"La contraseña debe tener al menos {_MIN_PASSWORD_LENGTH} caracteres."
        )

    role = (data.get("role") or ROLE_VENDEDOR).strip().lower()
    if role not in ROLES:
        raise ValidationError(
            f"Rol inválido: '{role}'. Valores permitidos: {', '.join(ROLES)}."
        )

    if User.query.filter_by(email=email).first() is not None:
        raise ConflictError(f"Ya existe un usuario con el email '{email}'.")
    if User.query.filter_by(username=username).first() is not None:
        raise ConflictError(f"Ya existe un usuario con el username '{username}'.")

    user = User(name=name, email=email, username=username, role=role)
    user.set_password(password)
    db.session.add(user)
    db.session.flush()  # asigna user.id antes de crear la identidad

    db.session.add(
        AuthIdentity(
            user_id=user.id,
            provider=PROVIDER_LOCAL,
            provider_user_id=str(user.id),
            email=user.email,
        )
    )
    db.session.commit()
    return user


def login(data: dict) -> User:
    """Inicia sesión con email o username en el campo 'identifier'."""
    identifier = (data.get("identifier") or "").strip().lower()
    password = data.get("password") or ""
    if not identifier or not password:
        raise ValidationError("Los campos 'identifier' y 'password' son obligatorios.")

    user = User.query.filter(
        db.or_(User.email == identifier, User.username == identifier)
    ).first()

    # Mensaje genérico: no revelar si el usuario existe o si falló la contraseña.
    if user is None or not user.check_password(password):
        raise ValidationError("Credenciales inválidas.", status_code=401)

    if not user.is_active:
        raise ValidationError("El usuario está inactivo. Contacte al administrador.", status_code=401)

    login_user(user)
    return user


def logout() -> None:
    logout_user()
