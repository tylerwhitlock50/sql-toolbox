"""
Browse canonical queries mounted at app/src/queries (sibling of this package).

Mount the repo's `queries/` tree there so tools can list paths and read `.sql` files.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

MOUNTED_QUERIES_ROOT = Path(__file__).resolve().parent / "queries"


def _repo_queries_root() -> Path:
    """
    Best-effort fallback for local, non-container execution.
    """
    current = Path(__file__).resolve()
    for parent in current.parents:
        candidate = parent / "queries"
        if candidate.is_dir():
            return candidate
    return current.parent / "queries"


def _repo_root() -> Path:
    current = Path(__file__).resolve()
    for parent in current.parents:
        if (parent / "queries").is_dir():
            return parent
    return current.parent


def _read_query_inventory() -> dict[str, dict[str, str]]:
    readme = _repo_root() / "queries" / "README.md"
    if not readme.is_file():
        return {}

    inventory: dict[str, dict[str, str]] = {}
    for line in readme.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.startswith("|") or "`" not in line:
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) < 4:
            continue
        domain, query_cell, purpose, status = cells[:4]
        start = query_cell.find("`")
        end = query_cell.find("`", start + 1)
        if start < 0 or end < 0:
            continue
        query_path = query_cell[start + 1 : end]
        inventory[query_path] = {
            "domain": domain,
            "purpose": purpose.strip("* "),
            "status": status.strip() or "-",
        }
    return inventory


def _extract_header_purpose(sql: str) -> str:
    lines = sql.splitlines()
    for index, line in enumerate(lines):
        if line.strip().lower().startswith("purpose:"):
            collected: list[str] = []
            for next_line in lines[index + 1 :]:
                stripped = next_line.strip().strip("*").strip()
                if not stripped:
                    if collected:
                        break
                    continue
                if stripped.lower().endswith(":") and collected:
                    break
                collected.append(stripped)
                if len(" ".join(collected)) > 220:
                    break
            return " ".join(collected)[:240].strip()
    return ""


def _domain_from_path(relative_path: str) -> str:
    parts = relative_path.split("/")
    if len(parts) >= 3 and parts[0] == "domains":
        return parts[1]
    return parts[0] if parts else ""


def browse_queries() -> list[dict[str, Any]]:
    """
    List every `.sql` file under the mounted queries directory.

    Returns:
        Sorted list of dicts with:
        - ``path``: POSIX path relative to the queries root (e.g. ``domains/gl/trial_balance.sql``)
        - ``name``: file basename only
    """
    root = MOUNTED_QUERIES_ROOT if MOUNTED_QUERIES_ROOT.is_dir() else _repo_queries_root()
    if not root.is_dir():
        return []

    inventory = _read_query_inventory()
    rows: list[dict[str, Any]] = []
    for path in sorted(root.rglob("*.sql")):
        rel = path.relative_to(root).as_posix()
        meta = inventory.get(rel, {})
        status = meta.get("status", "-")
        purpose = meta.get("purpose") or _extract_header_purpose(path.read_text(encoding="utf-8", errors="replace"))
        rows.append(
            {
                "path": rel,
                "name": path.name,
                "domain": meta.get("domain") or _domain_from_path(rel),
                "purpose": purpose,
                "status": status,
                "runnable": status.upper() != "SKIP-MULTI" and "fix_scripts" not in rel.lower(),
            }
        )
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
    query_root = MOUNTED_QUERIES_ROOT if MOUNTED_QUERIES_ROOT.is_dir() else _repo_queries_root()
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
