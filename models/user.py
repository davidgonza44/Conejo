from datetime import datetime

from flask_login import UserMixin
from werkzeug.security import check_password_hash, generate_password_hash

from app.extensions import db, login_manager

ROLE_ADMIN = "admin"
ROLE_EMPLEADO = "empleado"


class User(UserMixin, db.Model):
    __tablename__ = "users"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(120), nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False, index=True)
    password_hash = db.Column(db.String(255), nullable=False)
    role = db.Column(db.String(20), nullable=False, default=ROLE_EMPLEADO)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    stock_movements = db.relationship("StockMovement", back_populates="user")
    delivery_notes = db.relationship("DeliveryNote", back_populates="creator")

    def set_password(self, password: str) -> None:
        self.password_hash = generate_password_hash(password)

    def check_password(self, password: str) -> bool:
        return check_password_hash(self.password_hash, password)

    @property
    def is_admin(self) -> bool:
        return self.role == ROLE_ADMIN

    def __repr__(self) -> str:
        return f"<User {self.email}>"


@login_manager.user_loader
def load_user(user_id: str):
    return db.session.get(User, int(user_id))
