"""Lote auditable de importación histórica desde CSV.

El archivo se conserva en almacenamiento privado. ``storage_key`` es una
clave interna (UUID) y nunca debe serializarse en respuestas HTTP.
"""
from datetime import datetime
from uuid import uuid4

from app.extensions import db

IMPORT_STATUS_UPLOADED = "uploaded"
IMPORT_STATUS_PREVIEWED = "previewed"
IMPORT_STATUS_DRY_RUN_READY = "dry_run_ready"
IMPORT_STATUS_CONFIRMED = "confirmed"
IMPORT_STATUS_REVERTED = "reverted"

HISTORICAL_IMPORT_STATUSES = (
    IMPORT_STATUS_UPLOADED,
    IMPORT_STATUS_PREVIEWED,
    IMPORT_STATUS_DRY_RUN_READY,
    IMPORT_STATUS_CONFIRMED,
    IMPORT_STATUS_REVERTED,
)


class HistoricalImport(db.Model):
    """Metadatos, estado y auditoría de un archivo histórico."""

    __tablename__ = "historical_imports"
    __table_args__ = (
        db.UniqueConstraint("public_id", name="uq_historical_imports_public_id"),
        db.UniqueConstraint("sha256", name="uq_historical_imports_sha256"),
        db.UniqueConstraint("storage_key", name="uq_historical_imports_storage_key"),
        db.Index("ix_historical_imports_status_created", "status", "created_at"),
        db.Index("ix_historical_imports_created_by", "created_by_user_id"),
        db.Index("ix_historical_imports_source_system", "source_system"),
        {"mysql_charset": "utf8mb4", "mysql_collate": "utf8mb4_unicode_ci"},
    )

    id = db.Column(db.BigInteger, primary_key=True, autoincrement=True)
    public_id = db.Column(
        db.String(36), nullable=False, default=lambda: str(uuid4())
    )

    # Nombre original: solo metadata visible para administradores.
    original_filename = db.Column(db.String(255), nullable=False)
    # Clave opaca relativa al directorio privado; nunca contiene el nombre cliente.
    storage_key = db.Column(db.String(64), nullable=False)
    file_size_bytes = db.Column(db.BigInteger, nullable=False)
    sha256 = db.Column(db.String(64), nullable=False)
    source_system = db.Column(db.String(100), nullable=False)
    # CSV v1 no trae document_type por fila; es metadata fija del lote.
    document_type = db.Column(
        db.String(50), nullable=False, default="historical_demand"
    )
    file_encoding = db.Column(db.String(20), nullable=False, default="utf-8-sig")
    delimiter = db.Column(db.String(1), nullable=False, default=";")

    schema_version = db.Column(
        db.String(32), nullable=False, default="historical-csv-v1"
    )
    mapping_version = db.Column(db.String(32), nullable=False, default="mapping-v1")
    validation_version = db.Column(
        db.String(32), nullable=False, default="validation-v1"
    )
    fingerprint_version = db.Column(
        db.String(32), nullable=False, default="fingerprint-v1"
    )
    column_mapping_json = db.Column(db.JSON, nullable=True)
    # Allowlist técnica (por ejemplo, conteo estructural); nunca contiene filas.
    metadata_json = db.Column(db.JSON, nullable=True)

    status = db.Column(
        db.String(24), nullable=False, default=IMPORT_STATUS_UPLOADED
    )
    total_rows = db.Column(db.Integer, nullable=False, default=0)
    valid_rows = db.Column(db.Integer, nullable=False, default=0)
    error_count = db.Column(db.Integer, nullable=False, default=0)
    warning_count = db.Column(db.Integer, nullable=False, default=0)
    review_count = db.Column(db.Integer, nullable=False, default=0)
    matched_count = db.Column(db.Integer, nullable=False, default=0)
    unmatched_count = db.Column(db.Integer, nullable=False, default=0)
    strong_fingerprint_count = db.Column(db.Integer, nullable=False, default=0)
    weak_fingerprint_count = db.Column(db.Integer, nullable=False, default=0)
    dry_run_summary_json = db.Column(db.JSON, nullable=True)

    # Token efímero de un solo uso: solo se persiste SHA-256.
    confirmation_token_hash = db.Column(db.String(64), nullable=True)
    confirmation_token_expires_at = db.Column(db.DateTime, nullable=True)
    confirmation_token_used_at = db.Column(db.DateTime, nullable=True)

    created_by_user_id = db.Column(
        db.Integer,
        db.ForeignKey("users.id", ondelete="RESTRICT"),
        nullable=False,
    )
    previewed_by_user_id = db.Column(
        db.Integer,
        db.ForeignKey("users.id", ondelete="RESTRICT"),
        nullable=True,
    )
    dry_run_by_user_id = db.Column(
        db.Integer,
        db.ForeignKey("users.id", ondelete="RESTRICT"),
        nullable=True,
    )
    confirmed_by_user_id = db.Column(
        db.Integer,
        db.ForeignKey("users.id", ondelete="RESTRICT"),
        nullable=True,
    )
    reverted_by_user_id = db.Column(
        db.Integer,
        db.ForeignKey("users.id", ondelete="RESTRICT"),
        nullable=True,
    )

    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    previewed_at = db.Column(db.DateTime, nullable=True)
    dry_run_at = db.Column(db.DateTime, nullable=True)
    confirmed_at = db.Column(db.DateTime, nullable=True)
    reverted_at = db.Column(db.DateTime, nullable=True)
    reversal_reason = db.Column(db.String(1000), nullable=True)
    updated_at = db.Column(
        db.DateTime,
        nullable=False,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
    )
    lock_version = db.Column(db.Integer, nullable=False, default=1)

    records = db.relationship(
        "HistoricalDemandRecord",
        back_populates="historical_import",
        foreign_keys="HistoricalDemandRecord.historical_import_id",
        passive_deletes=True,
    )
    errors = db.relationship(
        "HistoricalImportError",
        back_populates="historical_import",
        passive_deletes=True,
    )
    creator = db.relationship("User", foreign_keys=[created_by_user_id])
    previewed_by = db.relationship("User", foreign_keys=[previewed_by_user_id])
    dry_run_by = db.relationship("User", foreign_keys=[dry_run_by_user_id])
    confirmed_by = db.relationship("User", foreign_keys=[confirmed_by_user_id])
    reverted_by = db.relationship("User", foreign_keys=[reverted_by_user_id])

    def __repr__(self) -> str:
        return f"<HistoricalImport {self.public_id} status={self.status}>"
