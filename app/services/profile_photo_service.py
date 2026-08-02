"""Foto de perfil del usuario autenticado.

Guarda el archivo en uploads/users/ y persiste solo profile_photo_filename
en la tabla users (nunca base64 ni rutas absolutas).
"""
from werkzeug.datastructures import FileStorage

from app.extensions import db
from app.models.user import User
from app.services import upload_service

_MEDIA_PREFIX = "/media/users/"


def _photo_url(user: User) -> str | None:
    if user.profile_photo_filename:
        return f"{_MEDIA_PREFIX}{user.profile_photo_filename}"
    return None


def set_photo(user: User, file: FileStorage | None) -> User:
    old_filename = user.profile_photo_filename
    filename = upload_service.save_image(
        file, upload_service.USERS_FOLDER, prefix=f"u{user.id}"
    )
    user.profile_photo_filename = filename
    db.session.commit()
    upload_service.delete_image(upload_service.USERS_FOLDER, old_filename)
    return user


def remove_photo(user: User) -> User:
    old_filename = user.profile_photo_filename
    user.profile_photo_filename = None
    db.session.commit()
    upload_service.delete_image(upload_service.USERS_FOLDER, old_filename)
    return user


def photo_response(user: User) -> dict:
    return {
        "message": "Foto de perfil actualizada correctamente.",
        "profile_photo_url": _photo_url(user),
        "user": user.to_dict(),
    }


def remove_response(user: User) -> dict:
    return {
        "message": "Foto de perfil eliminada correctamente.",
        "user": user.to_dict(),
    }
