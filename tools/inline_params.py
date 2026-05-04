"""Strip DECLARE blocks and inline default param values in a canonical SQL file.

Usage:
    python tools/inline_params.py <path-to-sql>             # emit inlined SQL
    python tools/inline_params.py --classify <path-to-sql>  # report SINGLE | MULTI | WRITE

SINGLE  -> exactly one top-level SELECT/WITH after inlining; safe to run via MCP
MULTI   -> 2+ top-level statements; skip per user rule
WRITE   -> contains INSERT/UPDATE/DELETE/CREATE/etc; skip
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.DOTALL)
LINE_COMMENT_RE = re.compile(r"--[^\r\n]*")

DECLARE_RE = re.compile(
    r"DECLARE\s+@(?P<name>\w+)\s+"
    r"(?P<type>[A-Za-z_][\w]*(?:\s*\([^)]*\))?)"
    r"(?:\s*=\s*(?P<default>.+?))?"
    r"\s*;",
    re.IGNORECASE | re.DOTALL,
)

WRITE_KEYWORDS = re.compile(
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
    for match in DECLARE_RE.finditer(cleaned):
        name = match.group("name")
        default = (match.group("default") or "NULL").strip()
        decls[name] = default

    body = DECLARE_RE.sub(" ", cleaned)

    for name in sorted(decls, key=len, reverse=True):
        pattern = re.compile(rf"@{re.escape(name)}\b")
        body = pattern.sub(f"({decls[name]})", body)

    return body.strip()


def split_top_level_statements(sql: str) -> list[str]:
    """Split on `;` that aren't inside string literals or parens.

    Returns the list of non-empty trimmed statements.
    """
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
                # handle '' escape
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


def classify(sql: str) -> str:
    inlined = inline(sql)
    statements = split_top_level_statements(inlined)
    if not statements:
        return "EMPTY"
    if any(WRITE_KEYWORDS.search(s) for s in statements):
        return "WRITE"
    if len(statements) > 1:
        return "MULTI"
    first = statements[0].split(None, 1)[0].lower()
    if first not in {"select", "with"}:
        return "OTHER"
    return "SINGLE"


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print("usage: python tools/inline_params.py [--classify] <path>", file=sys.stderr)
        return 2

    if args[0] == "--classify":
        if len(args) != 2:
            print("usage: python tools/inline_params.py --classify <path>", file=sys.stderr)
            return 2
        sql = Path(args[1]).read_text(encoding="utf-8")
        sys.stdout.write(classify(sql))
        return 0

    if len(args) != 1:
        print("usage: python tools/inline_params.py <path>", file=sys.stderr)
        return 2
    sql = Path(args[0]).read_text(encoding="utf-8")
    sys.stdout.write(inline(sql))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
