from datetime import datetime

from app.extensions import db

STATUS_PENDIENTE = "pendiente"
STATUS_CONFIRMADA = "confirmada"
STATUS_ANULADA = "anulada"

DELIVERY_NOTE_STATUSES = (STATUS_PENDIENTE, STATUS_CONFIRMADA, STATUS_ANULADA)


class DeliveryNote(db.Model):
    __tablename__ = "delivery_notes"

    id = db.Column(db.Integer, primary_key=True)
    note_number = db.Column(db.String(30), unique=True, nullable=False, index=True)
    client_name = db.Column(db.String(150), nullable=False)
    client_phone = db.Column(db.String(30))
    created_by = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    status = db.Column(db.String(20), nullable=False, default=STATUS_PENDIENTE)
    total = db.Column(db.Numeric(12, 2), nullable=False, default=0)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    creator = db.relationship("User", back_populates="delivery_notes")
    items = db.relationship(
        "DeliveryNoteItem",
        back_populates="delivery_note",
        cascade="all, delete-orphan",
    )

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "note_number": self.note_number,
            "client_name": self.client_name,
            "client_phone": self.client_phone,
            "created_by": self.created_by,
            "status": self.status,
            "total": float(self.total),
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "items": [item.to_dict() for item in self.items],
        }

    def __repr__(self) -> str:
        return f"<DeliveryNote {self.note_number}>"


class DeliveryNoteItem(db.Model):
    __tablename__ = "delivery_note_items"

    id = db.Column(db.Integer, primary_key=True)
    delivery_note_id = db.Column(
        db.Integer, db.ForeignKey("delivery_notes.id"), nullable=False, index=True
    )
    product_id = db.Column(db.Integer, db.ForeignKey("products.id"), nullable=False)
    quantity = db.Column(db.Integer, nullable=False)
    unit_price = db.Column(db.Numeric(12, 2), nullable=False)
    subtotal = db.Column(db.Numeric(12, 2), nullable=False)

    delivery_note = db.relationship("DeliveryNote", back_populates="items")
    product = db.relationship("Product")

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "delivery_note_id": self.delivery_note_id,
            "product_id": self.product_id,
            "product": self.product.name if self.product else None,
            "quantity": self.quantity,
            "unit_price": float(self.unit_price),
            "subtotal": float(self.subtotal),
        }

    def __repr__(self) -> str:
        return f"<DeliveryNoteItem note={self.delivery_note_id} product={self.product_id}>"
