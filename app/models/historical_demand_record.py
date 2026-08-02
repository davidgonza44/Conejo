"""Renglón histórico validado y auditable.

Los hechos de origen (fecha, código, cantidad y JSON allowlist) no se cambian
después de confirmar. Los campos de estado efectivo permiten superseder un
hecho sin borrarlo ni perder la trazabilidad.
"""
from datetime import datetime

from app.extensions import db

RECORD_TYPE_SALE = "sale"
RECORD_TYPE_RETURN = "return"
RECORD_TYPE_CANCELLATION = "cancellation"
RECORD_TYPE_CORRECTION = "correction"

HISTORICAL_RECORD_TYPES = (
    RECORD_TYPE_SALE,
    RECORD_TYPE_RETURN,
    RECORD_TYPE_CANCELLATION,
    RECORD_TYPE_CORRECTION,
)

RECORD_STATUS_ISSUED = "issued"
RECORD_STATUS_ACTIVE = "active"
RECORD_STATUS_CANCELLED = "cancelled"
RECORD_STATUS_VOIDED = "voided"
RECORD_STATUS_SUPERSEDED = "superseded"

HISTORICAL_RECORD_STATUSES = (
    RECORD_STATUS_ISSUED,
    RECORD_STATUS_ACTIVE,
    RECORD_STATUS_CANCELLED,
    RECORD_STATUS_VOIDED,
    RECORD_STATUS_SUPERSEDED,
)

FINGERPRINT_STRONG = "strong"
FINGERPRINT_WEAK = "weak"


class HistoricalDemandRecord(db.Model):
    """Registro staging/confirmado; jamás genera movimientos de inventario."""

    __tablename__ = "historical_demand_records"
    __table_args__ = (
        db.UniqueConstraint(
            "historical_import_id",
            "source_row_number",
            name="uq_hist_records_import_source_row",
        ),
        db.UniqueConstraint("dedupe_key", name="uq_hist_records_dedupe_key"),
        db.CheckConstraint("quantity > 0", name="ck_hist_records_quantity_positive"),
        db.CheckConstraint(
            "unit_price IS NULL OR unit_price >= 0",
            name="ck_hist_records_unit_price_nonnegative",
        ),
        db.Index("ix_hist_records_import", "historical_import_id"),
        db.Index("ix_hist_records_event_date", "event_date"),
        db.Index("ix_hist_records_product", "product_id"),
        db.Index("ix_hist_records_product_code", "product_code_normalized"),
        db.Index("ix_hist_records_document", "document_number_normalized"),
        db.Index("ix_hist_records_fingerprint", "fingerprint"),
        db.Index("ix_hist_records_match_status", "match_status"),
        db.Index(
            "ix_hist_records_demand_effective",
            "include_in_demand",
            "effective_status",
            "record_type",
        ),
        db.Index("ix_hist_records_related", "related_record_id"),
        {"mysql_charset": "utf8mb4", "mysql_collate": "utf8mb4_unicode_ci"},
    )

    id = db.Column(db.BigInteger, primary_key=True, autoincrement=True)
    historical_import_id = db.Column(
        db.BigInteger,
        db.ForeignKey("historical_imports.id", ondelete="RESTRICT"),
        nullable=False,
    )
    source_row_number = db.Column(db.Integer, nullable=False)

    source_record_id_original = db.Column(db.String(255), nullable=True)
    source_record_id_normalized = db.Column(db.String(255), nullable=True)
    source_line_id_original = db.Column(db.String(255), nullable=True)
    source_line_id_normalized = db.Column(db.String(255), nullable=True)

    document_type = db.Column(
        db.String(50), nullable=False, default="historical_demand"
    )
    document_number_original = db.Column(db.String(255), nullable=True)
    document_number_normalized = db.Column(db.String(255), nullable=True)
    event_date = db.Column(db.Date, nullable=False)

    product_code_original = db.Column(db.String(255), nullable=False)
    product_code_normalized = db.Column(db.String(255), nullable=False)
    product_name_original = db.Column(db.String(255), nullable=True)
    product_name_normalized = db.Column(db.String(255), nullable=True)
    product_id = db.Column(
        db.Integer,
        db.ForeignKey("products.id", ondelete="RESTRICT"),
        nullable=True,
    )
    suggested_product_id = db.Column(
        db.Integer,
        db.ForeignKey("products.id", ondelete="RESTRICT"),
        nullable=True,
    )

    quantity = db.Column(db.Numeric(12, 2), nullable=False)
    unit_price = db.Column(db.Numeric(12, 2), nullable=True)
    record_type = db.Column(db.String(20), nullable=False)
    # Estado declarado por la fuente; se conserva como hecho inmutable.
    record_status = db.Column(db.String(20), nullable=False)
    # Estado lógico vigente, modificable solo por una corrección auditada.
    effective_status = db.Column(db.String(20), nullable=False)

    related_source_record_id = db.Column(db.String(255), nullable=True)
    related_document_number_normalized = db.Column(db.String(255), nullable=True)
    related_record_id = db.Column(
        db.BigInteger,
        db.ForeignKey("historical_demand_records.id", ondelete="RESTRICT"),
        nullable=True,
    )
    superseded_by_record_id = db.Column(
        db.BigInteger,
        db.ForeignKey("historical_demand_records.id", ondelete="RESTRICT"),
        nullable=True,
    )
    superseded_by_import_id = db.Column(
        db.BigInteger,
        db.ForeignKey("historical_imports.id", ondelete="RESTRICT"),
        nullable=True,
    )
    superseded_at = db.Column(db.DateTime, nullable=True)

    fingerprint = db.Column(db.String(64), nullable=False)
    fingerprint_strength = db.Column(db.String(10), nullable=False)
    # Solo se rellena en confirmación fuerte; NULL permite filas débiles.
    dedupe_key = db.Column(db.String(64), nullable=True)

    match_status = db.Column(db.String(32), nullable=False, default="pending")
    match_method = db.Column(db.String(32), nullable=True)
    include_in_demand = db.Column(db.Boolean, nullable=False, default=False)

    # Allowlist de decisiones booleanas; no admite texto libre ni datos cliente.
    review_flags_json = db.Column(db.JSON, nullable=True)
    reviewed_by_user_id = db.Column(
        db.Integer,
        db.ForeignKey("users.id", ondelete="RESTRICT"),
        nullable=True,
    )
    reviewed_at = db.Column(db.DateTime, nullable=True)

    # Solo las diez columnas canónicas del CSV, nunca columnas desconocidas.
    raw_row_json = db.Column(db.JSON, nullable=False)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    updated_at = db.Column(
        db.DateTime,
        nullable=False,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
    )
    lock_version = db.Column(db.Integer, nullable=False, default=1)

    historical_import = db.relationship(
        "HistoricalImport",
        back_populates="records",
        foreign_keys=[historical_import_id],
    )
    product = db.relationship("Product", foreign_keys=[product_id])
    suggested_product = db.relationship(
        "Product", foreign_keys=[suggested_product_id]
    )
    related_record = db.relationship(
        "HistoricalDemandRecord",
        remote_side=[id],
        foreign_keys=[related_record_id],
        post_update=True,
    )
    superseded_by_record = db.relationship(
        "HistoricalDemandRecord",
        remote_side=[id],
        foreign_keys=[superseded_by_record_id],
        post_update=True,
    )
    reviewer = db.relationship("User", foreign_keys=[reviewed_by_user_id])

    def __repr__(self) -> str:
        return (
            f"<HistoricalDemandRecord import={self.historical_import_id} "
            f"row={self.source_row_number}>"
        )
