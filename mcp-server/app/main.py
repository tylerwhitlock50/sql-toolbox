from __future__ import annotations

import os

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
)

mcp = FastMCP(
    "sql-toolbox",
    host=os.getenv("MCP_HOST", "0.0.0.0"),
    port=int(os.getenv("MCP_PORT", "8000")),
)


@mcp.tool()
def browse_queries() -> list[dict[str, str]]:
    """List canonical SQL files mounted from the repository's queries directory."""
    return list_saved_queries()


@mcp.tool()
def read_query(query_path: str) -> str:
    """Read a canonical SQL file by relative path from browse_queries."""
    return get_saved_query(query_path)


@mcp.tool()
def run_query(query: str, max_rows: int = 20) -> dict:
    """
    Run one read-only SELECT query against SQL Server.

    The server blocks obvious write/admin keywords and returns at most max_rows rows.
    Use a small explicit TOP clause in the SQL when exploring large tables.
    """
    return query_database(query=query, max_rows=max_rows)


@mcp.tool()
def browse_schema_docs() -> list[dict[str, str]]:
    """List curated schema docs and active-table inventories under database_scripts."""
    return list_schema_docs()


@mcp.tool()
def read_schema_doc(path: str, max_chars: int = 40000) -> dict:
    """Read a schema doc or active-table CSV by relative path from browse_schema_docs."""
    return get_schema_doc(path=path, max_chars=max_chars)


@mcp.tool()
def browse_database_objects(database: str = "veca", search: str = "") -> list[dict[str, str]]:
    """
    List table/view DDL files for veca, vfin, or lsa.

    Use search to narrow by table/view name, e.g. search="customer".
    """
    return list_database_objects(database=database, search=search)


@mcp.tool()
def read_database_object(path: str, max_chars: int = 40000) -> dict:
    """Read one table/view DDL file by relative path from browse_database_objects."""
    return get_database_object(path=path, max_chars=max_chars)


@mcp.tool()
def active_tables(database: str = "veca", max_rows: int = 500) -> dict:
    """Read the active-table inventory for veca or vfin."""
    return get_active_tables(database=database, max_rows=max_rows)


if __name__ == "__main__":
    transport = os.getenv("MCP_TRANSPORT", "streamable-http")
    print(f"Starting MCP server (transport={transport})...", flush=True)
    mcp.run(transport=transport)
    print("MCP server stopped.", flush=True)
