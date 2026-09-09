"""Rutas web (páginas HTML renderizadas con Jinja2).

Las rutas /api/* no se tocan: siguen devolviendo JSON puro.
Acceso al dashboard: solo admin e inventario; vendedor ve acceso denegado.
"""
from flask import Blueprint, abort, current_app, redirect, render_template, request, url_for
from flask_login import current_user, login_required
from flask_wtf.csrf import generate_csrf

from app.models.user import ROLE_ADMIN, ROLE_INVENTARIO
from app.utils import inventory_reference, predictive_reference, reports_reference, sales_reference
from app.utils.permissions import (
    CATEGORIES_WRITE,
    DELIVERY_NOTES_CANCEL,
    DELIVERY_NOTES_CREATE,
    DELIVERY_NOTES_READ,
    HISTORICAL_IMPORTS_CONFIRM,
    HISTORICAL_IMPORTS_EXPORT,
    HISTORICAL_IMPORTS_READ,
    HISTORICAL_IMPORTS_REVERT,
    HISTORICAL_IMPORTS_REVIEW,
    HISTORICAL_IMPORTS_UPLOAD,
    INVENTORY_MOVE,
    INVENTORY_READ,
    PREDICTIONS_READ,
    PRODUCTS_READ,
    PRODUCTS_WRITE,
    REPORTS_READ,
    role_has_permission,
)

pages_bp = Blueprint("pages", __name__)

_DASHBOARD_ROLES = (ROLE_ADMIN, ROLE_INVENTARIO)


def _reference_mode():
    """Modo de referencia visual: solo en debug y con ``?ref=1``; nunca toca la BD."""
    return current_app.debug and request.args.get("ref") == "1"


@pages_bp.get("/login")
def login():
    if current_user.is_authenticated:
        if current_user.role in _DASHBOARD_ROLES:
            return redirect(url_for("pages.dashboard"))
        return redirect(url_for("pages.access_denied"))
    return render_template("login.html")


@pages_bp.get("/forgot-password")
def forgot_password():
    return render_template("forgot_password.html")


@pages_bp.get("/reset-password")
def reset_password():
    # El token llega en el query string (?token=...) y lo lee el JS.
    return render_template("reset_password.html")


@pages_bp.get("/products")
@login_required
def products():
    # Lectura permitida a todos los roles autenticados (igual que la API).
    # can_write controla los botones de crear/editar; la API valida igual.
    if _reference_mode():
        return _render_inventory("inventory/products.html", inventory_reference.PRODUCTS)
    return render_template(
        "products.html",
        can_write=role_has_permission(current_user.role, PRODUCTS_WRITE),
    )


@pages_bp.get("/categories")
@login_required
def categories():
    if _reference_mode():
        return _render_inventory("inventory/categories.html", inventory_reference.CATEGORIES)
    return render_template(
        "categories.html",
        can_write=role_has_permission(current_user.role, CATEGORIES_WRITE),
    )


@pages_bp.get("/catalog")
@login_required
def catalog():
    """Catálogo visual de solo consulta para los roles autenticados."""
    return render_template("catalog.html")


@pages_bp.get("/chatbot")
@login_required
def chatbot():
    """Asistente interno de consulta para roles con lectura de productos."""
    if not role_has_permission(current_user.role, PRODUCTS_READ):
        return redirect(url_for("pages.access_denied"))
    return render_template(
        "chatbot.html",
        can_view_stock=current_user.role in _DASHBOARD_ROLES,
    )


@pages_bp.get("/profile")
@login_required
def profile():
    return render_template("profile.html")


@pages_bp.get("/inventory")
@login_required
def inventory():
    if not role_has_permission(current_user.role, INVENTORY_READ):
        return redirect(url_for("pages.access_denied"))
    if _reference_mode():
        return _render_inventory("inventory/movements.html", inventory_reference.MOVEMENTS)
    return render_template(
        "inventory.html",
        can_move=role_has_permission(current_user.role, INVENTORY_MOVE),
    )


# --- Módulo Inventario (shell "ix") ----------------------------------------
# Resumen y Proveedores son pantallas nuevas sin servicio propio todavía: en modo
# normal muestran el estado veraz "no disponible". Movimientos y Categorías solo
# usan el shell "ix" en debug con ?ref=1; en modo normal conservan sus plantillas
# y datos reales. El fixture (app/utils/inventory_reference.py) no toca la BD.


