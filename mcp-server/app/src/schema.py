from __future__ import annotations

import csv
from pathlib import Path
from typing import Any

SCHEMA_ROOT = Path(__file__).resolve().parents[3] / "database_scripts"
DEFAULT_MAX_CHARS = 40_000
MAX_CHARS = 120_000


def _safe_path(relative_path: str) -> Path:
    root = SCHEMA_ROOT.resolve()
    rel = Path(relative_path)
    if rel.is_absolute():
        raise ValueError("path must be relative to database_scripts")

    candidate = (root / rel).resolve()
    if not candidate.is_relative_to(root):
        raise ValueError("path escapes database_scripts")
    if not candidate.is_file():
        raise FileNotFoundError(f"schema file not found: {relative_path}")
    return candidate


def _read_text(path: Path) -> str:
    data = path.read_bytes()
    for encoding in ("utf-8-sig", "utf-16", "utf-16-le"):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue
    return data.decode("latin-1")


def _cap_text(text: str, max_chars: int) -> dict[str, Any]:
    limit = max(1, min(max_chars, MAX_CHARS))
    return {
        "text": text[:limit],
        "truncated": len(text) > limit,
        "max_chars": limit,
        "char_count": len(text),
    }


def browse_schema_docs() -> list[dict[str, str]]:
    docs: list[dict[str, str]] = []
    for path in sorted(SCHEMA_ROOT.glob("*.md")):
        docs.append({"path": path.relative_to(SCHEMA_ROOT).as_posix(), "name": path.name, "type": "schema_doc"})
    for path in sorted(SCHEMA_ROOT.glob("active_tables*.csv")):
        docs.append({"path": path.relative_to(SCHEMA_ROOT).as_posix(), "name": path.name, "type": "active_tables"})
    return docs


def read_schema_doc(path: str, max_chars: int = DEFAULT_MAX_CHARS) -> dict[str, Any]:
    candidate = _safe_path(path)
    if candidate.suffix.lower() not in {".md", ".csv"}:
        raise ValueError("read_schema_doc only reads .md and .csv files")
    result = _cap_text(_read_text(candidate), max_chars)
    result["path"] = path
    return result


def browse_database_objects(database: str = "veca", search: str = "") -> list[dict[str, str]]:
    database_key = database.lower().strip()
    if database_key not in {"veca", "vfin", "lsa"}:
        raise ValueError("database must be one of: veca, vfin, lsa")

    root = SCHEMA_ROOT / database_key
    if not root.is_dir():
        return []

    search_key = search.lower().strip()
    rows: list[dict[str, str]] = []
    for path in sorted(root.rglob("*.sql")):
        rel = path.relative_to(SCHEMA_ROOT).as_posix()
        if search_key and search_key not in path.name.lower() and search_key not in rel.lower():
            continue
        kind = "view" if ".View." in path.name or path.parent.name == "useful_views" else "table"
        rows.append({"path": rel, "name": path.name, "database": database_key, "type": kind})
    return rows


def read_database_object(path: str, max_chars: int = DEFAULT_MAX_CHARS) -> dict[str, Any]:
    candidate = _safe_path(path)
    if candidate.suffix.lower() != ".sql":
        raise ValueError("read_database_object only reads .sql files")
    result = _cap_text(_read_text(candidate), max_chars)
    result["path"] = path
    return result


def read_active_tables(database: str = "veca", max_rows: int = 500) -> dict[str, Any]:
    database_key = database.lower().strip()
    if database_key == "veca":
        path = SCHEMA_ROOT / "active_tables.csv"
    elif database_key == "vfin":
        path = SCHEMA_ROOT / "active_tables_vfin.csv"
    else:
        raise ValueError("active table inventory exists for veca and vfin only")

    text = _read_text(path)
    reader = csv.DictReader(text.splitlines())
    limit = max(1, min(max_rows, 5000))
    rows = []
    for index, row in enumerate(reader):
        if index >= limit:
            break
        rows.append(dict(row))

    return {
        "path": path.relative_to(SCHEMA_ROOT).as_posix(),
        "database": database_key,
        "columns": reader.fieldnames or [],
        "rows": rows,
        "row_count": len(rows),
        "max_rows": limit,
    }
