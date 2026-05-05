from __future__ import annotations

import os
from typing import Any

from mcp.server.fastmcp import FastMCP

from src.tools import (
    get_active_tables,
    get_database_object,
    get_saved_query,
    get_schema_doc,
    list_database_objects,
    list_saved_queries,
    list_schema_docs,
    query_database,
    query_saved_database,
)

mcp = FastMCP(
    "sql-toolbox",
    host=os.getenv("MCP_HOST", "0.0.0.0"),
    port=int(os.getenv("MCP_PORT", "8000")),
)

GUIDANCE_TEXT = """
SQL Toolbox workflow:

1. Start with browse_queries, then read_query. Canonical queries are the source of truth.
2. Use run_saved_query for canonical files with DECLARE parameter blocks.
3. Use run_query only for one ad hoc SELECT/WITH statement. Do not paste full canonical files into run_query.
4. If schema detail is needed, read curated schema docs with browse_schema_docs/read_schema_doc before raw DDL.
5. Browse raw database objects only after canonical queries and curated docs are not enough.

Repo-specific SQL rules:
- VECA is multi-site. Prefer SITE_ID filters on transactional tables.
- For part/customer/account/employee site overrides, prefer *_SITE_VIEW where available.
- Work-order joins need TYPE, BASE_ID, LOT_ID, SPLIT_ID, and SUB_ID.
- VFIN is entity-scoped; use ENTITY_ID business keys, not RECORD_IDENTITY, unless you already have the surrogate key.
- LSA is the Exchange/sync layer; start there for "why didn't this post?" diagnostics.
- old-queries is non-canonical triage material. Do not run or promote it without review.
""".strip()


@mcp.tool()
def sql_toolbox_guidance() -> str:
    """
    Start here. Return SQL Toolbox workflow guidance for agents using this MCP server.

    Prefer this guidance before browsing schema or running SQL.
    """
    return GUIDANCE_TEXT


@mcp.tool()
def workflow_rules() -> str:
    """
    Read this first. Alias for sql_toolbox_guidance with SQL Toolbox workflow rules.

    Use once per session before choosing query or schema tools.
    """
    return GUIDANCE_TEXT


@mcp.tool()
def browse_queries() -> list[dict[str, Any]]:
    """
    Default first step for SQL work. List canonical query files from the repo's queries directory.

    Call sql_toolbox_guidance or workflow_rules once per session for workflow rules.
    Prefer this before browsing raw schema. Results include domain, purpose, validation status,
    and whether the query is runnable through run_saved_query.
    """
    return list_saved_queries()


@mcp.tool()
def read_query(query_path: str) -> str:
    """
    Read a canonical SQL file by relative path from browse_queries.

    Call sql_toolbox_guidance or workflow_rules once per session for workflow rules.
    Use this to inspect purpose, parameters, filters, and expected output before running or adapting SQL.
    """
    return get_saved_query(query_path)


@mcp.tool()
def run_saved_query(query_path: str, parameters: dict[str, Any] | None = None, max_rows: int = 20) -> dict[str, Any]:
    """
    Run a canonical query from browse_queries/read_query with optional parameter overrides.

    Call sql_toolbox_guidance or workflow_rules once per session for workflow rules.
    Use this for repo query files that contain header comments and DECLARE parameter blocks.
    Pass parameters without @, for example {"Site": "TDJ", "Horizon": 12}; blank strings are treated as NULL.
    Known SKIP-MULTI/not-runnable files are rejected because they are notebooks, not single result queries.
    """
    return query_saved_database(query_path=query_path, parameters=parameters, max_rows=max_rows)


@mcp.tool()
def run_query(query: str, max_rows: int = 20) -> dict:
    """
    Run one ad hoc read-only SELECT/WITH query against SQL Server.

    Call sql_toolbox_guidance or workflow_rules once per session for workflow rules.
    This is for quick exploration only. For canonical queries with DECLARE/parameter
    blocks, use run_saved_query instead.
    The server blocks obvious write/admin keywords and returns at most max_rows rows.
    Use a small explicit TOP clause in the SQL when exploring large tables.
    """
    return query_database(query=query, max_rows=max_rows)


@mcp.tool()
def browse_schema_docs() -> list[dict[str, str]]:
    """
    List curated schema docs and active-table inventories under database_scripts.

    Call sql_toolbox_guidance or workflow_rules once per session for workflow rules.
    Use after checking canonical queries when schema context is needed. Prefer these docs before raw DDL.
    """
    return list_schema_docs()


@mcp.tool()
def read_schema_doc(path: str, max_chars: int = 40000) -> dict:
    """
    Read a curated schema doc or active-table CSV by relative path from browse_schema_docs.

    Call sql_toolbox_guidance or workflow_rules once per session for workflow rules.
    """
    return get_schema_doc(path=path, max_chars=max_chars)


@mcp.tool()
def browse_database_objects(database: str = "veca", search: str = "") -> list[dict[str, str]]:
    """
    List table/view DDL files for veca, vfin, or lsa.

    Call sql_toolbox_guidance or workflow_rules once per session for workflow rules.
    Use this after browse_queries and schema docs when raw DDL details are needed.
    Use search to narrow by table/view name, e.g. search="customer".
    """
    return list_database_objects(database=database, search=search)


@mcp.tool()
def read_database_object(path: str, max_chars: int = 40000) -> dict:
    """
    Read one raw table/view DDL file by relative path from browse_database_objects.

    Call sql_toolbox_guidance or workflow_rules once per session for workflow rules.
    """
    return get_database_object(path=path, max_chars=max_chars)


@mcp.tool()
def active_tables(database: str = "veca", max_rows: int = 500) -> dict:
    """
    Read the active-table inventory for veca or vfin.

    Call sql_toolbox_guidance or workflow_rules once per session for workflow rules.
    """
    return get_active_tables(database=database, max_rows=max_rows)


if __name__ == "__main__":
    transport = os.getenv("MCP_TRANSPORT", "streamable-http")
    print(f"Starting MCP server (transport={transport})...", flush=True)
    mcp.run(transport=transport)
    print("MCP server stopped.", flush=True)
