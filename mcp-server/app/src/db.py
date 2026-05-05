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
DECLARE_START_RE = re.compile(r"\A\s*declare\s+@(?P<name>[A-Za-z_][A-Za-z0-9_]*)\b", re.IGNORECASE)
DECLARE_ASSIGN_RE = re.compile(
    r"(?P<prefix>\A\s*declare\s+@(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s+"
    r"(?P<type>[A-Za-z0-9_\[\]]+(?:\s*\(\s*(?:max|\d+)(?:\s*,\s*\d+)?\s*\))?)"
    r"(?:\s*=\s*))(?P<value>[\s\S]*?)(?P<suffix>;\s*(?:--[^\r\n]*)?)\s*\Z",
    re.IGNORECASE,
)


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

    cleaned = re.sub(r"^\s*;\s*", "", cleaned)
    if ";" in cleaned.rstrip(";"):
        if re.search(r"\bdeclare\s+@", cleaned, re.IGNORECASE):
            raise ValueError(
                "run_query accepts one raw SELECT/WITH only. "
                "Use run_saved_query for canonical SQL files with DECLARE parameter blocks."
            )
        raise ValueError("Only one SQL statement is allowed.")

    cleaned = cleaned.rstrip(";").strip()
    first_word = cleaned.split(None, 1)[0].lower()
    if first_word not in {"select", "with"}:
        if first_word == "declare":
            raise ValueError(
                "run_query accepts one raw SELECT/WITH only. "
                "Use run_saved_query for canonical SQL files with DECLARE parameter blocks."
            )
        raise ValueError("Only SELECT queries are allowed.")

    if WRITE_OR_ADMIN_RE.search(cleaned):
        raise ValueError("Query contains a blocked write/admin keyword.")

    if SELECT_INTO_RE.search(cleaned):
        raise ValueError("SELECT INTO is blocked because it creates tables.")

    if UNSAFE_PROC_RE.search(cleaned):
        raise ValueError("Stored procedure calls are blocked.")

    return cleaned


def _strip_leading_comments(sql: str) -> str:
    remaining = sql.lstrip("\ufeff\r\n\t ")
    while True:
        stripped = remaining.lstrip()
        if stripped.startswith("/*"):
            end = stripped.find("*/")
            if end < 0:
                return ""
            remaining = stripped[end + 2 :]
            continue
        if stripped.startswith("--"):
            newline = stripped.find("\n")
            if newline < 0:
                return ""
            remaining = stripped[newline + 1 :]
            continue
        return stripped


def _consume_statement(sql: str) -> tuple[str, str]:
    in_string = False
    index = 0
    while index < len(sql):
        char = sql[index]
        if char == "'":
            if in_string and index + 1 < len(sql) and sql[index + 1] == "'":
                index += 2
                continue
            in_string = not in_string
        elif char == ";" and not in_string:
            line_end = sql.find("\n", index)
            if line_end < 0:
                line_end = len(sql)
            return sql[: line_end], sql[line_end:]
        index += 1
    return sql, ""


def _split_canonical_sql(sql: str) -> tuple[list[str], str]:
    remaining = _strip_leading_comments(sql)
    declarations: list[str] = []
    while DECLARE_START_RE.match(remaining):
        statement, remaining = _consume_statement(remaining)
        declarations.append(statement.strip())
        remaining = remaining.lstrip()
    return declarations, remaining.strip()


def _coerce_param_value(value: Any) -> Any:
    if value == "":
        return None
    return value


def _apply_parameter_overrides(declarations: list[str], parameters: dict[str, Any]) -> tuple[list[str], dict[str, Any]]:
    if not parameters:
        return declarations, {}

    normalized = {key.lower().lstrip("@"): value for key, value in parameters.items()}
    seen: set[str] = set()
    binds: dict[str, Any] = {}
    updated: list[str] = []

    for declaration in declarations:
        match = DECLARE_ASSIGN_RE.match(declaration)
        if not match:
            updated.append(declaration)
            continue

        name = match.group("name")
        key = name.lower()
        if key not in normalized:
            updated.append(declaration)
            continue

        bind_name = f"param_{name}"
        updated.append(f"{match.group('prefix')}:{bind_name}{match.group('suffix')}")
        binds[bind_name] = _coerce_param_value(normalized[key])
        seen.add(key)

    unknown = sorted(set(normalized) - seen)
    if unknown:
        raise ValueError(f"Unknown saved-query parameter(s): {', '.join(unknown)}")

    return updated, binds


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


def run_saved_read_only_query(
    query: str,
    *,
    query_path: str,
    parameters: dict[str, Any] | None = None,
    max_rows: int = DEFAULT_MAX_ROWS,
) -> dict[str, Any]:
    declarations, body = _split_canonical_sql(query)
    safe_body = validate_read_only_query(body)
    safe_declarations, binds = _apply_parameter_overrides(declarations, parameters or {})
    row_limit = max(1, min(max_rows, MAX_ROW_LIMIT))
    script = "\n".join([*safe_declarations, safe_body])

    with _get_engine().connect() as conn:
        conn.execute(sa.text("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED"))
        result = conn.execution_options(stream_results=True).execute(sa.text(script), binds)
        rows = result.fetchmany(row_limit + 1)
        columns = list(result.keys())

    returned_rows = rows[:row_limit]
    return {
        "query_path": query_path,
        "parameters": parameters or {},
        "columns": columns,
        "rows": [
            {column: _json_value(value) for column, value in row._mapping.items()}
            for row in returned_rows
        ],
        "row_count": len(returned_rows),
        "truncated": len(rows) > row_limit,
        "max_rows": row_limit,
    }
