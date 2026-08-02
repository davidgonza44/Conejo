"""Modelos del sistema. Importarlos aquí los registra en SQLAlchemy."""
from app.models.user import User
from app.models.auth_identity import AuthIdentity
from app.models.passwordless_token import PasswordlessToken
from app.models.password_reset_token import PasswordResetToken
from app.models.category import Category
from app.models.product import Product
from app.models.stock_movement import StockMovement
from app.models.delivery_note import DeliveryNote
from app.models.delivery_note_item import DeliveryNoteItem
from app.models.historical_import import HistoricalImport
from app.models.historical_demand_record import HistoricalDemandRecord
from app.models.historical_import_error import HistoricalImportError

__all__ = [
    "User",
    "AuthIdentity",
    "PasswordlessToken",
    "PasswordResetToken",
    "Category",
    "Product",
    "StockMovement",
    "DeliveryNote",
    "DeliveryNoteItem",
    "HistoricalImport",
    "HistoricalDemandRecord",
    "HistoricalImportError",
]
