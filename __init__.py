"""Application factory del sistema de inventario."""
from flask import Flask, jsonify

from app.config import Config
from app.extensions import db, login_manager


def create_app(config_class: type = Config) -> Flask:
    app = Flask(__name__)
    app.config.from_object(config_class)

    db.init_app(app)
    login_manager.init_app(app)

    @login_manager.unauthorized_handler
    def handle_unauthorized():
        return jsonify({"error": "Autenticación requerida."}), 401

    from app import models  # noqa: F401  (registra los modelos en SQLAlchemy)

    from app.routes.main import main_bp
    from app.routes.auth import auth_bp
    from app.routes.users import users_bp
    from app.routes.categories import categories_bp
    from app.routes.products import products_bp
    from app.routes.inventory import inventory_bp

    app.register_blueprint(main_bp)
    app.register_blueprint(auth_bp)
    app.register_blueprint(users_bp)
    app.register_blueprint(categories_bp)
    app.register_blueprint(products_bp)
    app.register_blueprint(inventory_bp)

    from app.services.exceptions import ApiError

    @app.errorhandler(ApiError)
    def handle_api_error(error: ApiError):
        return jsonify({"error": error.message}), error.status_code

    @app.errorhandler(404)
    def handle_not_found(_):
        return jsonify({"error": "Ruta no encontrada."}), 404

    @app.errorhandler(405)
    def handle_method_not_allowed(_):
        return jsonify({"error": "Método HTTP no permitido para esta ruta."}), 405

    return app
