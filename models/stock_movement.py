from datetime import datetime

from app.extensions import db

MOVEMENT_ENTRADA = "entrada"
MOVEMENT_SALIDA = "salida"
MOVEMENT_AJUSTE = "ajuste"

MOVEMENT_TYPES = (MOVEMENT_ENTRADA, MOVEMENT_SALIDA, MOVEMENT_AJUSTE)


class StockMovement(db.Model):
    __tablename__ = "stock_movements"

    id = db.Column(db.Integer, primary_key=True)
    product_id = db.Column(
        db.Integer, db.ForeignKey("products.id"), nullable=False, index=True
    )
    movement_type = db.Column(db.String(20), nullable=False, index=True)
    quantity = db.Column(db.Integer, nullable=False)
    previous_stock = db.Column(db.Integer, nullable=False)
    new_stock = db.Column(db.Integer, nullable=False)
    reason = db.Column(db.String(255))
    # Nullable mientras no exista autenticación; se guarda si está disponible.
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True)
    created_at = db.Column(
        db.DateTime, nullable=False, default=datetime.utcnow, index=True
    )

    product = db.relationship("Product", back_populates="stock_movements")
    user = db.relationship("User", back_populates="stock_movements")

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "product_id": self.product_id,
            "product": self.product.name if self.product else None,
            "movement_type": self.movement_type,
            "quantity": self.quantity,
            "previous_stock": self.previous_stock,
            "new_stock": self.new_stock,
            "reason": self.reason,
            "user_id": self.user_id,
            "user": self.user.name if self.user else None,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }

    def __repr__(self) -> str:
        return f"<StockMovement {self.movement_type} product={self.product_id}>"
