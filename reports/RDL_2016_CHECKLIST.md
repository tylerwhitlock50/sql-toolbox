# RDL 2016 Compliance Checklist

All 12 production reports in this directory use the **RDL 2016** schema (`http://schemas.microsoft.com/sqlserver/reporting/2016/01/reportdefinition`). The 2016 schema is stricter than 2010 — it rejects shapes the 2010 schema accepted as implicit. This file lists the six places that bite when porting a 2010 RDL forward (or hand-authoring a new report) and how to fix each. The first five are 2010 → 2016 specifically; the sixth (undeclared field references) bites independent of schema version but tends to surface in the same deployment pass.

If `open_so_list.rdl` deploys cleanly and another report doesn't, it's almost always one of these. Use `open_so_list.rdl` as your template for new reports — it has all six pieces correct.

## The six gotchas

### 1. `<Report>` element — namespaces + `MustUnderstand`

The root element must declare three namespaces and the `MustUnderstand="df"` attribute, and it must include `<rd:ReportUnitType>` and `<df:DefaultFontFamily>` inside the report:

```xml
<Report MustUnderstand="df"
        xmlns="http://schemas.microsoft.com/sqlserver/reporting/2016/01/reportdefinition"
        xmlns:rd="http://schemas.microsoft.com/SQLServer/reporting/reportdesigner"
        xmlns:df="http://schemas.microsoft.com/sqlserver/reporting/2016/01/reportdefinition/defaultfontfamily">
  <rd:ReportUnitType>Inch</rd:ReportUnitType>
  <df:DefaultFontFamily>Segoe UI</df:DefaultFontFamily>
  <AutoRefresh>0</AutoRefresh>
  ...
```

### 2. `<DataSource>` — use a shared reference, not embedded ConnectionProperties

The repo convention (matches CLAUDE.md) is to point at a shared data source published on the report server:

```xml
<DataSource Name="VECA">
  <rd:SecurityType>None</rd:SecurityType>
  <DataSourceReference>/VECA</DataSourceReference>
  <rd:DataSourceID>6f4e2c8a-9d31-4b67-8a22-1e8f7c2d3e91</rd:DataSourceID>
</DataSource>
```

Adjust the path (`/VECA`) to wherever the shared data source actually lives on your report server (e.g. `/Shared Data Sources/VECA`). Don't ship reports with embedded `<ConnectionProperties>` + `YOUR_SERVER` placeholders.

### 3. `ReportID` must use the `rd:` namespace

**Deserialization error:**
> The element 'Report' has invalid child element 'ReportID'. List of possible elements expected: 'Description, Author, AutoRefresh, …'

In RDL 2010, `<ReportID>` lived in the report-definition namespace. In RDL 2016, it moved to the designer namespace.

```xml
<!-- WRONG (2010) -->
<ReportID>a1b2c3d4-e5f6-7890-abcd-ef1234567890</ReportID>
<!-- RIGHT (2016) -->
<rd:ReportID>a1b2c3d4-e5f6-7890-abcd-ef1234567890</rd:ReportID>
```

Each report should have its own GUID.

### 4. `<Paragraph>` must contain `<TextRuns>` — no self-closing

**Deserialization error:**
> The report definition element 'Paragraph' is empty at line N. It is missing a mandatory child element of type 'TextRuns'.

This shows up on totals/footer rows where you want a visually-blank cell. The 2010 schema let you self-close `<Paragraph />`; 2016 requires the full `<TextRuns>` structure even when the value is empty:

```xml
<!-- WRONG -->
<Paragraphs><Paragraph /></Paragraphs>
<!-- RIGHT -->
<Paragraphs><Paragraph><TextRuns><TextRun><Value /></TextRun></TextRuns></Paragraph></Paragraphs>
```

### 5. `<ReportParametersLayout>` must exist and have one cell per parameter

**Run-time error (file deserializes fine, then fails when rendered):**
> The number of defined parameters is not equal to the number of cell definitions in the parameter panel.

In RDL 2010, the layout block was optional and SSRS auto-laid-out parameters. In RDL 2016, the runtime expects a layout whose cell count exactly matches the `<ReportParameter>` count.

Place the block at the **end of the file**, just before `</Report>`:

```xml
<ReportParametersLayout>
  <GridLayoutDefinition>
    <NumberOfColumns>3</NumberOfColumns>
    <NumberOfRows>1</NumberOfRows>
    <CellDefinitions>
      <CellDefinition><ColumnIndex>0</ColumnIndex><RowIndex>0</RowIndex><ParameterName>Site</ParameterName></CellDefinition>
      <CellDefinition><ColumnIndex>1</ColumnIndex><RowIndex>0</RowIndex><ParameterName>Buyer</ParameterName></CellDefinition>
      <CellDefinition><ColumnIndex>2</ColumnIndex><RowIndex>0</RowIndex><ParameterName>Horizon</ParameterName></CellDefinition>
    </CellDefinitions>
  </GridLayoutDefinition>
</ReportParametersLayout>
```

