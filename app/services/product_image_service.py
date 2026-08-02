"""Imágenes de producto: guarda el archivo en uploads/products y persiste
solo la ruta relativa (/media/products/<archivo>) en products.image_url.

No se usa base64 ni se crea ninguna columna nueva: se reutiliza el campo
image_url que ya existía en el modelo Product.
"""
from werkzeug.datastructures import FileStorage

from app.extensions import db
from app.services import product_service, upload_service

_MEDIA_PREFIX = "/media/products/"


def _stored_filename(image_url: str | None) -> str | None:
    """Extrae el nombre de archivo si image_url apunta a nuestra carpeta local.

    URLs externas (p. ej. asignadas por Postman con el CRUD JSON) se ignoran:
    no hay archivo local que borrar.
    """
    if image_url and image_url.startswith(_MEDIA_PREFIX):
        return image_url[len(_MEDIA_PREFIX):]
    return None


def set_image(product_id: int, file: FileStorage | None):
    """Guarda/reemplaza la imagen del producto. Devuelve el producto."""
    product = product_service.get_product_or_404(product_id)

    old_filename = _stored_filename(product.image_url)
    filename = upload_service.save_image(
        file, upload_service.PRODUCTS_FOLDER, prefix=f"p{product.id}"
    )

    product.image_url = f"{_MEDIA_PREFIX}{filename}"
    db.session.commit()

    # El archivo anterior se borra al final: si algo falla antes, no se pierde.
    upload_service.delete_image(upload_service.PRODUCTS_FOLDER, old_filename)
    return product


def remove_image(product_id: int):
    """Quita la imagen del producto (borra archivo local si lo hay)."""
    product = product_service.get_product_or_404(product_id)

    old_filename = _stored_filename(product.image_url)
    product.image_url = None
    db.session.commit()

    upload_service.delete_image(upload_service.PRODUCTS_FOLDER, old_filename)
    return product