def _render_inventory(template, fixture):
    reference_mode = _reference_mode()
    return render_template(template, reference_mode=reference_mode, fixture=fixture if reference_mode else None)


@pages_bp.get("/inventory/summary")
@login_required
def inventory_summary():
    if not role_has_permission(current_user.role, INVENTORY_READ):
        return redirect(url_for("pages.access_denied"))
    return _render_inventory("inventory/summary.html", inventory_reference.SUMMARY)


@pages_bp.get("/suppliers")
@login_required
def suppliers():
    if not role_has_permission(current_user.role, INVENTORY_READ):
        return redirect(url_for("pages.access_denied"))
    return _render_inventory("inventory/suppliers.html", inventory_reference.SUPPLIERS)


@pages_bp.get("/delivery-notes")
@login_required
def delivery_notes():
    if not role_has_permission(current_user.role, DELIVERY_NOTES_READ):
        return redirect(url_for("pages.access_denied"))
    return render_template(
        "delivery_notes.html",
        can_create=role_has_permission(current_user.role, DELIVERY_NOTES_CREATE),
        can_cancel=role_has_permission(current_user.role, DELIVERY_NOTES_CANCEL),
    )


@pages_bp.get("/historical-imports")
@login_required
def historical_imports():
    if not role_has_permission(current_user.role, HISTORICAL_IMPORTS_READ):
        return redirect(url_for("pages.access_denied"))
    return render_template(
        "historical_imports.html",
        can_upload=role_has_permission(
            current_user.role, HISTORICAL_IMPORTS_UPLOAD
        ),
        can_review=role_has_permission(
            current_user.role, HISTORICAL_IMPORTS_REVIEW
        ),
        can_confirm=role_has_permission(
            current_user.role, HISTORICAL_IMPORTS_CONFIRM
        ),
        can_revert=role_has_permission(
            current_user.role, HISTORICAL_IMPORTS_REVERT
        ),
        can_export=role_has_permission(
            current_user.role, HISTORICAL_IMPORTS_EXPORT
        ),
        historical_csrf_token=generate_csrf(),
    )


@pages_bp.get("/predictions")
@login_required
def predictions():
    if not role_has_permission(current_user.role, PREDICTIONS_READ):
        return redirect(url_for("pages.access_denied"))
    return render_template("predictions.html")


@pages_bp.get("/access-denied")
def access_denied():
    return render_template("access_denied.html")


@pages_bp.get("/dashboard")
@login_required
def dashboard():
    if current_user.role not in _DASHBOARD_ROLES:
        return redirect(url_for("pages.access_denied"))
    # Modo de referencia visual (solo en debug): la vista se dibuja con el
    # fixture determinista de dashboard_reference_data.js, sin tocar la BD.
    return render_template("dashboard.html", reference_mode=_reference_mode())


@pages_bp.get("/reports")
@login_required
def reports():
    """Dashboard de Reportes (shell "ix"). La réplica visual solo existe en debug con
    ?ref=1 y usa el fixture de app/utils/reports_reference.py (no toca la BD); en modo
    normal los reportes reales siguen viviendo en Inicio (/dashboard)."""
    if current_user.role not in _DASHBOARD_ROLES:
        return redirect(url_for("pages.access_denied"))
    if not _reference_mode():
        return redirect(url_for("pages.dashboard"))
    return render_template("reports/dashboard.html", reference_mode=True, fixture=reports_reference.REPORTS)


# --- Módulo Ventas (shell "ix") ---------------------------------------------
# Nueve pantallas de referencia (collage aprobado de Ventas). Solo en debug con ?ref=1
# reciben el fixture determinista de app/utils/sales_reference.py (no toca la BD ni crea
# ventas, clientes, cotizaciones o pedidos). En modo normal `fixture` es None y la vista
# muestra el estado veraz "no disponible" que enlaza con las notas de entrega reales.


def _render_sales(template, fixture, permission=DELIVERY_NOTES_READ, **context):
    if not role_has_permission(current_user.role, permission):
        return redirect(url_for("pages.access_denied"))
    reference_mode = _reference_mode()
    return render_template(
        template,
        reference_mode=reference_mode,
        fixture=fixture if reference_mode else None,
        sales_menu=sales_reference.MENU,
        **context,
    )


@pages_bp.get("/sales")
@login_required
def sales():
    return _render_sales("sales/dashboard.html", sales_reference.DASHBOARD)


@pages_bp.get("/sales/list")
@login_required
def sales_list():
    return _render_sales("sales/list.html", sales_reference.SALES_LIST)


