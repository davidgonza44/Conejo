from datetime import datetime

from app.extensions import db


class Product(db.Model):
    __tablename__ = "products"

    id = db.Column(db.Integer, primary_key=True)
    code = db.Column(db.String(50), unique=True, nullable=False, index=True)
    name = db.Column(db.String(150), nullable=False)
    description = db.Column(db.Text)
    category_id = db.Column(
        db.Integer, db.ForeignKey("categories.id"), nullable=False
    )
    unit = db.Column(db.String(30), nullable=False, default="unidad")
    current_stock = db.Column(db.Integer, nullable=False, default=0)
    minimum_stock = db.Column(db.Integer, nullable=False, default=0)
    purchase_price = db.Column(db.Numeric(12, 2), nullable=False, default=0)
    sale_price = db.Column(db.Numeric(12, 2), nullable=False, default=0)
    image_url = db.Column(db.String(255))
    is_active = db.Column(db.Boolean, nullable=False, default=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    updated_at = db.Column(
        db.DateTime,
        nullable=False,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
    )

    category = db.relationship("Category", back_populates="products")
    stock_movements = db.relationship("StockMovement", back_populates="product")

    @property
    def is_low_stock(self) -> bool:
        """Regla 8: bajo stock cuando current_stock <= minimum_stock."""
        return self.current_stock <= self.minimum_stock

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "code": self.code,
            "name": self.name,
            "description": self.description,
            "category_id": self.category_id,
            "category": self.category.name if self.category else None,
            "unit": self.unit,
            "current_stock": self.current_stock,
            "minimum_stock": self.minimum_stock,
            "purchase_price": float(self.purchase_price),
            "sale_price": float(self.sale_price),
            "image_url": self.image_url,
            "is_active": self.is_active,
            "is_low_stock": self.is_low_stock,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }

    def __repr__(self) -> str:
        return f"<Product {self.code} {self.name}>"
