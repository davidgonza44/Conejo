"""Application factory del sistema de inventario."""
from flask import Flask, jsonify, redirect, request, url_for

from app.config import Config
from app.extensions import db, login_manager, oauth


def create_app(config_class: type = Config) -> Flask:
    app = Flask(__name__)
    app.config.from_object(config_class)

    db.init_app(app)
    login_manager.init_app(app)
    oauth.init_app(app)

    from app.services.google_auth_service import register_oauth_client

    register_oauth_client(app)

    @login_manager.unauthorized_handler
    def handle_unauthorized():
        # API y archivos media: JSON 401. Páginas web: redirigen al login.
        if request.path.startswith("/api/") or request.path.startswith("/media/"):
            return jsonify({"error": "Autenticación requerida."}), 401
        return redirect(url_for("pages.login"))

    from app import models  # noqa: F401  (registra los modelos en SQLAlchemy)

    from app.routes.main import main_bp
    from app.routes.auth import auth_bp
    from app.routes.users import users_bp
    from app.routes.categories import categories_bp
    from app.routes.products import products_bp
    from app.routes.inventory import inventory_bp
    from app.routes.delivery_notes import delivery_notes_bp
    from app.routes.reports import reports_bp
    from app.routes.pages import pages_bp
    from app.routes.media import media_bp
    from app.routes.chatbot import chatbot_bp
    from app.routes.historical_imports import historical_imports_bp
    from app.routes.predictions import predictions_bp

    app.register_blueprint(main_bp)
    app.register_blueprint(auth_bp)
    app.register_blueprint(users_bp)
    app.register_blueprint(categories_bp)
    app.register_blueprint(products_bp)
    app.register_blueprint(inventory_bp)
    app.register_blueprint(delivery_notes_bp)
    app.register_blueprint(reports_bp)
    app.register_blueprint(pages_bp)
    app.register_blueprint(media_bp)
    app.register_blueprint(chatbot_bp)
    app.register_blueprint(historical_imports_bp)
    app.register_blueprint(predictions_bp)

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

    @app.errorhandler(413)
    def handle_payload_too_large(_):
        return jsonify({"error": "La petición excede el tamaño permitido."}), 413

    return app
