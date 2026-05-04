"""End-to-end query validator. Designed to run *inside* the mcp-server container
(reuses the container's pyodbc + ODBC driver + DB env vars).

For each canonical .sql under /app/src/queries/domains/:
    * skips fix_scripts/ and `.md` siblings
    * strips DECLARE block + inlines default param values
    * splits on top-level `;` and runs only files with a single SELECT/WITH
        - MULTI / WRITE / EMPTY / OTHER are reported, not executed
    * wraps the SELECT as `SELECT TOP 1 * FROM (<query>) v` to bound the cost
    * connects via the same env vars as src/db.py
    * prints `<rel-path>\t<status>\t<message>` per file

Status values: PASS | FAIL | SKIP_MULTI | SKIP_WRITE | SKIP_EMPTY | SKIP_OTHER | SKIP_FIX_SCRIPT
"""

from __future__ import annotations

import os
import re
import sys
import time
import traceback
from pathlib import Path

import sqlalchemy as sa
from sqlalchemy.engine import URL


BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.DOTALL)
LINE_COMMENT_RE = re.compile(r"--[^\r\n]*")

DECLARE_RE = re.compile(
    r"DECLARE\s+@(?P<name>\w+)\s+"
    r"(?P<type>[A-Za-z_][\w]*(?:\s*\([^)]*\))?)"
    r"(?:\s*=\s*(?P<default>.+?))?"
    r"\s*;",
    re.IGNORECASE | re.DOTALL,
)

WRITE_RE = re.compile(
    r"\b(insert|update|delete|merge|truncate|drop|alter|create|grant|revoke|exec|execute)\b",
    re.IGNORECASE,
)


def strip_comments(sql: str) -> str:
    sql = BLOCK_COMMENT_RE.sub(" ", sql)
    sql = LINE_COMMENT_RE.sub(" ", sql)
    return sql


def inline(sql: str) -> str:
    cleaned = strip_comments(sql)
    decls: dict[str, str] = {}
    for m in DECLARE_RE.finditer(cleaned):
        decls[m.group("name")] = (m.group("default") or "NULL").strip()
    body = DECLARE_RE.sub(" ", cleaned)
    for name in sorted(decls, key=len, reverse=True):
        body = re.sub(rf"@{re.escape(name)}\b", f"({decls[name]})", body)
    return body.strip()


def split_top_level(sql: str) -> list[str]:
    out: list[str] = []
    buf: list[str] = []
    depth = 0
    in_str = False
    i = 0
    while i < len(sql):
        ch = sql[i]
        if in_str:
            buf.append(ch)
            if ch == "'":
                if i + 1 < len(sql) and sql[i + 1] == "'":
                    buf.append("'")
                    i += 2
                    continue
                in_str = False
        elif ch == "'":
            in_str = True
            buf.append(ch)
        elif ch == "(":
            depth += 1
            buf.append(ch)
        elif ch == ")":
            depth = max(0, depth - 1)
            buf.append(ch)
        elif ch == ";" and depth == 0:
            stmt = "".join(buf).strip()
            if stmt:
                out.append(stmt)
            buf = []
        else:
            buf.append(ch)
        i += 1
    tail = "".join(buf).strip()
    if tail:
        out.append(tail)
    return out


def classify(inlined: str) -> tuple[str, str]:
    statements = split_top_level(inlined)
    if not statements:
        return ("SKIP_EMPTY", "no statements after inline")
    if any(WRITE_RE.search(s) for s in statements):
        return ("SKIP_WRITE", "contains write keyword")
    if len(statements) > 1:
        return ("SKIP_MULTI", f"{len(statements)} top-level statements")
    first = statements[0].split(None, 1)[0].lower()
    if first not in {"select", "with"}:
        return ("SKIP_OTHER", f"first word: {first.upper()}")
    return ("RUN", statements[0])


def make_engine() -> sa.Engine:
    url = URL.create(
        "mssql+pyodbc",
        username=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        host=os.environ["DB_HOST"],
        port=int(os.environ["DB_PORT"]) if os.environ.get("DB_PORT") else None,
        database=os.environ["DB_NAME"],
        query={
            "driver": os.environ.get("DB_DRIVER", "ODBC Driver 18 for SQL Server"),
            "TrustServerCertificate": "yes",
        },
    )
    return sa.create_engine(url, pool_pre_ping=True)


def run_one(engine: sa.Engine, statement: str, timeout_s: int = 300) -> tuple[bool, str]:
    """Run the statement and pull 1 row. CTE-prefixed queries (`WITH ...`)
    cannot be wrapped, so we run them as-is; for plain `SELECT ...` we wrap
    in `SELECT TOP 1 * FROM (...) v` to bound the cost when possible."""
    body = statement.rstrip().rstrip(";")
    first_word = body.lstrip().split(None, 1)[0].lower()

    if first_word == "select":
        no_order = re.sub(r"\bORDER\s+BY\b[\s\S]*$", "", body, flags=re.IGNORECASE)
        to_run = f"SELECT TOP 1 * FROM (\n{no_order}\n) AS _v"
    else:
        to_run = body

    start = time.time()
    try:
        with engine.connect() as conn:
            raw = conn.connection.dbapi_connection
            try:
                raw.timeout = timeout_s
            except Exception:
                pass
            conn.execute(sa.text("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED"))
            conn.execute(sa.text(f"SET LOCK_TIMEOUT {timeout_s * 1000}"))
            result = conn.execution_options(stream_results=True).execute(sa.text(to_run))
            result.fetchmany(1)
        return (True, f"{time.time() - start:.1f}s")
    except Exception as exc:
        msg = str(exc).splitlines()[0][:240]
        return (False, msg)


def main() -> int:
    queries_root = Path("/app/src/queries/domains")
    if not queries_root.exists():
        print(f"queries root not found: {queries_root}", file=sys.stderr)
        return 2

    engine = make_engine()
    files = sorted(p for p in queries_root.rglob("*.sql"))

    only_paths = set(sys.argv[1:])  # if any args, run only those

    for sql_file in files:
        rel = sql_file.relative_to(Path("/app/src")).as_posix()  # queries/domains/...
        if only_paths and rel not in only_paths:
            continue
        if "/fix_scripts/" in rel:
            print(f"{rel}\tSKIP_FIX_SCRIPT\twrite scripts (per user rule)")
            continue

        try:
            raw = sql_file.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            raw = sql_file.read_text(encoding="utf-16")

        inlined = inline(raw)
        verdict, payload = classify(inlined)

        if verdict != "RUN":
            print(f"{rel}\t{verdict}\t{payload}")
            continue

        ok, msg = run_one(engine, payload)
        print(f"{rel}\t{'PASS' if ok else 'FAIL'}\t{msg}")
        sys.stdout.flush()

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception:
        traceback.print_exc()
        raise
