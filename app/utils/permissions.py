"""Mapa de permisos por rol (autorización).

El rol define QUÉ puede hacer el usuario; la autenticación define QUIÉN es.
"""
from app.models.user import ROLE_ADMIN, ROLE_INVENTARIO, ROLE_VENDEDOR

# Permisos granulares del sistema.
PRODUCTS_READ = "products:read"
PRODUCTS_WRITE = "products:write"
CATEGORIES_WRITE = "categories:write"
INVENTORY_MOVE = "inventory:move"      # entradas, salidas y ajustes manuales
INVENTORY_READ = "inventory:read"      # historial de movimientos
DELIVERY_NOTES_READ = "delivery_notes:read"
DELIVERY_NOTES_CREATE = "delivery_notes:create"
DELIVERY_NOTES_CANCEL = "delivery_notes:cancel"
REPORTS_READ = "reports:read"
USERS_MANAGE = "users:manage"
HISTORICAL_IMPORTS_READ = "historical_imports:read"
HISTORICAL_IMPORTS_EXPORT = "historical_imports:export"
HISTORICAL_IMPORTS_UPLOAD = "historical_imports:upload"
HISTORICAL_IMPORTS_REVIEW = "historical_imports:review"
HISTORICAL_IMPORTS_CONFIRM = "historical_imports:confirm"
HISTORICAL_IMPORTS_REVERT = "historical_imports:revert"

_ALL_PERMISSIONS = {
    PRODUCTS_READ,
    PRODUCTS_WRITE,
    CATEGORIES_WRITE,
    INVENTORY_MOVE,
    INVENTORY_READ,
    DELIVERY_NOTES_READ,
    DELIVERY_NOTES_CREATE,
    DELIVERY_NOTES_CANCEL,
    REPORTS_READ,
    USERS_MANAGE,
    HISTORICAL_IMPORTS_READ,
    HISTORICAL_IMPORTS_EXPORT,
    HISTORICAL_IMPORTS_UPLOAD,
    HISTORICAL_IMPORTS_REVIEW,
    HISTORICAL_IMPORTS_CONFIRM,
    HISTORICAL_IMPORTS_REVERT,
}

ROLE_PERMISSIONS: dict[str, set[str]] = {
    ROLE_ADMIN: _ALL_PERMISSIONS,
    ROLE_INVENTARIO: {
        PRODUCTS_READ,
        PRODUCTS_WRITE,
        CATEGORIES_WRITE,
        INVENTORY_MOVE,
        INVENTORY_READ,
        DELIVERY_NOTES_READ,
        DELIVERY_NOTES_CANCEL,
        REPORTS_READ,
        HISTORICAL_IMPORTS_READ,
        HISTORICAL_IMPORTS_EXPORT,
    },
    ROLE_VENDEDOR: {
        PRODUCTS_READ,
        DELIVERY_NOTES_READ,
        DELIVERY_NOTES_CREATE,
    },
}


def role_has_permission(role: str, permission: str) -> bool:
    return permission in ROLE_PERMISSIONS.get(role, set())
