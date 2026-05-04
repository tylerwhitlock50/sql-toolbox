from __future__ import annotations

import base64
import datetime as dt
import decimal
import os
import re
import uuid
from typing import Any

import sqlalchemy as sa
from dotenv import load_dotenv
from sqlalchemy.engine import URL

load_dotenv()

DEFAULT_MAX_ROWS = 20
MAX_ROW_LIMIT = 200

WRITE_OR_ADMIN_RE = re.compile(
    r"\b("
    r"alter|backup|bulk|create|dbcc|delete|deny|drop|exec|execute|grant|"
    r"insert|merge|reconfigure|restore|revoke|shutdown|truncate|update|use|"
    r"waitfor"
    r")\b",
    re.IGNORECASE,
)
SELECT_INTO_RE = re.compile(r"\bselect\b[\s\S]*?\binto\b", re.IGNORECASE)
UNSAFE_PROC_RE = re.compile(r"\b(?:sp_|xp_)\w+", re.IGNORECASE)


def _required_env(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def _engine() -> sa.Engine:
    driver = os.getenv("DB_DRIVER", "ODBC Driver 18 for SQL Server")
    port = os.getenv("DB_PORT")
    url = URL.create(
        "mssql+pyodbc",
        username=_required_env("DB_USER"),
        password=_required_env("DB_PASSWORD"),
        host=_required_env("DB_HOST"),
        port=int(port) if port else None,
        database=_required_env("DB_NAME"),
        query={"driver": driver, "TrustServerCertificate": "yes"},
    )
    return sa.create_engine(url, pool_pre_ping=True)


engine: sa.Engine | None = None


def _get_engine() -> sa.Engine:
    global engine
    if engine is None:
        engine = _engine()
    return engine


def _strip_comments(sql: str) -> str:
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.DOTALL)
    return re.sub(r"--[^\r\n]*", " ", sql)


def validate_read_only_query(query: str) -> str:
    cleaned = _strip_comments(query).strip()
    if not cleaned:
        raise ValueError("Query is empty.")

    if ";" in cleaned.rstrip(";"):
        raise ValueError("Only one SQL statement is allowed.")

    cleaned = cleaned.rstrip(";").strip()
    first_word = cleaned.split(None, 1)[0].lower()
    if first_word not in {"select", "with"}:
        raise ValueError("Only SELECT queries are allowed.")

    if WRITE_OR_ADMIN_RE.search(cleaned):
        raise ValueError("Query contains a blocked write/admin keyword.")

    if SELECT_INTO_RE.search(cleaned):
        raise ValueError("SELECT INTO is blocked because it creates tables.")

    if UNSAFE_PROC_RE.search(cleaned):
        raise ValueError("Stored procedure calls are blocked.")

    return cleaned


def _json_value(value: Any) -> Any:
    if isinstance(value, (dt.date, dt.datetime, dt.time)):
        return value.isoformat()
    if isinstance(value, decimal.Decimal):
        return float(value)
    if isinstance(value, uuid.UUID):
        return str(value)
    if isinstance(value, bytes):
        return base64.b64encode(value).decode("ascii")
    return value


def run_read_only_query(query: str, max_rows: int = DEFAULT_MAX_ROWS) -> dict[str, Any]:
    safe_query = validate_read_only_query(query)
    row_limit = max(1, min(max_rows, MAX_ROW_LIMIT))

    with _get_engine().connect() as conn:
        conn.execute(sa.text("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED"))
        result = conn.execution_options(stream_results=True).execute(sa.text(safe_query))
        rows = result.fetchmany(row_limit + 1)
        columns = list(result.keys())

    returned_rows = rows[:row_limit]
    return {
        "columns": columns,
        "rows": [
            {column: _json_value(value) for column, value in row._mapping.items()}
            for row in returned_rows
        ],
        "row_count": len(returned_rows),
        "truncated": len(rows) > row_limit,
        "max_rows": row_limit,
    }
