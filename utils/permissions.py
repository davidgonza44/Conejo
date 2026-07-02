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
DELIVERY_NOTES_CREATE = "delivery_notes:create"
REPORTS_READ = "reports:read"
USERS_MANAGE = "users:manage"

_ALL_PERMISSIONS = {
    PRODUCTS_READ,
    PRODUCTS_WRITE,
    CATEGORIES_WRITE,
    INVENTORY_MOVE,
    INVENTORY_READ,
    DELIVERY_NOTES_CREATE,
    REPORTS_READ,
    USERS_MANAGE,
}

ROLE_PERMISSIONS: dict[str, set[str]] = {
    ROLE_ADMIN: _ALL_PERMISSIONS,
    ROLE_INVENTARIO: {
        PRODUCTS_READ,
        PRODUCTS_WRITE,
        CATEGORIES_WRITE,
        INVENTORY_MOVE,
        INVENTORY_READ,
        REPORTS_READ,
    },
    ROLE_VENDEDOR: {
        PRODUCTS_READ,
        DELIVERY_NOTES_CREATE,
    },
}


def role_has_permission(role: str, permission: str) -> bool:
    return permission in ROLE_PERMISSIONS.get(role, set())