Grid sizing convention used in this repo:

| Param count | Grid | Notes |
|---|---|---|
| 1 | 1 col × 1 row | |
| 2 | 2 cols × 1 row | |
| 3 | 3 cols × 1 row | |
| 4 | 3 cols × 2 rows | last cell empty |
| 5 | 3 cols × 2 rows | last cell empty |
| 6 | 3 cols × 2 rows | full |
| 7+ | 3 cols × ⌈N/3⌉ rows | |

When you add a parameter to an existing report, you must also add a matching `<CellDefinition>` (and increment `<NumberOfRows>` / `<NumberOfColumns>` if needed). Removing a parameter requires removing its cell.

### 6. Every `Fields!X.Value` reference must have a matching `<Field>` declaration

**Run-time error:**
> The Value expression for the text box 'X' refers to the field 'Y'. Report item expressions can only refer to fields within the current dataset scope... Letters in the names of fields must use the correct case.

Not strictly a 2010 → 2016 issue — it bites whenever a column added to the SQL doesn't get a matching `<Field>` declaration in the dataset (or the case differs). But it tends to surface during the same deployment pass as the other gotchas, so it's worth scanning for.

**Fix:** add a `<Field>` for every column referenced in the layout. The `Name` is the SSRS-side handle (case-sensitive), the `<DataField>` is the column name returned by the SQL.

```xml
<Field Name="is_on_open_sales_order">
  <DataField>is_on_open_sales_order</DataField>
  <rd:TypeName>System.Int32</rd:TypeName>
</Field>
```

There's a one-shot scan for this in the compliance section below.

## Quick compliance check

Run from the repo root. The first command should hit each production `.rdl` exactly **6 times** (once per required marker). The second should return **nothing** for production files (the backup file is exempt). The third scans for any `Fields!X` reference whose field isn't declared in the dataset.

```powershell
# 1. Required-marker count per file — every production RDL should show 6
Select-String -Path "reports\*.rdl" `
  -Pattern 'MustUnderstand="df"|xmlns:df=|df:DefaultFontFamily|DataSourceReference|<rd:ReportID|<ReportParametersLayout' `
  | Group-Object Path | Sort-Object Name | Format-Table Count, Name

# 2. Anti-patterns — should be empty for production files
Select-String -Path "reports\*.rdl" `
  -Pattern '2010/01/reportdefinition|YOUR_SERVER|ConnectionProperties|<Paragraph />' `
  | Where-Object { $_.Path -notlike '*Backup*' }

# 3. Undeclared field references — should print "(end of scan)" with no preceding output
$files = Get-ChildItem reports\*.rdl | Where-Object { $_.Name -notlike '*Backup*' }
foreach ($f in $files) {
    $content   = Get-Content $f.FullName -Raw
    $refs      = [regex]::Matches($content, 'Fields!(\w+)\.') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    $declared  = [regex]::Matches($content, '<Field Name="([^"]+)"')   | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    $missing   = $refs | Where-Object { $declared -notcontains $_ }
    if ($missing) {
        Write-Output "=== $($f.Name) ==="
        $missing | ForEach-Object { Write-Output "  MISSING: $_" }
    }
}
Write-Output "(end of scan)"
```

## Adding a new report

1. Copy `open_so_list.rdl` as your starting template — it has all five pieces correct.
2. Generate a new GUID for `<rd:ReportID>` (don't reuse `b7c8d9e0-...`).
3. Replace the dataset, fields, parameters, tablix, and titles for your new report.
4. **Update `<ReportParametersLayout>`** so the cell count matches your parameter count.
5. Run the quick compliance check above before deploying.

## Updating the SQL inside an existing report

The SQL lives inside `<DataSets>/<DataSet>/<Query>/<CommandText><![CDATA[ ... ]]>`. When the canonical query in `queries/domains/...` evolves, copy the updated SQL into the matching RDL but:

- **Strip the `DECLARE @Param ...;` lines** at the top — SSRS passes parameters via `<QueryParameters>` and the `DECLARE`s will conflict.
- Keep the optional-filter pattern (`@Param IS NULL OR @Param = '' OR column = @Param`) so blank still means "all".
- If you add or remove a parameter in the SQL, update `<ReportParameter>`, `<QueryParameter>`, and `<ReportParametersLayout>` together.
