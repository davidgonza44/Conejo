"""Migración manual e idempotente del módulo de importación histórica.

Garantías:
- Solo crea historical_imports, historical_demand_records y
  historical_import_errors.
- Nunca altera ni borra tablas/datos operativos.
- Verifica columnas, índices, constraints únicos y claves foráneas.
- Captura conteos + rango de PK de todas las tablas operativas antes/después.
- Si MariaDB falla tras un DDL con autocommit, compensa únicamente tablas
  nuevas y vacías creadas por esta ejecución, en orden hijo -> padre.

Uso:
    python scripts/migrate_historical_imports.py
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import MetaData, Table, UniqueConstraint, func, inspect, select

from app import create_app
from app.extensions import db
from app.models import (
    HistoricalDemandRecord,
    HistoricalImport,
    HistoricalImportError,
)

HISTORICAL_MODELS = (
    HistoricalImport,
    HistoricalDemandRecord,
    HistoricalImportError,
)
HISTORICAL_TABLES = tuple(model.__tablename__ for model in HISTORICAL_MODELS)
MODEL_BY_TABLE = {model.__tablename__: model for model in HISTORICAL_MODELS}


def _operational_snapshot() -> dict[str, dict[str, object]]:
    """Snapshot no mutante: conteo y rango de la primera PK por tabla."""
    inspector = inspect(db.engine)
    result: dict[str, dict[str, object]] = {}
    for table_name in sorted(set(inspector.get_table_names()) - set(HISTORICAL_TABLES)):
        metadata = MetaData()
        table = Table(table_name, metadata, autoload_with=db.engine)
        pk_columns = list(table.primary_key.columns)
        statement = select(func.count()).select_from(table)
        count = int(db.session.execute(statement).scalar_one())
        snapshot: dict[str, object] = {"count": count}
        if len(pk_columns) == 1:
            pk = pk_columns[0]
            pk_min, pk_max = db.session.execute(
                select(func.min(pk), func.max(pk))
            ).one()
            snapshot["pk_column"] = pk.name
            snapshot["pk_min"] = pk_min
            snapshot["pk_max"] = pk_max
        result[table_name] = snapshot
    return result


def _actual_indexes(table_name: str) -> dict[str, tuple[tuple[str, ...], bool]]:
    inspector = inspect(db.engine)
    result: dict[str, tuple[tuple[str, ...], bool]] = {}
    for index in inspector.get_indexes(table_name):
        result[index["name"]] = (
            tuple(index.get("column_names") or ()),
            bool(index.get("unique")),
        )
    for constraint in inspector.get_unique_constraints(table_name):
        name = constraint.get("name")
        if name:
            result[name] = (
                tuple(constraint.get("column_names") or ()),
                True,
            )
    return result


def _expected_indexes(table) -> dict[str, tuple[tuple[str, ...], bool]]:
    result: dict[str, tuple[tuple[str, ...], bool]] = {}
    for index in table.indexes:
        result[index.name] = (
            tuple(column.name for column in index.columns),
            bool(index.unique),
        )
    for constraint in table.constraints:
        if isinstance(constraint, UniqueConstraint) and constraint.name:
            result[constraint.name] = (
                tuple(column.name for column in constraint.columns),
                True,
            )
    return result


def _actual_foreign_keys(
    table_name: str,
) -> set[tuple[tuple[str, ...], str, tuple[str, ...]]]:
    result = set()
    for foreign_key in inspect(db.engine).get_foreign_keys(table_name):
        result.add(
            (
                tuple(foreign_key.get("constrained_columns") or ()),
                foreign_key.get("referred_table"),
                tuple(foreign_key.get("referred_columns") or ()),
            )
        )
    return result


def _expected_foreign_keys(
    table,
) -> set[tuple[tuple[str, ...], str, tuple[str, ...]]]:
    result = set()
    for constraint in table.foreign_key_constraints:
        local = tuple(element.parent.name for element in constraint.elements)
        target_tables = {element.column.table.name for element in constraint.elements}
        if len(target_tables) != 1:
            raise RuntimeError("Se detectó una FK compuesta hacia tablas distintas.")
        target_table = next(iter(target_tables))
        remote = tuple(element.column.name for element in constraint.elements)
        result.add((local, target_table, remote))
    return result


def _column_type(table_name: str, column_name: str) -> str:
    for column in inspect(db.engine).get_columns(table_name):
        if column["name"] == column_name:
            return str(column["type"]).casefold()
    return "(missing)"


def _verify_table(model) -> bool:
    table = model.__table__
    table_name = table.name
    inspector = inspect(db.engine)
    actual_columns = {column["name"] for column in inspector.get_columns(table_name)}
    expected_columns = {column.name for column in table.columns}
    columns_ok = actual_columns == expected_columns
    print(
        f"[{'OK' if columns_ok else 'ERROR'}] {table_name}: "
        f"{len(actual_columns)}/{len(expected_columns)} columnas exactas."
    )
    if not columns_ok:
        missing = sorted(expected_columns - actual_columns)
        extra = sorted(actual_columns - expected_columns)
        print(f"  faltantes={missing}; extras={extra}")

    actual_indexes = _actual_indexes(table_name)
    indexes_ok = True
    for name, expected_signature in sorted(_expected_indexes(table).items()):
        present = actual_indexes.get(name) == expected_signature
        indexes_ok = indexes_ok and present
        print(
            f"[{'OK' if present else 'ERROR'}] índice {table_name}.{name} "
            f"{expected_signature[0]} unique={expected_signature[1]}"
        )

    actual_fks = _actual_foreign_keys(table_name)
    fks_ok = True
    for signature in sorted(_expected_foreign_keys(table)):
        present = signature in actual_fks
        fks_ok = fks_ok and present
        local_columns, target_table, target_columns = signature
        print(
            f"[{'OK' if present else 'ERROR'}] FK "
            f"{table_name}{local_columns} -> {target_table}{target_columns}"
        )
        if present:
            for local_column, target_column in zip(local_columns, target_columns):
                local_type = _column_type(table_name, local_column)
                target_type = _column_type(target_table, target_column)
                compatible = local_type == target_type
                fks_ok = fks_ok and compatible
                print(
                    f"[{'OK' if compatible else 'ERROR'}] tipos FK "
                    f"{table_name}.{local_column} ({local_type}) == "
                    f"{target_table}.{target_column} ({target_type})"
                )
    return columns_ok and indexes_ok and fks_ok


def _verify_all() -> bool:
    existing = set(inspect(db.engine).get_table_names())
    missing = set(HISTORICAL_TABLES) - existing
    if missing:
        print(f"[ERROR] Faltan tablas históricas: {sorted(missing)}")
        return False
    results = [_verify_table(model) for model in HISTORICAL_MODELS]
    return all(results)


def _compensate_new_empty_tables(created_tables: list[str]) -> None:
    """Compensa solo DDL de esta ejecución; nunca toca tablas preexistentes."""
    db.session.rollback()
    for table_name in reversed(created_tables):
        if table_name not in set(inspect(db.engine).get_table_names()):
            continue
        model = MODEL_BY_TABLE[table_name]
        count = int(
            db.session.execute(
                select(func.count()).select_from(model.__table__)
            ).scalar_one()
        )
        if count != 0:
            print(
                f"[NO COMPENSADO] {table_name} tiene {count} filas; "
                "no se elimina automáticamente."
            )
            continue
        model.__table__.drop(bind=db.engine, checkfirst=True)
        print(f"[OK] Compensación: tabla nueva y vacía {table_name} eliminada.")


def main() -> int:
    app = create_app()
    created_tables: list[str] = []
    with app.app_context():
        try:
            before = _operational_snapshot()
            print(
                f"[OK] Snapshot operativo inicial: {len(before)} tablas, "
                f"{sum(int(item['count']) for item in before.values())} filas."
            )

            existing = set(inspect(db.engine).get_table_names())
            for model in HISTORICAL_MODELS:
                table_name = model.__tablename__
                if table_name in existing:
                    print(f"[OK] {table_name} ya existe; no se modifica.")
                    continue
                model.__table__.create(bind=db.engine, checkfirst=True)
                created_tables.append(table_name)
                existing.add(table_name)
                print(f"[OK] Tabla histórica creada: {table_name}.")

            if not _verify_all():
                raise RuntimeError(
                    "La verificación del esquema histórico no fue satisfactoria."
                )

            after = _operational_snapshot()
            if before != after:
                raise RuntimeError(
                    "El snapshot operativo cambió durante la migración; "
                    "se aborta la verificación."
                )
            print("[OK] Snapshot operativo final idéntico al inicial.")
            for table_name, snapshot in before.items():
                print(
                    f"[OK] Operativa intacta {table_name}: "
                    f"count={snapshot['count']}."
                )
            print("[OK] Migración histórica completada y verificada.")
            return 0
        except Exception as exc:
            db.session.rollback()
            print(f"[ERROR] Migración histórica fallida: {exc}")
            if created_tables:
                try:
                    _compensate_new_empty_tables(created_tables)
                except Exception as compensation_error:
                    print(
                        "[ERROR] La compensación segura no pudo completarse: "
                        f"{compensation_error}"
                    )
            return 1


if __name__ == "__main__":
    raise SystemExit(main())
