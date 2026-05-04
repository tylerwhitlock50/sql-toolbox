from __future__ import annotations

from typing import Any

from .browse import browse_queries, read_query
from .db import DEFAULT_MAX_ROWS, run_read_only_query
from .schema import (
    browse_database_objects,
    browse_schema_docs,
    read_active_tables,
    read_database_object,
    read_schema_doc,
)


def list_saved_queries() -> list[dict[str, Any]]:
    return browse_queries()


def get_saved_query(query_path: str) -> str:
    return read_query(query_path)


def query_database(query: str, max_rows: int = DEFAULT_MAX_ROWS) -> dict[str, Any]:
    return run_read_only_query(query, max_rows=max_rows)


def list_schema_docs() -> list[dict[str, str]]:
    return browse_schema_docs()


def get_schema_doc(path: str, max_chars: int = 40_000) -> dict[str, Any]:
    return read_schema_doc(path, max_chars=max_chars)


def list_database_objects(database: str = "veca", search: str = "") -> list[dict[str, str]]:
    return browse_database_objects(database=database, search=search)


def get_database_object(path: str, max_chars: int = 40_000) -> dict[str, Any]:
    return read_database_object(path, max_chars=max_chars)


def get_active_tables(database: str = "veca", max_rows: int = 500) -> dict[str, Any]:
    return read_active_tables(database=database, max_rows=max_rows)
