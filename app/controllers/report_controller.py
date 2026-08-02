"""Controlador de reportes: lee query params y delega en report_service."""
from flask import jsonify, request

from app.services import report_service


def _dates() -> dict:
    return {
        "date_from": request.args.get("date_from"),
        "date_to": request.args.get("date_to"),
    }


def dashboard_summary():
    return jsonify(report_service.dashboard_summary())


def stock_vs_minimum():
    return jsonify(report_service.stock_vs_minimum())


def low_stock_products():
    return jsonify(report_service.low_stock_products())


def products_without_movement():
    return jsonify(
        report_service.products_without_movement(days=request.args.get("days"))
    )


def excess_stock_products():
    return jsonify(
        report_service.excess_stock_products(multiplier=request.args.get("multiplier"))
    )


def entries_vs_exits():
    return jsonify(report_service.entries_vs_exits(**_dates()))


def movements_by_category():
    return jsonify(report_service.movements_by_category(**_dates()))


def top_products_by_exits():
    return jsonify(
        report_service.top_products_by_exits(**_dates(), limit=request.args.get("limit"))
    )


def least_products_by_exits():
    return jsonify(
        report_service.least_products_by_exits(**_dates(), limit=request.args.get("limit"))
    )


def inventory_adjustments():
    return jsonify(report_service.inventory_adjustments(**_dates()))


def delivery_notes_by_period():
    return jsonify(report_service.delivery_notes_by_period(**_dates()))


def top_delivered_products():
    return jsonify(
        report_service.top_delivered_products(**_dates(), limit=request.args.get("limit"))
    )


def delivery_notes_by_user():
    return jsonify(report_service.delivery_notes_by_user(**_dates()))


def delivery_notes_by_customer():
    return jsonify(
        report_service.delivery_notes_by_customer(
            **_dates(), limit=request.args.get("limit")
        )
    )
