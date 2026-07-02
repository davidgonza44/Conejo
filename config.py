"""Configuración de la aplicación leída desde variables de entorno (.env)."""
import os
from urllib.parse import quote_plus

from dotenv import load_dotenv

load_dotenv()


def _env_bool(name: str, default: str = "false") -> bool:
    """Interpreta variables de entorno booleanas ('true', '1', 'yes')."""
    return os.getenv(name, default).strip().lower() in ("true", "1", "yes")


class Config:
    SECRET_KEY = os.getenv("SECRET_KEY", "clave-insegura-solo-desarrollo")

    # 'development' o 'production'. En desarrollo, el token passwordless se
    # devuelve en la respuesta para pruebas; en producción, jamás.
    APP_ENV = os.getenv("APP_ENV", "development")

    # URL base pública usada para armar enlaces enviados por correo
    # (p. ej. el enlace de restablecimiento de contraseña).
    APP_BASE_URL = os.getenv("APP_BASE_URL", "http://localhost:5000")

    # Minutos de vigencia del token passwordless.
    PASSWORDLESS_TOKEN_MINUTES = int(os.getenv("PASSWORDLESS_TOKEN_MINUTES", "15"))

    # Minutos de vigencia del token de recuperación de contraseña.
    PASSWORD_RESET_TOKEN_MINUTES = int(os.getenv("PASSWORD_RESET_TOKEN_MINUTES", "30"))

    # --- Correo saliente (SMTP) ---
    # Con MAIL_ENABLED=false no se envía correo real; en development los
    # flujos devuelven dev_token / dev_reset_link para poder probarlos.
    # MAIL_PASSWORD nunca debe imprimirse en consola ni en logs.
    MAIL_ENABLED = _env_bool("MAIL_ENABLED", "false")
    MAIL_SERVER = os.getenv("MAIL_SERVER", "")
    MAIL_PORT = int(os.getenv("MAIL_PORT", "587"))
    MAIL_USE_TLS = _env_bool("MAIL_USE_TLS", "true")
    MAIL_USE_SSL = _env_bool("MAIL_USE_SSL", "false")
    MAIL_USERNAME = os.getenv("MAIL_USERNAME", "")
    MAIL_PASSWORD = os.getenv("MAIL_PASSWORD", "")
    MAIL_DEFAULT_SENDER = os.getenv("MAIL_DEFAULT_SENDER", "")
    MAIL_FROM_NAME = os.getenv("MAIL_FROM_NAME", "Ferretería El Conejo")

    # Google OIDC (login con Google). Sin valores por defecto: se configuran
    # en .env con las credenciales creadas en Google Cloud Console.
    GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID")
    GOOGLE_CLIENT_SECRET = os.getenv("GOOGLE_CLIENT_SECRET")
    GOOGLE_REDIRECT_URI = os.getenv("GOOGLE_REDIRECT_URI")

    DB_HOST = os.getenv("DB_HOST", "localhost")
    DB_PORT = os.getenv("DB_PORT", "3306")
    DB_USER = os.getenv("DB_USER", "root")
    DB_PASSWORD = os.getenv("DB_PASSWORD", "")
    DB_NAME = os.getenv("DB_NAME", "ferreteria_conejo")

    SQLALCHEMY_DATABASE_URI = (
        f"mysql+pymysql://{DB_USER}:{quote_plus(DB_PASSWORD)}"
        f"@{DB_HOST}:{DB_PORT}/{DB_NAME}?charset=utf8mb4"
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False
