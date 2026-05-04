# SQL Toolbox MCP Server

Small experimental MCP server for read-only SQL exploration against SQL Server.

## Tools

- `browse_queries`: lists canonical `.sql` files mounted from `../queries`
- `read_query`: reads one saved query by relative path
- `run_query`: runs one guarded `SELECT` query and returns rows as JSON-like data
- `browse_schema_docs`: lists curated docs and active-table inventories under `database_scripts`
- `read_schema_doc`: reads one schema doc or active-table CSV
- `browse_database_objects`: lists table/view DDL files for `veca`, `vfin`, or `lsa`
- `read_database_object`: reads one table/view DDL file
- `active_tables`: returns parsed active-table inventory rows for `veca` or `vfin`

Example prompt:

```text
Use the SQL Toolbox MCP server to run:
select top 20 * from customer
```

Example workflow for debugging a column error:

```text
Browse VECA objects matching customer, read the CUSTOMER DDL, then fix this query's column names.
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

This is intentionally basic. The server blocks non-`SELECT` statements, obvious write/admin keywords, multiple statements, `SELECT INTO`, and stored procedure calls. It also caps returned rows to 200, defaulting to 20.

Keep using a read-only SQL Server account. The query validator is a convenience guard, not a security boundary.
