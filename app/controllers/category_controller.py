"""Controlador de categorías: traduce HTTP <-> servicio."""
from flask import jsonify, request

from app.services import category_service
from app.services.exceptions import ValidationError


def _json_body() -> dict:
    data = request.get_json(silent=True)
    if data is None or not isinstance(data, dict):
        raise ValidationError("El cuerpo de la petición debe ser un JSON válido.")
    return data


def list_categories():
    categories = category_service.list_categories()
    return jsonify({"count": len(categories), "items": [c.to_dict() for c in categories]})


def get_category(category_id: int):
    category = category_service.get_category_or_404(category_id)
    return jsonify(category.to_dict())


def create_category():
    category = category_service.create_category(_json_body())
    return jsonify(category.to_dict()), 201


def update_category(category_id: int):
    category = category_service.update_category(category_id, _json_body())
    return jsonify(category.to_dict())


def delete_category(category_id: int):
    category_service.delete_category(category_id)
    return jsonify({"message": f"Categoría {category_id} eliminada correctamente."})