@pages_bp.get("/sales/new")
@login_required
def sales_new():
    return _render_sales("sales/new.html", sales_reference.NEW_SALE)


@pages_bp.get("/sales/quotes")
@login_required
def sales_quotes():
    return _render_sales("sales/quotes.html", sales_reference.QUOTES)


@pages_bp.get("/sales/orders")
@login_required
def sales_orders():
    return _render_sales("sales/orders.html", sales_reference.ORDERS)


@pages_bp.get("/sales/customers")
@login_required
def sales_customers():
    return _render_sales("sales/customers.html", sales_reference.CUSTOMERS)


@pages_bp.get("/sales/reports")
@login_required
def sales_reports():
    if not role_has_permission(current_user.role, REPORTS_READ):
        return redirect(url_for("pages.access_denied"))
    params = {"tab": request.args.get("tab", "summary")}
    if _reference_mode():
        params["ref"] = "1"
    return redirect(url_for("pages.report_sales", **params))


@pages_bp.get("/reports/sales")
@login_required
def report_sales():
    """Historical report previews; reference fixtures never reach persistence."""
    if not role_has_permission(current_user.role, REPORTS_READ):
        return redirect(url_for("pages.access_denied"))
    from app.utils.report_sales_reference import REPORT, TABS
    tab = request.args.get("tab", "summary")
    if tab not in dict(TABS):
        abort(404)
    reference_mode = _reference_mode()
    return render_template("reports/sales.html", reference_mode=reference_mode,
                           fixture=REPORT if reference_mode else None, tab=tab, tabs=TABS)


def _sale_fixture(sale_number, fixture):
    """En modo referencia solo existe la venta del fixture; cualquier otro número es 404."""
    if _reference_mode() and sale_number != sales_reference.SALE_NUMBER:
        abort(404)
    return fixture


@pages_bp.get("/sales/<sale_number>")
@login_required
def sale_detail(sale_number):
    return _render_sales("sales/detail.html", _sale_fixture(sale_number, sales_reference.SALE_DETAIL))


@pages_bp.get("/sales/<sale_number>/print")
@login_required
def sale_print(sale_number):
    return _render_sales("sales/print.html", _sale_fixture(sale_number, sales_reference.SALE_PRINT))


# --- Módulo Análisis predictivo -------------------------------------------
# Cinco destinos con el shell "ix". Solo en debug con ?ref=1 reciben el fixture
# determinista de app/utils/predictive_reference.py (no toca la BD); en modo
# normal `fixture` es None y la vista muestra el estado veraz "no disponible".


def _render_predictive(template, fixture, **context):
    if not role_has_permission(current_user.role, PREDICTIONS_READ):
        return redirect(url_for("pages.access_denied"))
    reference_mode = _reference_mode()
    return render_template(
        template,
        reference_mode=reference_mode,
        fixture=fixture if reference_mode else None,
        **context,
    )


@pages_bp.get("/predictive/demand")
@login_required
def demand_forecast():
    return _render_predictive("predictive/demand_forecast.html", predictive_reference.FORECAST)


@pages_bp.get("/predictive/replenishment")
@login_required
def replenishment():
    return _render_predictive("predictive/replenishment.html", predictive_reference.REPLENISHMENT)


@pages_bp.get("/predictive/critical")
@login_required
def critical_products():
    return _render_predictive("predictive/critical_products.html", predictive_reference.CRITICAL)


@pages_bp.get("/predictive/trends")
@login_required
def trends():
    state = predictive_reference.trends_state(request.args.get("trend", ""))
    return _render_predictive("predictive/trends.html", predictive_reference.TRENDS, trend_state=state)


@pages_bp.get("/predictive/accuracy")
@login_required
def model_accuracy():
    return _render_predictive("predictive/model_accuracy.html", predictive_reference.ACCURACY)



@pages_bp.get("/settings")
@login_required
def settings():
    """Read-only settings previews; reference values never reach persistence."""
    if current_user.role != ROLE_ADMIN:
        return redirect(url_for("pages.access_denied"))
    from app.utils.settings_reference import SETTINGS, TABS

    tab = request.args.get("tab", "general")
    if tab not in dict(TABS):
        abort(404)
    reference_mode = _reference_mode()
    return render_template(
        "settings/page.html", tab=tab, tabs=TABS,
        reference_mode=reference_mode, fixture=SETTINGS if reference_mode else None,
    )
