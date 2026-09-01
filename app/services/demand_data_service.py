"""Extracción y combinación de demanda histórica y operativa.

Fase de diagnóstico: no pronostica, no reabastece y no modifica inventario.

Fuentes aprobadas:
- Histórica: ``historical_demand_records`` de lotes CONFIRMADOS, vigentes,
  con ``include_in_demand`` y ``product_id`` válido.
- Operativa: renglones de notas de entrega con estado ``issued``.

No se usa ``stock_movements``: cada nota emitida ya genera una salida, y
sumar ambos duplicaría la demanda comercial. Las salidas manuales, entradas
y ajustes quedan fuera a propósito.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta
from decimal import Decimal
from typing import Iterable

from sqlalchemy.orm import load_only

from app.extensions import db
from app.models import DeliveryNote, DeliveryNoteItem, HistoricalDemandRecord, HistoricalImport
from app.models.delivery_note import STATUS_ISSUED
from app.models.historical_demand_record import (
    RECORD_STATUS_ACTIVE,
    RECORD_STATUS_ISSUED,
    RECORD_TYPE_CANCELLATION,
    RECORD_TYPE_CORRECTION,
    RECORD_TYPE_RETURN,
    RECORD_TYPE_SALE,
)
from app.models.historical_import import IMPORT_STATUS_CONFIRMED

SOURCE_HISTORICAL = "historical"
SOURCE_OPERATIONAL = "operational"
SOURCE_COMBINED = "combined"

ACTIVE_EFFECTIVE_STATUSES = (RECORD_STATUS_ISSUED, RECORD_STATUS_ACTIVE)
DEMAND_ADD_TYPES = (RECORD_TYPE_SALE, RECORD_TYPE_CORRECTION)
DEMAND_SUBTRACT_TYPES = (RECORD_TYPE_RETURN, RECORD_TYPE_CANCELLATION)

INCONSISTENCY_NEGATIVE_NET = "negative_net_demand"
INCONSISTENCY_UNLINKED_RETURN = "unlinked_return"
INCONSISTENCY_UNLINKED_CANCELLATION = "unlinked_cancellation"
INCONSISTENCY_RELATED_PRODUCT_MISMATCH = "related_product_mismatch"


def _as_decimal(value) -> Decimal:
    if isinstance(value, Decimal):
        return value
    return Decimal(str(value))


def _iso_date(value: date | None) -> str | None:
    return value.isoformat() if value else None


@dataclass(frozen=True)
class TemporalCutoff:
    """Corte derivado de lotes históricos confirmados; nunca de fechas inventadas."""

    has_confirmed_historical_import: bool
    confirmed_import_count: int
    historical_period_start: date | None
    historical_period_end: date | None
    operational_starts_on: date | None

    def to_dict(self) -> dict:
        return {
            "has_confirmed_historical_import": self.has_confirmed_historical_import,
            "confirmed_import_count": self.confirmed_import_count,
            "historical_period_start": _iso_date(self.historical_period_start),
            "historical_period_end": _iso_date(self.historical_period_end),
            "operational_starts_on": _iso_date(self.operational_starts_on),
        }


@dataclass(frozen=True)
class DemandEvent:
    product_id: int
    event_date: date
    quantity: Decimal
    signed_quantity: Decimal
    source: str
    record_type: str
    applied: bool
    inconsistency_code: str | None = None


@dataclass
class DailyPoint:
    day: date
    demand: Decimal


@dataclass
class ProductDemandSeries:
    product_id: int
    points: list[DailyPoint] = field(default_factory=list)
    original_event_count: int = 0
    data_source: str | None = None
    inconsistencies: list[dict] = field(default_factory=list)
    historical_event_count: int = 0
    operational_event_count: int = 0

    @property
    def start_date(self) -> date | None:
        return self.points[0].day if self.points else None

    @property
    def end_date(self) -> date | None:
        return self.points[-1].day if self.points else None


def get_temporal_cutoff() -> TemporalCutoff:
    """Calcula el corte con ``period_start``/``period_end`` de lotes confirmados."""
    rows = (
        db.session.query(
            HistoricalImport.period_start,
            HistoricalImport.period_end,
        )
        .filter(HistoricalImport.status == IMPORT_STATUS_CONFIRMED)
        .all()
    )
    if not rows:
        return TemporalCutoff(
            has_confirmed_historical_import=False,
            confirmed_import_count=0,
            historical_period_start=None,
            historical_period_end=None,
            operational_starts_on=None,
        )

    starts = [row.period_start for row in rows if row.period_start is not None]
    ends = [row.period_end for row in rows if row.period_end is not None]
    period_start = min(starts) if starts else None
    period_end = max(ends) if ends else None
    operational_starts_on = (
        period_end + timedelta(days=1) if period_end is not None else None
    )
    return TemporalCutoff(
        has_confirmed_historical_import=True,
        confirmed_import_count=len(rows),
        historical_period_start=period_start,
        historical_period_end=period_end,
        operational_starts_on=operational_starts_on,
    )


def load_demand_events(cutoff: TemporalCutoff | None = None) -> list[DemandEvent]:
    """Carga eventos válidos de ambas fuentes sin solapar períodos."""
    cutoff = cutoff or get_temporal_cutoff()
    events: list[DemandEvent] = []
    events.extend(_load_historical_events())
    events.extend(_load_operational_events(cutoff))
    return events


def build_daily_series_by_product(
    events: Iterable[DemandEvent] | None = None,
    cutoff: TemporalCutoff | None = None,
) -> dict[int, ProductDemandSeries]:
    """Agrega por producto y día, rellena ceros y detecta netos negativos."""
    cutoff = cutoff or get_temporal_cutoff()
    if events is None:
        events = load_demand_events(cutoff)

    grouped: dict[int, list[DemandEvent]] = {}
    for event in events:
        grouped.setdefault(event.product_id, []).append(event)
    return {
        product_id: _build_product_series(product_id, product_events)
        for product_id, product_events in grouped.items()
    }


def get_product_daily_series(
    product_id: int,
    events: Iterable[DemandEvent] | None = None,
    cutoff: TemporalCutoff | None = None,
) -> ProductDemandSeries:
    series_map = build_daily_series_by_product(events, cutoff)
    return series_map.get(product_id, ProductDemandSeries(product_id=product_id))


def _load_historical_events() -> list[DemandEvent]:
    records = (
        HistoricalDemandRecord.query.join(
            HistoricalImport,
            HistoricalDemandRecord.historical_import_id == HistoricalImport.id,
        )
        .options(
            load_only(
                HistoricalDemandRecord.id,
                HistoricalDemandRecord.product_id,
                HistoricalDemandRecord.event_date,
                HistoricalDemandRecord.quantity,
                HistoricalDemandRecord.record_type,
                HistoricalDemandRecord.related_record_id,
                HistoricalDemandRecord.include_in_demand,
                HistoricalDemandRecord.effective_status,
                HistoricalDemandRecord.historical_import_id,
            )
        )
        .filter(
            HistoricalImport.status == IMPORT_STATUS_CONFIRMED,
            HistoricalDemandRecord.include_in_demand.is_(True),
            HistoricalDemandRecord.effective_status.in_(ACTIVE_EFFECTIVE_STATUSES),
            HistoricalDemandRecord.product_id.isnot(None),
        )
        .all()
    )
    related_map = _load_related_records(records)
    events: list[DemandEvent] = []
    for record in records:
        events.append(_historical_event(record, related_map.get(record.related_record_id)))
    return events


def _load_related_records(records: list[HistoricalDemandRecord]) -> dict[int, HistoricalDemandRecord]:
    related_ids = {
        record.related_record_id
        for record in records
        if record.related_record_id is not None
    }
    if not related_ids:
        return {}
    related = (
        HistoricalDemandRecord.query.options(
            load_only(
                HistoricalDemandRecord.id,
                HistoricalDemandRecord.product_id,
                HistoricalDemandRecord.record_type,
            )
        )
        .filter(HistoricalDemandRecord.id.in_(related_ids))
        .all()
    )
    return {row.id: row for row in related}


def _historical_event(
    record: HistoricalDemandRecord,
    related: HistoricalDemandRecord | None,
) -> DemandEvent:
    quantity = _as_decimal(record.quantity)
    record_type = record.record_type
    product_id = int(record.product_id)

    if record_type in DEMAND_ADD_TYPES:
        return DemandEvent(
            product_id=product_id,
            event_date=record.event_date,
            quantity=quantity,
            signed_quantity=quantity,
            source=SOURCE_HISTORICAL,
            record_type=record_type,
            applied=True,
        )

    if record_type in DEMAND_SUBTRACT_TYPES:
        inconsistency = _return_inconsistency(record, related)
        applied = inconsistency is None
        signed = -quantity if applied else Decimal("0")
        return DemandEvent(
            product_id=product_id,
            event_date=record.event_date,
            quantity=quantity,
            signed_quantity=signed,
            source=SOURCE_HISTORICAL,
            record_type=record_type,
            applied=applied,
            inconsistency_code=inconsistency,
        )

    return DemandEvent(
        product_id=product_id,
        event_date=record.event_date,
        quantity=quantity,
        signed_quantity=Decimal("0"),
        source=SOURCE_HISTORICAL,
        record_type=record_type,
        applied=False,
        inconsistency_code=None,
    )


def _return_inconsistency(
    record: HistoricalDemandRecord,
    related: HistoricalDemandRecord | None,
) -> str | None:
    default_code = (
        INCONSISTENCY_UNLINKED_CANCELLATION
        if record.record_type == RECORD_TYPE_CANCELLATION
        else INCONSISTENCY_UNLINKED_RETURN
    )
    if record.related_record_id is None or related is None:
        return default_code
    if related.product_id != record.product_id:
        return INCONSISTENCY_RELATED_PRODUCT_MISMATCH
    if related.record_type not in DEMAND_ADD_TYPES:
        return default_code
    return None


def _load_operational_events(cutoff: TemporalCutoff) -> list[DemandEvent]:
    query = (
        db.session.query(DeliveryNoteItem, DeliveryNote)
        .join(DeliveryNote, DeliveryNoteItem.delivery_note_id == DeliveryNote.id)
        .filter(DeliveryNote.status == STATUS_ISSUED)
    )
    if cutoff.operational_starts_on is not None:
        query = query.filter(
            DeliveryNote.created_at
            >= datetime.combine(cutoff.operational_starts_on, time.min)
        )

    events: list[DemandEvent] = []
    for item, note in query.all():
        if note.created_at is None:
            continue
        quantity = _as_decimal(item.quantity)
        events.append(
            DemandEvent(
                product_id=int(item.product_id),
                event_date=note.created_at.date(),
                quantity=quantity,
                signed_quantity=quantity,
                source=SOURCE_OPERATIONAL,
                record_type=RECORD_TYPE_SALE,
                applied=True,
            )
        )
    return events


def _build_product_series(
    product_id: int, events: list[DemandEvent]
) -> ProductDemandSeries:
    daily_net: dict[date, Decimal] = {}
    inconsistencies: list[dict] = []
    applied_sources: set[str] = set()
    historical_count = 0
    operational_count = 0
    original_event_count = 0

    for event in events:
        if event.inconsistency_code:
            inconsistencies.append(
                {
                    "code": event.inconsistency_code,
                    "date": event.event_date.isoformat(),
                    "message": _inconsistency_message(event),
                }
            )
        if not event.applied:
            continue

        original_event_count += 1
        daily_net[event.event_date] = (
            daily_net.get(event.event_date, Decimal("0")) + event.signed_quantity
        )
        applied_sources.add(event.source)
        if event.source == SOURCE_HISTORICAL:
            historical_count += 1
        elif event.source == SOURCE_OPERATIONAL:
            operational_count += 1

    if not daily_net:
        return ProductDemandSeries(
            product_id=product_id,
            inconsistencies=inconsistencies,
        )

    start = min(daily_net)
    end = max(daily_net)
    points: list[DailyPoint] = []
    current = start
    while current <= end:
        demand = daily_net.get(current, Decimal("0"))
        if demand < 0:
            inconsistencies.append(
                {
                    "code": INCONSISTENCY_NEGATIVE_NET,
                    "date": current.isoformat(),
                    "message": (
                        "La demanda neta del "
                        f"{current.isoformat()} es negativa ({demand}); "
                        "no se reemplaza silenciosamente por cero."
                    ),
                }
            )
        points.append(DailyPoint(day=current, demand=demand))
        current += timedelta(days=1)

    data_source: str | None
    if SOURCE_HISTORICAL in applied_sources and SOURCE_OPERATIONAL in applied_sources:
        data_source = SOURCE_COMBINED
    elif SOURCE_HISTORICAL in applied_sources:
        data_source = SOURCE_HISTORICAL
    elif SOURCE_OPERATIONAL in applied_sources:
        data_source = SOURCE_OPERATIONAL
    else:
        data_source = None

    return ProductDemandSeries(
        product_id=product_id,
        points=points,
        original_event_count=original_event_count,
        data_source=data_source,
        inconsistencies=inconsistencies,
        historical_event_count=historical_count,
        operational_event_count=operational_count,
    )


def _inconsistency_message(event: DemandEvent) -> str:
    day = event.event_date.isoformat()
    if event.inconsistency_code == INCONSISTENCY_RELATED_PRODUCT_MISMATCH:
        return (
            f"Devolución o anulación del {day} apunta a un producto distinto; "
            "no se restó de la demanda."
        )
    if event.inconsistency_code == INCONSISTENCY_UNLINKED_CANCELLATION:
        return (
            f"Anulación del {day} sin vínculo válido a una venta; "
            "no se restó de la demanda."
        )
    return (
        f"Devolución del {day} sin vínculo válido a una venta; "
        "no se restó de la demanda."
    )
