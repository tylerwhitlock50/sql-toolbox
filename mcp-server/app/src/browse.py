"""
Browse canonical queries mounted at app/src/queries (sibling of this package).

Mount the repo's `queries/` tree there so tools can list paths and read `.sql` files.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

MOUNTED_QUERIES_ROOT = Path(__file__).resolve().parent / "queries"
REPO_QUERIES_ROOT = Path(__file__).resolve().parents[3] / "queries"


def browse_queries() -> list[dict[str, Any]]:
    """
    List every `.sql` file under the mounted queries directory.

    Returns:
        Sorted list of dicts with:
        - ``path``: POSIX path relative to the queries root (e.g. ``domains/gl/trial_balance.sql``)
        - ``name``: file basename only
    """
    root = MOUNTED_QUERIES_ROOT if MOUNTED_QUERIES_ROOT.is_dir() else REPO_QUERIES_ROOT
    if not root.is_dir():
        return []

    rows: list[dict[str, Any]] = []
    for path in sorted(root.rglob("*.sql")):
        rel = path.relative_to(root).as_posix()
        rows.append({"path": rel, "name": path.name})
    return rows


def read_query(query_path: str) -> str:
    """
    Read a single query file as UTF-8 text.

    Args:
        query_path: Path relative to the queries root, e.g. ``domains/gl/trial_balance.sql``.

    Returns:
        Full file contents.

    Raises:
        ValueError: If ``query_path`` is absolute or escapes the queries directory.
        FileNotFoundError: If the path does not exist or is not a file.
    """
    query_root = MOUNTED_QUERIES_ROOT if MOUNTED_QUERIES_ROOT.is_dir() else REPO_QUERIES_ROOT
    root = query_root.resolve()
    rel = Path(query_path)
    if rel.is_absolute():
        raise ValueError("query_path must be relative to the queries directory")

    candidate = (root / rel).resolve()
    if not candidate.is_relative_to(root):
        raise ValueError("query_path escapes the queries directory")

    if not candidate.is_file():
        raise FileNotFoundError(f"query not found: {query_path}")

    return candidate.read_text(encoding="utf-8")
