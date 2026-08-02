"""Hallazgos seguros de validación y revisión de una importación histórica."""
from datetime import datetime

from app.extensions import db

SEVERITY_ERROR = "error"
SEVERITY_WARNING = "warning"
SEVERITY_REVIEW = "review"
HISTORICAL_ERROR_SEVERITIES = (
    SEVERITY_ERROR,
    SEVERITY_WARNING,
    SEVERITY_REVIEW,
)

RESOLUTION_UNRESOLVED = "unresolved"
RESOLUTION_RESOLVED = "resolved"
RESOLUTION_NOT_REQUIRED = "not_required"
HISTORICAL_RESOLUTION_STATUSES = (
    RESOLUTION_UNRESOLVED,
    RESOLUTION_RESOLVED,
    RESOLUTION_NOT_REQUIRED,
)


class HistoricalImportError(db.Model):
    """Error, warning o revisión; el mensaje nunca contiene la fila completa."""

    __tablename__ = "historical_import_errors"
    __table_args__ = (
        db.Index(
            "ix_hist_errors_import_severity",
            "historical_import_id",
            "severity",
            "resolution_status",
        ),
        db.Index("ix_hist_errors_record", "historical_demand_record_id"),
        db.Index(
            "ix_hist_errors_import_row",
            "historical_import_id",
            "source_row_number",
        ),
        db.Index("ix_hist_errors_code", "error_code"),
        db.Index("ix_hist_errors_resolved_by", "resolved_by_user_id"),
        {"mysql_charset": "utf8mb4", "mysql_collate": "utf8mb4_unicode_ci"},
    )

    id = db.Column(db.BigInteger, primary_key=True, autoincrement=True)
    historical_import_id = db.Column(
        db.BigInteger,
        db.ForeignKey("historical_imports.id", ondelete="RESTRICT"),
        nullable=False,
    )
    historical_demand_record_id = db.Column(
        db.BigInteger,
        db.ForeignKey("historical_demand_records.id", ondelete="RESTRICT"),
        nullable=True,
    )
    source_row_number = db.Column(db.Integer, nullable=True)
    field_name = db.Column(db.String(64), nullable=True)
    error_code = db.Column(db.String(64), nullable=False)
    severity = db.Column(db.String(16), nullable=False)
    message = db.Column(db.String(1000), nullable=False)

    resolution_status = db.Column(
        db.String(20), nullable=False, default=RESOLUTION_UNRESOLVED
    )
    # Código allowlist (p. ej. admin_manual_match); no es texto libre.
    resolution_action = db.Column(db.String(64), nullable=True)
    resolved_by_user_id = db.Column(
        db.Integer,
        db.ForeignKey("users.id", ondelete="RESTRICT"),
        nullable=True,
    )
    resolved_at = db.Column(db.DateTime, nullable=True)

    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    updated_at = db.Column(
        db.DateTime,
        nullable=False,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
    )

    historical_import = db.relationship(
        "HistoricalImport", back_populates="errors"
    )
    record = db.relationship("HistoricalDemandRecord")
    resolver = db.relationship("User", foreign_keys=[resolved_by_user_id])

    def __repr__(self) -> str:
        return (
            f"<HistoricalImportError import={self.historical_import_id} "
            f"code={self.error_code} severity={self.severity}>"
        )
