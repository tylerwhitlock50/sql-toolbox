# SQL Toolbox MCP Server

Small experimental MCP server for read-only SQL exploration against SQL Server.

## Tools

- `sql_toolbox_guidance`: explains the preferred agent workflow and SQL Toolbox conventions
- `workflow_rules`: shorter read-first alias for `sql_toolbox_guidance`
- `browse_queries`: lists canonical `.sql` files mounted from `../queries`, including purpose/status/runnability metadata
- `read_query`: reads one saved query by relative path
- `run_saved_query`: runs one canonical query file with optional parameter overrides
- `run_query`: runs one guarded ad hoc `SELECT`/`WITH` query and returns rows as JSON-like data
- `browse_schema_docs`: lists curated docs and active-table inventories under `database_scripts`
- `read_schema_doc`: reads one schema doc or active-table CSV
- `browse_database_objects`: lists table/view DDL files for `veca`, `vfin`, or `lsa`
- `read_database_object`: reads one table/view DDL file
- `active_tables`: returns parsed active-table inventory rows for `veca` or `vfin`

Recommended workflow:

1. Call `sql_toolbox_guidance` or `workflow_rules`.
2. Use `browse_queries` and `read_query` to find an existing canonical query.
3. Use `run_saved_query` for canonical files that contain `DECLARE` parameter blocks.
4. Use `run_query` only for quick one-statement exploration.
5. Use schema docs and raw DDL only when canonical queries do not answer the question.

Example prompt:

```text
Use the SQL Toolbox MCP server to run:
select top 20 * from customer
```

Example workflow for debugging a column error:

```text
Browse canonical customer/order queries first, then read VECA schema docs or CUSTOMER DDL only if the query library is not enough.
```

Example saved-query run:

```text
Use run_saved_query with query_path="domains/sales/order_information/so_header_and_lines_open_orders.sql" and parameters={"Site":"TDJ"}.
```

## Setup

Create `mcp-server/.env` from `.env.example`. Use a database login that only has read permissions.

```bash
cd mcp-server/app
python -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
python main.py
```

For Docker:

```bash
cd mcp-server
docker compose build
docker compose run --rm mcp-server
```

Example MCP client config for local stdio:

```json
{
  "mcpServers": {
    "sql-toolbox": {
      "command": "/Users/tylerwhitlock/sql-toolbox/mcp-server/app/.venv/bin/python",
      "args": ["/Users/tylerwhitlock/sql-toolbox/mcp-server/app/main.py"],
      "cwd": "/Users/tylerwhitlock/sql-toolbox/mcp-server/app"
    }
  }
}
```

## Guardrails

This is intentionally basic. `run_query` blocks non-`SELECT` statements, obvious write/admin keywords, multiple statements, `SELECT INTO`, and stored procedure calls. `run_saved_query` supports canonical leading `DECLARE` parameter blocks, but still validates that the runnable body is one read-only `SELECT`/`WITH` statement. Both tools cap returned rows to 200, defaulting to 20.

Keep using a read-only SQL Server account. The query validator is a convenience guard, not a security boundary.
