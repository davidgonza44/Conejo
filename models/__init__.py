"""Modelos del sistema. Importarlos aquí los registra en SQLAlchemy."""
from app.models.user import User
from app.models.auth_identity import AuthIdentity
from app.models.passwordless_token import PasswordlessToken
from app.models.category import Category
from app.models.product import Product
from app.models.stock_movement import StockMovement
from app.models.delivery_note import DeliveryNote, DeliveryNoteItem

__all__ = [
    "User",
    "AuthIdentity",
    "PasswordlessToken",
    "Category",
    "Product",
    "StockMovement",
    "DeliveryNote",
    "DeliveryNoteItem",
]
