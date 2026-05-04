"""Classify every canonical .sql file under queries/domains/.

Prints `<rel-path>\t<classification>` per file. Run from repo root.
"""

from __future__ import annotations

from pathlib import Path

from inline_params import classify

ROOT = Path(__file__).resolve().parent.parent
QUERIES = ROOT / "queries" / "domains"

if __name__ == "__main__":
    for sql_file in sorted(QUERIES.rglob("*.sql")):
        rel = sql_file.relative_to(ROOT).as_posix()
        if "/fix_scripts/" in rel:
            print(f"{rel}\tSKIP_FIX_SCRIPT")
            continue
        try:
            kind = classify(sql_file.read_text(encoding="utf-8"))
        except Exception as exc:  # pragma: no cover
            kind = f"ERROR:{exc}"
        print(f"{rel}\t{kind}")
