"""Configuración de la aplicación leída desde variables de entorno (.env)."""
import os
from urllib.parse import quote_plus

from dotenv import load_dotenv

load_dotenv()


class Config:
    SECRET_KEY = os.getenv("SECRET_KEY", "clave-insegura-solo-desarrollo")

    # 'development' o 'production'. En desarrollo, el token passwordless se
    # devuelve en la respuesta para pruebas; en producción, jamás.
    APP_ENV = os.getenv("APP_ENV", "development")

    # Minutos de vigencia del token passwordless.
    PASSWORDLESS_TOKEN_MINUTES = int(os.getenv("PASSWORDLESS_TOKEN_MINUTES", "15"))

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
