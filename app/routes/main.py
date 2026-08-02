"""Rutas básicas para verificar que el backend y la base de datos funcionan."""
from flask import Blueprint, jsonify
from sqlalchemy import text

from app.extensions import db
from app.models import Category, Product

main_bp = Blueprint("main", __name__)


@main_bp.get("/")
def index():
    return jsonify(
        {
            "system": (
                "Sistema inteligente de apoyo al control de inventario — "
                "Ferretería y Construcciones El Conejo C.A."
            ),
            "status": "ok",
            "version": "0.1.0 (incremento 1: base del backend)",
        }
    )


@main_bp.get("/health/db")
def health_db():
    try:
        db.session.execute(text("SELECT 1"))
        return jsonify({"database": "ok", "message": "Conexión a MySQL exitosa"})
    except Exception as exc:  # noqa: BLE001 - se reporta el error de conexión
        return (
            jsonify({"database": "error", "message": str(exc)}),
            500,
        )


@main_bp.get("/api/test/categories")
def test_categories():
    categories = Category.query.order_by(Category.name).all()
    return jsonify({"count": len(categories), "items": [c.to_dict() for c in categories]})


@main_bp.get("/api/test/products")
def test_products():
    products = Product.query.order_by(Product.code).all()
    return jsonify({"count": len(products), "items": [p.to_dict() for p in products]})
