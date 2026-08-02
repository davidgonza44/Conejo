"""Controlador de productos: traduce HTTP <-> servicio."""
from flask import jsonify, request

from app.services import product_image_service, product_service
from app.services.exceptions import ValidationError


def _json_body() -> dict:
    data = request.get_json(silent=True)
    if data is None or not isinstance(data, dict):
        raise ValidationError("El cuerpo de la petición debe ser un JSON válido.")
    return data


def list_products():
    category_id = request.args.get("category_id", type=int)
    products = product_service.list_products(
        search=request.args.get("search"),
        category_id=category_id,
        low_stock=request.args.get("low_stock", "").lower() in ("1", "true", "si"),
        include_inactive=request.args.get("include_inactive", "").lower()
        in ("1", "true", "si"),
    )
    return jsonify({"count": len(products), "items": [p.to_dict() for p in products]})


def list_low_stock_products():
    products = product_service.list_products(low_stock=True)
    return jsonify({"count": len(products), "items": [p.to_dict() for p in products]})


def get_product(product_id: int):
    product = product_service.get_product_or_404(product_id)
    return jsonify(product.to_dict())


def create_product():
    product = product_service.create_product(_json_body())
    return jsonify(product.to_dict()), 201


def update_product(product_id: int):
    product = product_service.update_product(product_id, _json_body())
    return jsonify(product.to_dict())


def deactivate_product(product_id: int):
    product = product_service.deactivate_product(product_id)
    return jsonify(
        {
            "message": f"Producto '{product.name}' desactivado correctamente.",
            "product": product.to_dict(),
        }
    )


def upload_product_image(product_id: int):
    """Sube/reemplaza la imagen (multipart/form-data, campo 'image')."""
    product = product_image_service.set_image(product_id, request.files.get("image"))
    return jsonify(
        {
            "message": "Imagen del producto actualizada correctamente.",
            "image_url": product.image_url,
            "product": product.to_dict(),
        }
    )


def delete_product_image(product_id: int):
    product = product_image_service.remove_image(product_id)
    return jsonify(
        {
            "message": "Imagen del producto eliminada correctamente.",
            "product": product.to_dict(),
        }
    )
