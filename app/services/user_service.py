"""Lógica de negocio de gestión de usuarios (solo administradores)."""
from flask_login import current_user

from app.extensions import db
from app.models import User
from app.models.user import ROLES
from app.services import auth_service
from app.services.exceptions import NotFoundError, ValidationError


def get_user_or_404(user_id: int) -> User:
    user = db.session.get(User, user_id)
    if user is None:
        raise NotFoundError(f"El usuario con id {user_id} no existe.")
    return user


def list_users() -> list[User]:
    return User.query.order_by(User.name).all()


def create_user(data: dict) -> User:
    """Un admin crea un usuario; reutiliza las validaciones del registro."""
    return auth_service.register(data)


def update_user(user_id: int, data: dict) -> User:
    user = get_user_or_404(user_id)

    if "name" in data:
        name = (data.get("name") or "").strip()
        if not name:
            raise ValidationError("El campo 'name' no puede estar vacío.")
        user.name = name

    if "role" in data:
        role = (data.get("role") or "").strip().lower()
        if role not in ROLES:
            raise ValidationError(
                f"Rol inválido: '{role}'. Valores permitidos: {', '.join(ROLES)}."
            )
        if user.id == current_user.id and role != user.role:
            raise ValidationError("No puede cambiar su propio rol.")
        user.role = role

    if "is_active" in data:
        is_active = bool(data.get("is_active"))
        if user.id == current_user.id and not is_active:
            raise ValidationError("No puede desactivar su propia cuenta.")
        user.is_active = is_active

    if "password" in data:
        password = data.get("password") or ""
        if len(password) < 6:
            raise ValidationError("La contraseña debe tener al menos 6 caracteres.")
        user.set_password(password)

    db.session.commit()
    return user
