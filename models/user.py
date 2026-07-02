from datetime import datetime

from flask_login import UserMixin
from werkzeug.security import check_password_hash, generate_password_hash

from app.extensions import db, login_manager

ROLE_ADMIN = "admin"
ROLE_INVENTARIO = "inventario"
ROLE_VENDEDOR = "vendedor"

ROLES = (ROLE_ADMIN, ROLE_INVENTARIO, ROLE_VENDEDOR)


class User(UserMixin, db.Model):
    __tablename__ = "users"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(120), nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False, index=True)
    username = db.Column(db.String(50), unique=True, nullable=False, index=True)
    # Nullable: usuarios passwordless o de Google pueden no tener contraseña.
    password_hash = db.Column(db.String(255), nullable=True)
    role = db.Column(db.String(20), nullable=False, default=ROLE_VENDEDOR)
    is_active = db.Column(db.Boolean, nullable=False, default=True)
    email_verified = db.Column(db.Boolean, nullable=False, default=False)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    updated_at = db.Column(
        db.DateTime,
        nullable=False,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
    )

    stock_movements = db.relationship("StockMovement", back_populates="user")
    delivery_notes = db.relationship(
        "DeliveryNote",
        back_populates="creator",
        foreign_keys="DeliveryNote.created_by_user_id",
    )
    identities = db.relationship(
        "AuthIdentity", back_populates="user", cascade="all, delete-orphan"
    )

    def set_password(self, password: str) -> None:
        self.password_hash = generate_password_hash(password)

    def check_password(self, password: str) -> bool:
        if not self.password_hash:
            return False
        return check_password_hash(self.password_hash, password)

    @property
    def is_admin(self) -> bool:
        return self.role == ROLE_ADMIN

    def to_dict(self) -> dict:
        """Representación pública del usuario. Nunca incluye password_hash."""
        return {
            "id": self.id,
            "name": self.name,
            "email": self.email,
            "username": self.username,
            "role": self.role,
            "is_active": self.is_active,
            "email_verified": self.email_verified,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }

    def __repr__(self) -> str:
        return f"<User {self.username}>"


@login_manager.user_loader
def load_user(user_id: str):
    return db.session.get(User, int(user_id))
