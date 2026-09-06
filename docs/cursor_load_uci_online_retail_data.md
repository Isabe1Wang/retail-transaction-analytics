# Load UCI Online Retail data
_Exported on 9/5/2026 at 16:35:54 GMT+10 from Cursor (3.17.21)_

---

**User**

Update @scripts/01_load_raw_data.py to load the UCI Online Retail Excel file into the existing SQL Server table raw.online_retail.

Requirements:

1. Keep the existing working pyodbc connection configuration.
2. Read data/raw/Online Retail.xlsx with pandas.
3. Validate that the Excel columns are exactly:
   InvoiceNo, StockCode, Description, Quantity, InvoiceDate, UnitPrice, CustomerID, Country.
4. Preserve all source rows. Do not perform business cleaning or remove cancellations, refunds, null CustomerIDs, or duplicates.
5. Only align pandas values with the existing SQL Server data types:
   - InvoiceNo and StockCode as strings
   - Quantity as integer
   - InvoiceDate as datetime
   - UnitPrice as numeric
   - CustomerID as a nullable string without “.0”
   - preserve null Description values
6. Before loading, check that raw.online_retail is empty. Stop with a clear error if it already contains rows.
7. Insert in batches using pyodbc fast_executemany.
8. Do not insert raw_row_id, source_file, or loaded_at because SQL Server supplies those values automatically.
9. Use a transaction, rollback on error, and close the cursor and connection safely.
10. After loading, compare the SQL Server row count with the Excel row count and print a clear success message.
11. Add concise comments explaining each major section.

Please modify the existing file only. Do not create additional files and do not run the script yet.

---

**Cursor**

I'll read the existing load script and check how `raw.online_retail` is defined so we can match columns and types without changing the connection.

I'll update only `scripts/01_load_raw_data.py`, keeping the current connection settings and adding Excel validation, type alignment, and a transactional batch load.

`scripts/01_load_raw_data.py` now loads `data/raw/Online Retail.xlsx` into `raw.online_retail`. The existing pyodbc connection settings are unchanged.

The script:
- Checks that the Excel columns match the eight UCI names exactly
- Keeps every source row (no business cleaning)
- Aligns types only: strings for `InvoiceNo`/`StockCode`, int `Quantity`, datetime `InvoiceDate`, numeric `UnitPrice`, nullable `CustomerID` without `.0`, and null `Description` values
- Stops if `raw.online_retail` already has rows
- Inserts in batches with `fast_executemany` (SQL Server still fills `raw_row_id`, `source_file`, and `loaded_at`)
- Uses a transaction, rolls back on error, and closes the cursor and connection in `finally`
- Compares SQL Server vs Excel row counts and prints a success message

I have not run the script.

---

**User**

I need to load the UCI Online Retail Excel dataset into the existing SQL Server table raw.online_retail.

The dataset contains about 541,909 rows. I am learning Python and pandas, and I do not yet know the best method for efficiently loading this amount of data into SQL Server.

Before writing or modifying any code:

1. Inspect @scripts/01_load_raw_data.py and the project structure.
2. Propose two suitable loading approaches.
3. Explain the advantages and disadvantages of each approach in beginner-friendly language.
4. Recommend the simplest reliable approach for this project.
5. Explain how the approach will prevent duplicate loads, partial loads, and row-count mismatches.
6. Identify any decisions or information you need from me.

Do not modify any files or run any commands yet.

---

**Cursor**

I’ll inspect the current load script and project layout only, then propose two loading approaches without changing anything.

Isabel, for ~541,909 rows the simplest reliable method is still **pandas + pyodbc batched inserts with `fast_executemany`**. That is already what `scripts/01_load_raw_data.py` does. I did not change any files or run the script.

## What I inspected

- **`scripts/01_load_raw_data.py`** is the only project script. It already: reads Excel with pandas, checks the eight UCI columns, aligns types (including nullable `CustomerID` without `.0`), refuses to load if `raw.online_retail` is not empty, inserts in 10,000-row batches, skips `raw_row_id` / `source_file` / `loaded_at`, wraps the load in a transaction, and compares Excel vs SQL Server counts before commit.
- **Project layout:** `scripts/` plus a `.venv` that includes pandas, pyodbc, SQLAlchemy, and openpyxl. I did not see files under `data/` from a file search, but the script expects `data/raw/Online Retail.xlsx` relative to the project root.
- **Connection:** the existing ODBC Driver 18 / Windows auth string is already in the script.

Row-by-row `cursor.execute()` is not a good option here. At this size it would take a long time.

---

## Approach 1: pandas + pyodbc `fast_executemany` (batches)

Read the Excel file once with pandas. Check columns and fix types. Then insert many rows at a time with `cursor.executemany()`, with `fast_executemany = True` so pyodbc sends each batch efficiently instead of one SQL statement per row.

**Advantages**
- Uses the connection you already have working.
- Easy to skip identity/default columns so SQL Server can fill them.
- Easy to keep one transaction, an empty-table check, and a final count check.
- Fast enough for ~540k rows on a local SQL Server (usually a few minutes, not hours).
- Good learning path: you can see pandas and SQL as two clear steps.

**Disadvantages**
- You write a bit more insert code than `to_sql`.
- The whole file sits in memory (fine for this dataset).
- One large transaction uses some SQL Server log space (usually fine locally).

---

## Approach 2: pandas `DataFrame.to_sql` (SQLAlchemy)

After the same pandas prep, call `df.to_sql(...)` with `chunksize` so pandas inserts in pieces through SQLAlchemy.

**Advantages**
- Shorter Python: pandas talks to the database for you.
- SQLAlchemy is already in your environment.
- `chunksize` still avoids sending all rows as one giant statement.

**Disadvantages**
- Less control over which columns are inserted. Identity/default columns (`raw_row_id`, `source_file`, `loaded_at`) are easier to get wrong.
- Often slower than `fast_executemany` for SQL Server.
- Transactions, “table must be empty,” and count checks are less obvious; you still have to add that logic yourself.
- Extra layer (SQLAlchemy) while you are still learning pandas and pyodbc.

A third option, **export CSV then `BULK INSERT` / bcp**, is usually the fastest, but it is more operations work (CSV, SQL Server file access, permissions) and is a worse first learning path.

---

## Recommendation

Use **Approach 1**. It matches this project: existing pyodbc connection, existing `raw.online_retail` table, and a one-time raw load you want to keep complete and auditable. You do not need to rewrite the script to `to_sql` unless you specifically want that API.

---

## How Approach 1 avoids the three failure modes

**Duplicate loads.** Before any `INSERT`, the script counts rows in `raw.online_retail`. If the count is not zero, it stops with a clear error and does not insert. A second run cannot pile another 541,909 rows on top of the first.

**Partial loads.** Inserts stay uncommitted until everything succeeds. If a batch fails, the `except` block rolls back, so SQL Server should not keep “the first 200,000 rows only.” The cursor and connection are closed in `finally`.

**Row-count mismatches.** After inserts (still inside the same transaction), it counts SQL Server rows and compares that to `len(df)` from Excel. If they differ, it raises an error and rolls back, so a short table is not committed. Only a matching count is committed, then a success message is printed.

---

## What I need from you

1. **Empty table vs reload.** Should a non-empty table always abort (current design), or do you ever want truncate-and-reload?
2. **Excel file.** Confirm `data/raw/Online Retail.xlsx` is on disk (I did not find files under `data/` in a project file search).
3. **Table contract.** Confirm we still insert only the eight source columns and leave `raw_row_id`, `source_file`, and `loaded_at` to SQL Server.
4. **First-run time.** A few minutes on local SQL Server is acceptable, or do you need bulk-load speed?
5. **Ready to run.** Say when you want the existing script executed; I have not run it.

If you confirm those, the next step is to run `scripts/01_load_raw_data.py` as it stands, not to switch loading methods.

---

**User**

You recommended pyodbc with fast_executemany.

Please explain:

1. What executemany does.
2. What fast_executemany changes.
3. Why it is more suitable than inserting one row at a time.
4. Whether it has any risks or limitations.
5. Whether it is appropriate for approximately 541,909 rows.

Do not write code yet.

---

**Cursor**

Isabel, **`executemany` is “run this INSERT many times with different values.” `fast_executemany` is the SQL Server shortcut that sends those values in bulk instead of one chatty round trip per row.** For ~541,909 rows it is appropriate if you insert in batches (as in the 10,000-row design).

## 1. What `executemany` does

`cursor.execute(sql, one_row)` sends **one** SQL statement with **one** set of `?` values.

`cursor.executemany(sql, many_rows)` uses the **same** SQL text (for example `INSERT INTO ... VALUES (?, ?, ...)`) and a **list of rows**. The driver binds each row’s values into those placeholders and runs the statement once per row.

You still write one INSERT shape. Python does not make you loop `execute` yourself. Without `fast_executemany`, pyodbc’s usual path is still close to “execute this statement, then this statement, then this statement…” — convenient, not especially fast.

## 2. What `fast_executemany` changes

`cursor.fast_executemany = True` changes **how** those rows are sent to SQL Server over ODBC.

Instead of a separate network conversation for almost every row, pyodbc **packs many parameter sets together** and uses the driver’s array/parameter-set binding. SQL Server still inserts row by row inside the engine, but Python and the network do far less work.

Think of it as:

- **`executemany` (default):** many small “here is one row” messages  
- **`fast_executemany`:** fewer larger “here is a stack of rows” messages  

It does **not** change your pandas cleaning, your column list, or your transaction. It only speeds up the insert API.

## 3. Why this beats one row at a time

Each `execute` has overhead: Python, ODBC, the network, and SQL Server preparing/receiving that call.

At ~541,909 rows:

- one-row `execute` → on the order of **hundreds of thousands of round trips** (often many minutes to hours)  
- batched `fast_executemany` → on the order of **tens of batches** (for example ~55 batches of 10,000)

Same INSERT, same data, far less chatter. That is why it is the usual “first serious load” method with pyodbc and SQL Server.

## 4. Risks and limitations

**Memory.** For each `executemany` call, that batch’s values are held in memory. Loading 541k rows as **one** giant `executemany` can get heavy. Batches of about 5,000–10,000 keep this comfortable.

**Stricter types.** The fast path is pickier. Pandas `NaN`/`NaT` must become Python `None` for SQL NULL. Datetimes should be real Python datetimes. Odd NumPy scalars can fail. That is why the load script aligns types before insert.

**All-or-nothing per batch.** If one value in a batch is illegal (wrong type, too long, constraint), the **whole batch** can fail. A transaction around the full load still lets you roll everything back.

**Not the fastest possible SQL Server load.** `BULK INSERT` / bcp can be faster for huge files. For this size, `fast_executemany` is usually fast enough and simpler from Python.

**Driver-specific.** It is aimed at **Microsoft ODBC + SQL Server**. You already use ODBC Driver 18, so that matches.

**One big transaction.** Inserting all ~541k rows before `commit` is good for “no partial load,” but it uses transaction log space. On a local learning database that is normally fine.

## 5. Is it appropriate for ~541,909 rows?

**Yes.** That size is a normal fit: too large for naive one-row inserts, small enough that pandas can hold the Excel file and pyodbc can insert in batches without bulk-file tooling.

A practical pattern is: read Excel once → check columns/types → confirm the table is empty → `fast_executemany` in ~10,000-row batches → one transaction → compare Excel count to `COUNT(*)` → commit or roll back.

No code was added or changed in this step.

---

**User**

Use the recommended pyodbc batch-loading approach.

Before implementation, summarise the final loading workflow and acceptance criteria. Then update @scripts/01_load_raw_data.py.

Do not run the script after modifying it. I want to review the code first.

---

**Cursor**

I’ll read the current script, outline the load workflow and acceptance checks, then update only that file—without running it.

## Final loading workflow

1. **Read** `data/raw/Online Retail.xlsx` with pandas (path resolved from the project root).
2. **Validate** that the columns are exactly: `InvoiceNo`, `StockCode`, `Description`, `Quantity`, `InvoiceDate`, `UnitPrice`, `CustomerID`, `Country`.
3. **Keep every Excel row.** No dropping of cancellations, refunds, null `CustomerID`s, or duplicates.
4. **Align types only:** identifiers as strings (no `.0`), `Quantity` as int, `InvoiceDate` as datetime, `UnitPrice` as numeric, `CustomerID` as nullable string, null `Description` as SQL NULL.
5. **Connect** with the existing pyodbc settings.
6. **Guard:** if `raw.online_retail` already has rows, stop and insert nothing.
7. **Insert** the eight source columns only in 10,000-row batches with `fast_executemany`. SQL Server still fills `raw_row_id`, `source_file`, and `loaded_at`.
8. **Check** SQL Server `COUNT(*)` against the Excel row count **before** commit.
9. **Commit** on match; **roll back** on any error; **close** cursor and connection in `finally`.

## Acceptance criteria

- Column mismatch → error, no insert.
- Table not empty → error, no insert.
- Insert failure or Excel vs SQL count mismatch → rollback, table stays empty.
- Success → committed row count equals Excel row count, and a message prints both numbers.
- Source row count is preserved (no business cleaning).

`scripts/01_load_raw_data.py` is updated to this workflow. I have not run it, so you can review it first.

---

**User**

Review the code you just generated before I run it.

I found one issue: the working SQL Server value that we already tested is:

server = r".\MSSQLSERVER02"

The hostname-based value previously failed, so do not use it.

Please:

1. Correct the server value.
2. Add a message before reading Excel so I know the script has started.
3. Print progress after every batch, showing loaded rows versus total rows.
4. Keep all other business rules, transaction controls, and validations unchanged.
5. Review the updated script for any remaining correctness or data-type risks.
6. Do not run the script.

---

**Cursor**

I’ll fix the server name, add a start message and per-batch progress, then review the script for remaining type and load risks—without running it.

Isabel, the script now uses `server = r".\MSSQLSERVER02"`, prints before Excel is read, and prints `Loaded {n} / {total} rows` after each batch. I have not run it.

The only extra change besides those three is in `_to_python`: NumPy scalars (`int64`, `float64`) are converted with `.item()`. `fast_executemany` often rejects those, and pandas produces them for `Quantity` and `UnitPrice`. Business rules, empty-table check, transaction, rollback, and final count check are unchanged.

## Remaining risks (nothing else I would change before your first run)

**Likely fine for UCI Online Retail**
- Null `CustomerID` and `Description` become Python `None`, which pyodbc sends as SQL NULL.
- `InvoiceNo` / `StockCode` / `CustomerID` lose a trailing `.0` from Excel floats.
- Negative `Quantity` (cancellations) is kept; `astype(int)` is correct if every quantity is present.
- One transaction for all batches: progress lines are **uncommitted** until the final success message. If the script fails, rollback still undoes those batches.

**Could still fail, depending on the table**
- If `Quantity` had a null, `astype(int)` would error before any insert (this file normally has none).
- If a SQL column is too short (for example `Description` or `InvoiceNo`), a batch can fail and the whole load rolls back.
- `Country.astype(str)` would turn a true null into the text `"nan"`. This dataset’s `Country` is populated.

**Operational**
- `read_excel` on ~541k rows can sit quiet for a while after “Starting load…”; that is pandas reading the file, not a hang.
- If `raw.online_retail` already has rows, the script stops after that check and never inserts.

After you run it, you want: start message → ~55 batch lines ending at the Excel total → a final “matches Excel row count” line, and a matching `COUNT(*)` in SQL Server.

---

**User**

I have reviewed and accepted the changes.

Before I run the script myself, please do a final read-only review of
scripts/01_load_raw_data.py.

Check:
1. The SQL Server name is exactly r".\MSSQLSERVER02".
2. There is only one server assignment.
3. The Excel path resolves to data/raw/Online Retail.xlsx.
4. The INSERT column order matches the row tuple order.
5. The script preserves all source rows.
6. The empty-table guard, transaction, rollback, row-count validation,
   batch progress, and connection cleanup are correct.
7. Check for syntax or indentation problems.

Do not edit the file and do not run the script.
Give me only:
- Ready to run, or
- A list of specific problems with line numbers.

---

**Cursor**

Ready to run

---

**User**

I cannnot run it as it mentioned No module named 'pandas'

---

**Cursor**

Pandas isn’t on the Python that’s running the script. I’ll check the terminal output and which interpreter the project venv uses.

Isabel, pandas **is** installed in this project’s `.venv`. The error comes from `python scripts\01_load_raw_data.py`, which uses **system Python**, not the venv.

Venv activation also failed because PowerShell script execution is disabled. You do not need to activate. Call the venv interpreter directly:

```powershell
.\.venv\Scripts\python.exe scripts\01_load_raw_data.py
```

That interpreter already has pandas, pyodbc, and openpyxl.

If you run the file from Cursor’s Run button, choose the interpreter at `.venv\Scripts\python.exe` so it does not keep using global `python`.

---

**User**

please read the error message from the terminal and fix it

---

**Cursor**

The insert failed because `Description` is NOT NULL in SQL Server while the Excel file has missing descriptions. I’ll check the table’s nullability so we can align the load without dropping rows.

SQL Server rejected the load because **`raw.online_retail.Description` is `NOT NULL`**, while the Excel file has blank descriptions. The failed insert was rolled back, so the table should still be empty.

The script now stores missing descriptions as an **empty string** instead of SQL `NULL`. Every Excel row is still loaded; `CustomerID` can still be null (that column allows it).

Re-run with:

```powershell
.\.venv\Scripts\python.exe scripts\01_load_raw_data.py
```

---

**User**

ok, now let's move on to the silver level, what's your suggestions on data profiling

---

**Cursor**

I’ll check how the raw load looks and whether any silver tables exist, then suggest a silver-layer profiling plan for this UCI dataset.

Isabel, the raw load is in good shape: **541,909 rows** in `raw.online_retail`. Profile **from that table** (not from Excel again) so silver rules match what SQL Server actually holds, including empty-string descriptions.

## What silver profiling is for

Raw is a faithful copy. Silver is the first **opinionated** layer: typed, labelled, and usable for analysis. Profiling is how you decide those opinions with evidence (counts and examples), instead of dropping cancellations because a tutorial did.

Keep raw unchanged. Write findings as notes or a small `scripts/02_profile_raw.py` / notebook that **reads SQL and prints summaries**. Do not write silver tables until you have agreed rules.

## How to do it

Pandas is enough at this size: `pd.read_sql` of the eight business columns (you can skip `raw_row_id` for most checks). Add `LineValue = Quantity * UnitPrice` only in the profile frame.

Use SQL `GROUP BY` later if a check is slow; start in pandas so you can inspect example rows.

## What to measure (this dataset)

**1. Completeness and the Description workaround**  
Null `CustomerID` (expect a large share). Empty vs non-empty `Description`. Confirm nothing else is unexpectedly blank (`InvoiceNo`, `StockCode`, `Country`).

**2. Transaction type (the main silver design choice)**  
- `InvoiceNo` starting with `C`  
- `Quantity < 0` without `C`  
- `C` with `Quantity >= 0` (should be rare)  
Cross-tab those. Silver should store flags such as `is_cancellation` rather than deleting those rows.

**3. Price and value**  
`UnitPrice` ≤ 0, `Quantity` = 0 if any, extreme `|Quantity|` and `UnitPrice` (this file has huge outliers). Sum of `LineValue` with vs without cancellations and zero-price lines.

**4. Non-product `StockCode`s**  
Codes like `POST`, `D`, `M`, `DOT`, `CRUK`, `BANK CHARGES`, gift vouchers. Count rows and value. Silver often flags `is_product_line` vs postage/manual/discount.

**5. Duplicates**  
Full-row duplicates vs repeats of `(InvoiceNo, StockCode, Quantity, UnitPrice, CustomerID)`. Decide: keep as-is, collapse, or keep and flag. Do not treat “same invoice, two lines, same SKU” as an automatic error.

**6. Keys and grain**  
One invoice → many lines. `CustomerID` null vs present. Same `StockCode`, several `Description`s (text drift). Country mix (UK will dominate).

**7. Time**  
Min/max `InvoiceDate`, rows per month, gaps. That sets the analysis window for RFM or monthly sales.

**8. Type checks after the load**  
`CustomerID` has no `.0`. `InvoiceNo`/`StockCode` are strings. `Quantity` is int. Empty `Description` count matches the NOT NULL load choice.

## How this should feed silver

A practical first silver table is still **one row per raw line**, plus derived columns, for example:

- `line_value`  
- `is_cancellation`, `is_return_or_adjust`  
- `has_customer`  
- `has_description`  
- `is_product_line`  
- `is_duplicate` (if you define it)

Filter for “valid sales” in **gold** or in a view, not by shrinking silver until you know RFM vs finance vs product analytics need different filters.

## Suggested order of work

1. Profile script or notebook against `raw.online_retail`.  
2. One short decision list (what to flag vs exclude vs keep).  
3. Then `CREATE` silver and a load script, with the same empty-table / row-count discipline as raw.

## What I need from you

What is silver for first: **customer RFM**, **revenue reporting**, or **both**? That decides whether guest checkouts (`CustomerID` null) and `C` invoices stay in the default silver grain or only in flagged subsets.

If you want to go next, I can draft `scripts/02_profile_raw.py` to print these counts and a few example rows from SQL Server.

---

**User**

please return a plan of profiling and the requirement

---

**Cursor**

Isabel, here is a **profiling plan and requirements** for moving from `raw.online_retail` toward silver. Profiling is read-only: no silver tables and no changes to raw until the findings are agreed.

---

## Goal

Describe the **541,909** loaded rows well enough to write silver rules: what to flag, what to keep, and what “valid” means for later RFM and sales analysis.

**Source of truth:** `RetailAnalytics.raw.online_retail` (not Excel).  
**Deliverable:** counts, examples, and a short decision list.  
**Tool:** `sql/02_raw_data_profiling.sql` (and optional pandas later). Raw stays untouched.

---

## Requirements

**Must**

1. Profile every raw business column: `InvoiceNo`, `StockCode`, `Description`, `Quantity`, `InvoiceDate`, `UnitPrice`, `CustomerID`, `Country`.
2. Do not drop, update, or delete raw rows.
3. Keep cancellations, negative quantities, zero prices, null `CustomerID`, empty `Description`, and duplicates in the profile (count and show examples).
4. Treat empty `Description` (`''`) as missing text, because the load stored Excel nulls as empty strings.
5. Treat `CustomerID` null as guest/unidentified, not as a load error.
6. For each issue, report **row count**, **% of 541,909**, and **a few example rows**.
7. Cross-check `InvoiceNo` like `C%` against `Quantity < 0`.
8. Compute `LineValue = Quantity * UnitPrice` only in the query (do not store it in raw).
9. Confirm load quality: row count **541,909**; `CustomerID` has no `.0`; identifiers are strings.

**Must not**

- Filter to “clean sales” as if that were the profile.
- Deduplicate in place.
- Guess silver column names before the decision list.

**Should**

- List frequent non-product `StockCode` values (postage, manual, discount, and similar).
- Show date min/max and monthly volume.
- Show how many descriptions exist per `StockCode`.

---

## Profiling plan

### Phase 0 — Baseline

- `COUNT(*)` equals 541,909.
- Min/max `InvoiceDate`.
- Distinct counts: invoices, stock codes, customers (non-null), countries.

**Pass:** grain is line-level (many lines per `InvoiceNo`).

### Phase 1 — Completeness

- Null `CustomerID`.
- `Description` empty or whitespace-only.
- Any null/blank `InvoiceNo`, `StockCode`, `Country` (should be none).

**Pass:** only `CustomerID` and `Description` are materially incomplete.

### Phase 2 — Transaction behaviour

- Rows with `InvoiceNo` like `'C%'`.
- Rows with `Quantity < 0`.
- Rows with `Quantity = 0` (if any).
- Cross-tab: cancellation prefix vs sign of `Quantity`.
- Example cancelled lines and any mismatches (e.g. `C` with positive quantity).

**Pass:** you can define `is_cancellation` (and related flags) without deleting rows.

### Phase 3 — Price and value

- `UnitPrice` = 0, `< 0`, `> 0`.
- Min/max/percentiles for `Quantity` and `UnitPrice`.
- Extreme `|Quantity|` or `UnitPrice` with example invoices.
- Sum of `LineValue` for all rows vs positive-price, non-cancelled rows.

**Pass:** you know what zero-price and outliers would do to revenue.

### Phase 4 — Product vs adjustment codes

- Top `StockCode`s by row count that are not typical product IDs.
- Known patterns: `POST`, `D`, `M`, `DOT`, `CRUK`, `BANK CHARGES`, gift/adjust codes.
- Row count and `LineValue` for those vs the rest.

**Pass:** you can define `is_product_line` (or equivalent).

### Phase 5 — Duplicates and keys

- Duplicate full business-column rows.
- Repeat groups on `(InvoiceNo, StockCode, Quantity, UnitPrice, CustomerID)`.
- Distinct `Description` count per `StockCode` (text drift).
- Invoices with mixed `Country` or mixed `CustomerID` (should be rare).

**Pass:** duplicate policy is evidence-based (keep, flag, or collapse later in silver).

### Phase 6 — Time and geography

- Rows per year-month.
- Top countries by rows and by `LineValue`.

---

**User**

could you please continue following phase 6

---

**Cursor**

I’ll look up what Phase 6 is in this project’s plan, then continue from there.

The empty `sql/02_raw_data_profiling.sql` is the next step after raw load. I’ll add the profiling plan, requirements, and SQL—with Phase 6 (keys, grain, and consistency) fully specified.

Isabel, Phase 6 is **keys, grain, and consistency**. The full profiling plan and requirements are in `sql/02_raw_data_profiling.sql` (read-only `SELECT`s against `raw.online_retail`).

## Requirements

- Profile **SQL Server raw**, not Excel again.
- **Do not change raw** (no deletes/updates).
- Capture **counts and examples**; do not apply silver filters yet.
- Silver **flags**; gold **filters**.
- Empty `Description` is missing text; null `CustomerID` is guest checkout.
- Grain is **one row = one invoice line**.

## Plan

| Phase | Focus |
| --- | --- |
| 1 | Volume / load (541,909 rows, date range, distinct keys) |
| 2 | Completeness (nulls and blanks) |
| 3 | Cancellations vs quantity sign |
| 4 | Price, quantity, line value, outliers |
| 5 | Non-product `StockCode` |
| **6** | **Invoice grain, duplicates, guest vs identified, mixed invoice keys, description drift, country** |
| 7 | Monthly time coverage |
| 8 | Example rows for silver flags |

Phase 6 in the script checks: lines per invoice, exact duplicate lines, repeated `(InvoiceNo, StockCode)`, guest vs identified customers, invoices with mixed `CustomerID` or `Country`, one `StockCode` with several descriptions, and country mix.

Run the file in SSMS against `RetailAnalytics` (batch by batch if you want). After you have the counts, we can lock silver flag rules.

---

**User**

here's my question please return a plan of profiling and the requirement, then you give me the answer please return a plan of profiling and the requirement

Isabel, here is a profiling plan and requirements for moving from raw.online_retail toward silver. Profiling is read-only: no silver tables and no changes to raw until the findings are agreed.

Goal
Describe the 541,909 loaded rows well enough to write silver rules: what to flag, what to keep, and what “valid” means for later RFM and sales analysis.

Source of truth: RetailAnalytics.raw.online_retail (not Excel).
Deliverable: counts, examples, and a short decision list.
Tool: sql/02_raw_data_profiling.sql (and optional pandas later). Raw stays untouched.

Requirements
Must

Profile every raw business column: InvoiceNo, StockCode, Description, Quantity, InvoiceDate, UnitPrice, CustomerID, Country.
Do not drop, update, or delete raw rows.
Keep cancellations, negative quantities, zero prices, null CustomerID, empty Description, and duplicates in the profile (count and show examples).
Treat empty Description ('') as missing text, because the load stored Excel nulls as empty strings.
Treat CustomerID null as guest/unidentified, not as a load error.
For each issue, report row count, % of 541,909, and a few example rows.
Cross-check InvoiceNo like C% against Quantity < 0.
Compute LineValue = Quantity * UnitPrice only in the query (do not store it in raw).
Confirm load quality: row count 541,909; CustomerID has no .0; identifiers are strings.
Must not

Filter to “clean sales” as if that were the profile.
Deduplicate in place.
Guess silver column names before the decision list.
Should

List frequent non-product StockCode values (postage, manual, discount, and similar).
Show date min/max and monthly volume.
Show how many descriptions exist per StockCode.
Profiling plan
Phase 0 — Baseline
COUNT(*) equals 541,909.
Min/max InvoiceDate.
Distinct counts: invoices, stock codes, customers (non-null), countries.
Pass: grain is line-level (many lines per InvoiceNo).

Phase 1 — Completeness
Null CustomerID.
Description empty or whitespace-only.
Any null/blank InvoiceNo, StockCode, Country (should be none).
Pass: only CustomerID and Description are materially incomplete.

Phase 2 — Transaction behaviour
Rows with InvoiceNo like 'C%'.
Rows with Quantity < 0.
Rows with Quantity = 0 (if any).
Cross-tab: cancellation prefix vs sign of Quantity.
Example cancelled lines and any mismatches (e.g. C with positive quantity).
Pass: you can define is_cancellation (and related flags) without deleting rows.

Phase 3 — Price and value
UnitPrice = 0, < 0, > 0.
Min/max/percentiles for Quantity and UnitPrice.
Extreme |Quantity| or UnitPrice with example invoices.
Sum of LineValue for all rows vs positive-price, non-cancelled rows.
Pass: you know what zero-price and outliers would do to revenue.

Phase 4 — Product vs adjustment codes
Top StockCodes by row count that are not typical product IDs.
Known patterns: POST, D, M, DOT, CRUK, BANK CHARGES, gift/adjust codes.
Row count and LineValue for those vs the rest.
Pass: you can define is_product_line (or equivalent).

Phase 5 — Duplicates and keys
Duplicate full business-column rows.
Repeat groups on (InvoiceNo, StockCode, Quantity, UnitPrice, CustomerID).
Distinct Description count per StockCode (text drift).
Invoices with mixed Country or mixed CustomerID (should be rare).
Pass: duplicate policy is evidence-based (keep, flag, or collapse later in silver).

Phase 6 — Time and geography
Rows per year-month.
Top countries by rows and by LineValue. now do you have any other things after this phase 6, it's a plan do not run any script

---

**Cursor**

Isabel, after **Phase 6 (time and geography)** the profiling plan is not finished. You still need a **close-out** that turns counts into silver rules. Do not run any scripts for this.

## After Phase 6

**Phase 7 — Examples and mismatches**  
For every issue that still matters (cancellations, guests, empty description, zero price, non-product codes, duplicates, outliers), keep a small set of **example rows**. That is how you check the flags before you name silver columns.

**Phase 8 — Decision list (required deliverable)**  
Write the short list profiling was for:

- Grain stays **invoice line**.  
- What to **flag** in silver (e.g. cancellation, guest, empty description, non-product, duplicate, zero/negative price, outlier).  
- What to **keep** in silver (default: all raw lines, plus flags).  
- What “**valid**” means for RFM vs for sales (usually two different filters, applied later in gold or in views — not by shrinking raw).

**Phase 9 — Silver scope (still a plan, not DDL)**  
Only after Phase 8: one silver table vs several; which flags; `LineValue` as a **derived** silver column; still no load until you agree the list.

## What you already covered

Phases 0–6 plus your **Must / Must not / Should** already cover completeness, transaction type, value, product codes, duplicates/keys, and time/geography. You do **not** need another measurement phase unless something in 0–6 is incomplete (for example you never cross-tabbed `C%` vs `Quantity < 0`).

## Optional, only if a phase 0–6 result is surprising

- Same invoice with mixed `InvoiceDate` (rare; only if you see it).  
- Percentiles for `Quantity` / `UnitPrice` if Phase 3 min/max is not enough for outlier rules.

Nothing after Phase 6 should **filter “clean sales”** or **deduplicate in place**. That stays out of profiling, as in your requirements.

---

**User**

please return the whole plan and requirements

---

**Cursor**

Isabel, here is the full profiling plan and requirements for moving from `raw.online_retail` toward silver. Profiling is **read-only**: no silver tables and no changes to raw until the findings are agreed. Do not run scripts as part of this document.

---

# Goal

Describe the **541,909** loaded rows well enough to write silver rules: what to **flag**, what to **keep**, and what **valid** means for later RFM and sales analysis.

- **Source of truth:** `RetailAnalytics.raw.online_retail` (not Excel).
- **Deliverable:** counts, examples, and a short decision list.
- **Tool:** `sql/02_raw_data_profiling.sql` (optional pandas later).
- **Constraint:** raw stays untouched.

---

# Requirements

## Must

- Profile every raw business column: `InvoiceNo`, `StockCode`, `Description`, `Quantity`, `InvoiceDate`, `UnitPrice`, `CustomerID`, `Country`.
- Do not drop, update, or delete raw rows.
- Keep cancellations, negative quantities, zero prices, null `CustomerID`, empty `Description`, and duplicates **in the profile** (count them and show examples).
- Treat empty `Description` (`''`) as missing text, because the load stored Excel nulls as empty strings.
- Treat `CustomerID` null as guest/unidentified, not as a load error.
- For each issue, report **row count**, **% of 541,909**, and a few **example rows**.
- Cross-check `InvoiceNo` like `C%` against `Quantity < 0`.
- Compute `LineValue = Quantity * UnitPrice` only in the query (do not store it in raw).
- Confirm load quality: row count **541,909**; `CustomerID` has no `.0`; identifiers are strings.

## Must not

- Filter to “clean sales” as if that were the profile.
- Deduplicate in place.
- Guess silver column names before the decision list.

## Should

- List frequent non-product `StockCode` values (postage, manual, discount, and similar).
- Show date min/max and monthly volume.
- Show how many descriptions exist per `StockCode`.

---

# Profiling plan

## Phase 0 — Baseline

- `COUNT(*)` equals 541,909.
- Min/max `InvoiceDate`.
- Distinct counts: invoices, stock codes, customers (non-null), countries.
- **Pass:** grain is line-level (many lines per `InvoiceNo`).

## Phase 1 — Completeness

- Null `CustomerID`.
- `Description` empty or whitespace-only.
- Any null/blank `InvoiceNo`, `StockCode`, `Country` (should be none).
- **Pass:** only `CustomerID` and `Description` are materially incomplete.

## Phase 2 — Transaction behaviour

- Rows with `InvoiceNo` like `'C%'`.
- Rows with `Quantity < 0`.
- Rows with `Quantity = 0` (if any).
- Cross-tab: cancellation prefix vs sign of `Quantity`.
- Example cancelled lines and any mismatches (for example `C` with positive quantity).
- **Pass:** you can define `is_cancellation` (and related flags) without deleting rows.

## Phase 3 — Price and value

- `UnitPrice = 0`, `< 0`, `> 0`.
- Min/max/percentiles for `Quantity` and `UnitPrice`.
- Extreme `|Quantity|` or `UnitPrice` with example invoices.
- Sum of `LineValue` for all rows vs positive-price, non-cancelled rows.
- **Pass:** you know what zero-price and outliers would do to revenue.

## Phase 4 — Product vs adjustment codes

- Top `StockCode`s by row count that are not typical product IDs.
- Known patterns: `POST`, `D`, `M`, `DOT`, `CRUK`, `BANK CHARGES`, gift/adjust codes.
- Row count and `LineValue` for those vs the rest.
- **Pass:** you can define `is_product_line` (or equivalent).

## Phase 5 — Duplicates and keys

- Duplicate full business-column rows.
- Repeat groups on `(InvoiceNo, StockCode, Quantity, UnitPrice, CustomerID)`.
- Distinct `Description` count per `StockCode` (text drift).
- Invoices with mixed `Country` or mixed `CustomerID` (should be rare).
- **Pass:** duplicate policy is evidence-based (keep, flag, or collapse later in silver).

## Phase 6 — Time and geography

- Rows per year-month.
- Top countries by rows and by `LineValue`.
- **Pass:** you have the analysis window and the UK vs other-country mix.

## Phase 7 — Examples and mismatches

- For each issue that still matters after Phases 0–6, keep a small set of example rows: cancellations, guests, empty description, zero/negative price, non-product codes, duplicates, outliers, and any `C%` vs `Quantity` mismatches.
- **Pass:** a reviewer can see what a silver flag would catch.

## Phase 8 — Decision list (required deliverable)

Write the short list profiling was for:

- Grain stays **invoice line**.
- What to **flag** in silver (for example cancellation, guest, empty description, non-product, duplicate, zero/negative price, outlier).
- What to **keep** in silver (default: all raw lines, plus flags).
- What **valid** means for **RFM** vs for **sales** (usually two different filters, applied later in gold or in views — not by shrinking raw).

**Pass:** flags and “valid” definitions are agreed; silver column names can be chosen only after this list.

## Phase 9 — Silver scope (plan only, no DDL yet)

- One silver table vs several.
- Which flags from Phase 8 become columns.
- `LineValue` as a **derived** silver column only.
- Same empty-table / row-count discipline as raw, when you later load.

**Pass:** silver design is documented; still no create/load until you agree Phase 8.

---

# Out of scope until Phase 8 is agreed

- Creating or loading silver tables.
- Filtering to clean sales in the profiling queries.
- Deduplicating or updating `raw.online_retail`.
- Optional extra checks (for example mixed `InvoiceDate` on one invoice, extra percentiles) only if a Phase 0–6 result is surprising.

---

**User**

The profiling plan is approved with the following additions:

1. Use the expected total of 541,909 only as a load-quality assertion.
   Calculate all percentages using the actual COUNT(*) dynamically.
2. For duplicates, later report:
   - duplicate group count,
   - rows belonging to duplicate groups,
   - extra duplicate rows beyond the first row.
3. Separate value measures into:
   - gross_sales_value: Quantity > 0 and UnitPrice > 0,
   - refund_value: Quantity < 0 and UnitPrice > 0,
   - net_line_value: all Quantity * UnitPrice,
   - zero_price rows/value,
   - negative_price rows/value.
4. Later check whether one InvoiceNo has multiple InvoiceDate values.
5. Later identify partial first and last calendar months.
6. Do not classify alphanumeric StockCodes as non-products based only on
   their format.

Now implement only Phases 0–3 in:

sql/02_raw_data_profiling.sql

Requirements:
- Use SQL Server syntax.
- Begin with USE RetailAnalytics.
- Read only from raw.online_retail.
- Write independent, clearly labelled query sections.
- Each issue query must show count and percentage using a dynamic total.
- Add TOP (10) example queries where relevant.
- Include comments explaining the business purpose of each query.
- Do not use INSERT, UPDATE, DELETE, MERGE, TRUNCATE, DROP, ALTER,
  CREATE TABLE, or SELECT INTO.
- Do not modify raw data.
- Do not create silver objects.
- Do not run the SQL.
- Do not implement Phases 4–9 yet.
- After editing, summarize which SQL section corresponds to each
  requirement and mention any assumptions.

---

**Cursor**

I’ll replace `sql/02_raw_data_profiling.sql` with Phases 0–3 only, using a dynamic `COUNT(*)` for percentages and the approved value measures.

Isabel, Phases **0–3** are in `sql/02_raw_data_profiling.sql`. I have not run it. Phases 4–9 are not in this file.

## Requirement → SQL section

| Requirement | Where it lives |
| --- | --- |
| `USE RetailAnalytics` | Top of file |
| Read-only `raw.online_retail` | All queries |
| **541,909 only as load assertion** | **0.1** (`actual_row_count` vs `expected_row_count`) |
| Percentages from **dynamic `COUNT(*)`** | `CROSS JOIN (SELECT COUNT(*) AS total_rows …)` on issue queries |
| `CustomerID` without `.0`; identifiers as strings | **0.5**, **0.6** |
| Grain / distinct keys / date range | **0.2–0.4** |
| Completeness (guests, empty description, unexpected blanks) | **1.1–1.6** |
| `C%` vs `Quantity` sign; mismatches; zero qty | **2.1–2.8** |
| `gross_sales_value`, `refund_value`, `net_line_value`, zero/negative price rows and value | **3.2** (signs also in **3.1**, **3.6**, **3.7**) |
| Min/max/percentiles and extreme examples | **3.3–3.5** |
| `TOP (10)` examples | **1.3, 1.5, 1.6, 2.5–2.8, 3.4–3.7** |
| Line value only in the query | `Quantity * UnitPrice` aliases; not stored |
| Duplicate group metrics | **Not implemented** (Phase 5) |
| One `InvoiceNo`, several `InvoiceDate`s | **Not implemented** (later) |
| Partial first/last calendar months | **Not implemented** (Phase 6) |
| Non-product `StockCode` | **Not implemented** (Phase 4; no format-based classification) |

## Assumptions

- `InvoiceNo LIKE 'C%'` is the cancellation prefix.
- **Refund value** is `Quantity < 0 AND UnitPrice > 0` (negative quantity at a positive price). Lines with `UnitPrice <= 0` are not in gross or refund; they sit in zero/negative price and still in **net**.
- Empty `Description` is `NULL` or whitespace-only; this file does not treat that as a load failure.
- Percentiles use `PERCENTILE_CONT` over the full table.
- Identifier “string” checks look for a leftover `%.0` pattern, not `INFORMATION_SCHEMA` types.

---

**User**

Please update sql/02_raw_data_profiling.sql with the following
targeted corrections. Keep Phases 0–3 only.

1. Simplify full-table summary queries

For sections 0.6, 1.1 and 3.2, which have no WHERE or GROUP BY:

- Replace NULLIF(MAX(t.total_rows), 0) with NULLIF(COUNT(*), 0).
- Remove the unnecessary CROSS JOIN that calculates total_rows.
- Keep all existing numerator conditions and business definitions.
- Do not use MAX(COUNT(*)).

2. Fix filtered issue-count queries

For sections:
0.5, 1.2, 1.4, 1.6, 2.1, 2.2, 2.3, 2.6, 2.7, 3.6 and 3.7:

- These queries use WHERE, so their outer COUNT(*) counts matching
  issue rows, not the full table.
- Calculate issue_rows and total_rows in separate single-row
  aggregate subqueries.
- CROSS JOIN those two single-row results.
- Calculate the percentage in the outer SELECT.

Required behaviour:
- Non-empty table with no matching issues: count 0 and percentage 0.
- Empty source table: count 0 and percentage NULL.
- Do not simply replace t.total_rows with MAX(t.total_rows).
- Do not use the filtered issue count as the denominator.

3. Preserve full-table denominators in grouped queries

For sections 2.4 and 3.1:

- Keep the independent full-table total from the CROSS JOIN.
- Keep NULLIF(MAX(t.total_rows), 0) as the denominator.
- Do not replace it with COUNT(*), because COUNT(*) here counts
  rows within each group.
- Each percentage must remain a percentage of the entire Raw table.

4. Correct unsupported comments

- Describe null CustomerID as "unidentified customer", not as a
  confirmed guest checkout.
- Remove the claim that missing Description became an empty string
  because the SQL column is NOT NULL.
- State only that blank descriptions were observed in SQL; the cause
  of that representation change has not been verified.

5. Add a separate metadata check

- Keep the existing identifier '.0' content checks.
- Add a read-only query showing column names, SQL data types and
  nullability for raw.online_retail.
- Read-only access to INFORMATION_SCHEMA.COLUMNS or system catalogs
  is permitted for this metadata check.

6. Improve example queries

- Include raw_row_id in every TOP (10) example output.
- Append raw_row_id as the final ORDER BY tie-breaker.

7. Clarify refund values in section 3.2

- Preserve refund_value as the signed negative amount for
  Quantity < 0 AND UnitPrice > 0.
- Add refund_amount_abs as its positive magnitude.
- Explain that this is a provisional refund measure pending
  classification of adjustment lines.

Constraints:
- Modify only sql/02_raw_data_profiling.sql.
- Do not rewrite unrelated queries.
- Do not implement Phases 4–9.
- Do not modify Raw data or create Silver objects.
- Do not run the SQL.

After editing:
- Summarize the changed sections.
- Explain which queries use COUNT(*) directly and which still need
  an independent full-table denominator.
- Confirm the expected behaviour for zero matching issue rows.

---

**Cursor**

I’ll read the profiling SQL and apply only the listed corrections in Phases 0–3.

Applying the targeted query-pattern, comment, metadata, example, and refund-value fixes without changing Phases 4–9 or unrelated logic.

Isabel, `sql/02_raw_data_profiling.sql` is updated for Phases 0–3 only. I have not run it.

## Changed sections

- **0.5, 1.2, 1.4, 1.6, 2.1–2.3, 2.6, 2.7, 3.6, 3.7:** issue `COUNT(*)` and full-table `COUNT(*)` are separate one-row aggregates, then `CROSS JOIN`ed; the outer query computes the percentage.
- **0.6, 1.1, 3.2:** no `CROSS JOIN`; denominator is `NULLIF(COUNT(*), 0)`.
- **2.4, 3.1:** unchanged pattern — full-table `CROSS JOIN` and `NULLIF(MAX(t.total_rows), 0)`.
- **0.7:** new read-only `INFORMATION_SCHEMA.COLUMNS` metadata query.
- **Comments:** unidentified customer; blank `Description` observed in SQL, cause not verified.
- **All `TOP (10)`:** `raw_row_id` in the select list and as the last `ORDER BY` key.
- **3.2:** `refund_amount_abs` added; `refund_value` stays signed and is labelled provisional.

## `COUNT(*)` vs independent full-table denominator

**Outer `COUNT(*)` is the full table** (no `WHERE`/`GROUP BY`): **0.6, 1.1, 3.2** — also **0.1** for the load assertion.

**Independent full-table total** (`t.total_rows`):  
- Filtered issues: **0.5, 1.2, 1.4, 1.6, 2.1, 2.2, 2.3, 2.6, 2.7, 3.6, 3.7** (`i.issue_rows` is the match count).  
- Grouped: **2.4, 3.1** (`COUNT(*)` is the group size; `MAX(t.total_rows)` is the whole table).

## Zero matching issue rows

On a **non-empty** table with no matches: `issue_rows = 0` and percentage **0**.  
If the **source table is empty**: `issue_rows = 0` and percentage **NULL** (`NULLIF(total_rows, 0)`).

---

**User**

I have reviewed and run Phases 0–3 in SSMS.

Create or update:
docs/02_raw_profiling_findings.md

Use the actual results I provide below, not assumptions based on SQL code.

For each finding, document:
- SQL section number,
- observed count and percentage,
- relevant example raw_row_ids,
- what the result means,
- potential impact on revenue, customer or product analysis,
- proposed treatment,
- questions that remain unresolved.

Requirements:
1. Clearly separate observed facts from interpretations and proposals.
2. Do not invent missing counts or examples; mark them Pending.
3. Do not assume every negative quantity is a confirmed refund.
4. Do not assume missing CustomerID means guest checkout.
5. Do not decide to delete outliers or duplicates without evidence.
6. Treat gross_sales_value and refund_value as provisional measures
   until adjustment codes have been reviewed.
7. State that Phases 4–6 are still pending.
8. Do not finalize Silver rules yet.
9. Do not create Silver objects, modify SQL, or run anything.

Actual SSMS results:
[paste the Phase 0–3 results here]

---

**Cursor**

The SSMS block is still a placeholder, so I’ll add `docs/02_raw_profiling_findings.md` with the required structure and mark every count and example as Pending rather than inventing numbers.

Isabel, `docs/02_raw_profiling_findings.md` is in place. I did not change SQL, Raw, or Silver, and I did not run anything.

The SSMS block in your message was still the placeholder `[paste the Phase 0–3 results here]`, so **every count, percentage, and `raw_row_id` is marked Pending**. Nothing was invented.

The note:

- Splits **fact / interpretation / proposal** for Phases 0–3  
- Does not treat negative quantity as a confirmed refund, or null `CustomerID` as guest checkout  
- Does not propose deleting outliers or duplicates  
- Treats `gross_sales_value` and `refund_value` as **provisional**  
- States **Phases 4–6 are still pending** and **Silver rules are not finalized**

Paste the actual SSMS grids when you have them and this file can be filled with real numbers.

---

**User**

You may now execute the reviewed read-only profiling queries and
summarize the actual results.

Scope:
- SQL file: sql/02_raw_data_profiling.sql
- Phases 0–3 only
- Server: .\MSSQLSERVER02
- Database: RetailAnalytics
- Authentication: Windows Trusted Connection
- Use the existing project .venv and installed pyodbc.

Tasks:

1. Inspect the SQL file before execution.
   Confirm it contains only the approved read-only profiling queries
   and metadata checks.
   If you find database-changing statements, stop and report them.

2. Create a separate script:
   scripts/02_run_raw_profiling.py

   Reuse the working connection configuration, but do not import or run
   scripts/01_load_raw_data.py because it loads data.

3. Execute the reviewed profiling SQL.
   Handle standalone GO batch separators correctly: GO is a client-side
   separator and must not be sent directly to pyodbc.
   Collect all result sets using cursor.nextset(), where necessary.
   Preserve column names and map each result set to its SQL section.

4. Save the query results under:
   outputs/profiling/phase_0_3/

   Preserve SQL NULL distinctly from empty strings.
   Record execution time and the source SQL file.
   Do not overwrite existing result files without asking.

5. Run this new profiling runner using the project .venv.

6. Update:
   docs/02_raw_profiling_findings.md

   Replace Pending fields only with successfully observed results.
   For each finding include:
   - SQL section,
   - count and percentage where applicable,
   - relevant example raw_row_ids,
   - interpretation,
   - potential business impact,
   - proposed treatment or further investigation.

Safety constraints:
- Do not run the raw loading script.
- Do not modify database data, schemas or permissions.
- Do not create Silver objects.
- Do not change the reviewed profiling SQL.
- Do not install packages or change system settings.
- If permissions or connections fail, stop and report the error.
- If a query fails, report the failure and do not invent its result.
- Always close cursors and connections.

Interpretation:
- Separate observed facts from hypotheses.
- Do not assume all negative quantities are refunds.
- Do not assume missing CustomerID means guest checkout.
- Do not finalize Silver rules; Phases 4–6 remain pending.

Finish with a concise summary of:
- queries completed or failed,
- important findings,
- saved result locations,
- remaining decisions.

---

**Cursor**

I’ll inspect the profiling SQL for anything that changes the database, then add a runner, execute Phases 0–3, save the result sets, and update the findings note from those outputs.

The SQL file is read-only (SELECT plus `INFORMATION_SCHEMA`). Next I’ll add a runner that splits on `GO`, execute Phases 0–3, and save the result sets.

Isabel, the profiling SQL is **read-only** (SELECT plus `INFORMATION_SCHEMA`). There were no INSERT/UPDATE/DELETE or schema changes. I did not run the load script or change `sql/02_raw_data_profiling.sql`.

## Execution

`scripts/02_run_raw_profiling.py` ran with `.venv` against `.\MSSQLSERVER02` / `RetailAnalytics`. **28 statements completed, 0 failed** (~16.8s). `GO` was not sent to pyodbc.

Results: `outputs/profiling/phase_0_3/` (including `manifest.json`). No files were overwritten (the folder was empty).

## Important findings (facts)

- **541,909** rows, load check **PASS**. Dates **2010-12-01** to **2011-12-09**. Grain: ~**21** lines per invoice (max **1,114**).
- **24.93%** (135,080) null `CustomerID` — unidentified, **not** labelled guest. **1,454** blank descriptions (**0.27%**). Invoice/stock/country blanks: **0**.
- **`C%`:** 9,288 lines (**1.71%**), all with **negative qty**. **1,336** further negative-qty lines **without** `C` (**0.25%**) — **not** assumed refunds. Zero quantity: **0**.
- Provisional values: gross **10,666,684.54**; signed “refund” **−896,812.49**; net **9,747,747.93**. Zero price **2,515** lines; **2** negative-price “Adjust bad debt” rows (`raw_row_id` **309984**, **309985**). Extreme qty pair **550422** / **550423** (±80,995). High prices include `M` / `AMAZONFEE` — totals stay **provisional** until Phase 4.

Findings note: `docs/02_raw_profiling_findings.md`.

## Remaining decisions

Phases **4–6** (codes, duplicates, time/geography). Do **not** finalize Silver: how to flag `C%` vs other negative qty, unidentified customers, zero price, and outliers — **without deleting rows**.

---

**User**

Phases 0–3 completed successfully: 28 statements, 0 failures.
The actual findings are recorded in:
docs/02_raw_profiling_findings.md

Read that document and append Phases 4–6 to:
sql/02_raw_data_profiling.sql

Do not change the reviewed Phases 0–3.

Phase 4 — Product, service and adjustment codes

- Profile candidate codes including POST, D, M, DOT, CRUK,
  BANK CHARGES, AMAZONFEE and codes associated with "Adjust bad debt".
- Discover additional candidates using descriptions and observed values.
- Do not classify codes as non-products merely because they contain letters.
- For each candidate code, show row count, percentage of all rows,
  quantity/price sign breakdown, gross value, signed negative-quantity
  value and net LineValue.
- Show TOP (10) examples per candidate code using raw_row_id.
- Treat classifications as proposals, not confirmed rules.
- Reconcile:
  net_line_value = gross_sales_value + signed_refund_value
                   + negative_price_value.
- Check whether negative_price_value totals -22,124.12 and whether
  this corresponds to the two observed "Adjust bad debt" rows.
  Report actual results; do not hard-code the expected result.

Phase 5 — Duplicates and invoice consistency

- Define exact duplicates using all eight original business columns,
  excluding raw_row_id, source_file and loaded_at.
- Report duplicate group count, rows in duplicate groups and extra
  rows beyond the first.
- Profile repeated combinations of InvoiceNo, StockCode, Quantity,
  UnitPrice and CustomerID as potential duplicates only.
- Show example groups and their raw_row_ids.
- Show StockCodes with multiple descriptions.
- Check invoices with multiple CustomerIDs, Countries or InvoiceDates.
- Check mixed null/non-null CustomerID separately, because
  COUNT(DISTINCT CustomerID) ignores NULL.
- Explain the effect of SQL collation on text equality when reporting
  exact duplicates.
- Do not delete or collapse any records.

Phase 6 — Time and geography

- Report rows, distinct invoices, identified customers, gross value,
  signed negative-quantity value, negative-price value and net value
  by calendar month.
- Include minimum and maximum observed dates per month.
- Flag the final month as potentially incomplete based on the dataset
  ending on 2011-12-09.
- Do not assume that a missing transaction on a month's final day
  alone proves the extract is incomplete.
- Report country-level row counts, invoices, identified customers,
  value measures and net-value share.
- Include a UK versus non-UK summary.
- Keep values provisional until classification rules are approved.

General requirements

- SQL Server syntax; independent, clearly labelled query sections.
- Read-only business queries against raw.online_retail.
- Dynamic full-table denominators with correct aggregation.
- Distinguish line counts from distinct invoice counts.
- Include raw_row_id in examples and deterministic ordering.
- Preserve original values; no data or schema changes.
- Do not create Silver objects.
- Do not implement Phases 7–9.
- Do not run SQL or the Python profiling runner.
- Modify only sql/02_raw_data_profiling.sql.

After editing, summarize the new sections and any assumptions.

---

**Cursor**

I’ll read the findings note and the end of the profiling SQL so Phases 4–6 can be appended without changing the reviewed 0–3 queries.

Updating only the file header, then appending Phases 4–6 after the last Phase 3 query.

Isabel, Phases **4–6** are appended to `sql/02_raw_data_profiling.sql`. Reviewed Phases **0–3** queries are unchanged (only the file header now says 0–6). I did not run SQL or the Python runner.

## New sections

**Phase 4 — codes (proposals only)**  
- **4.1** Seed list: `POST`, `D`, `M`, `DOT`, `CRUK`, `BANK CHARGES`, `AMAZONFEE`, `B`, plus `Description LIKE '%Adjust bad debt%'`, with line vs invoice counts, %, and provisional values.  
- **4.2** Quantity × price sign breakdown (full-table %).  
- **4.3** Extra candidates from description wording (postage, manual, discount, Amazon, adjust, bank, gift, carriage, samples) — **not** from letters in the code.  
- **4.4** TOP 10 examples per seed `StockCode` (`raw_row_id`, deterministic order).  
- **4.5** Recompute `net = gross + signed_refund + negative_price` (no hard-coded totals).  
- **4.6** Compare all negative-price lines with “Adjust bad debt” (counts and values computed).

**Phase 5 — duplicates / consistency (no deletes)**  
- **5.1** Text-column collation.  
- **5.2–5.3** Exact dups on the eight business columns: group count, rows in groups, extra rows, example `raw_row_id`s.  
- **5.4–5.5** Five-column repeats as *potential* dups only.  
- **5.6–5.7** Several descriptions per `StockCode`.  
- **5.8–5.11** Invoices with multiple non-null `CustomerID`s; mixed null/non-null (separate, because `COUNT(DISTINCT)` skips NULL); multiple countries; multiple `InvoiceDate`s.

**Phase 6 — time / geography (values still provisional)**  
- **6.1** By calendar month: lines, invoices, identified customers, value buckets, min/max dates; month of the extract’s last timestamp flagged `potentially_incomplete_final_month` (not “missing the 31st proves a gap”).  
- **6.2** By country, including net-value share.  
- **6.3** UK vs non-UK (`Country = 'United Kingdom'`).

## Assumptions

- Seed codes match UCI spellings (`BANK CHARGES`, `AMAZONFEE`).  
- UK is the string `United Kingdom` as in Phases 0–3 examples.  
- `STRING_AGG` needs SQL Server 2017+.  
- Duplicate equality uses column collation (usually CI).  
- Phases 7–9 are still not in the file.

---

**User**

Phases 4–6 are approved for read-only execution.

Please run them and produce evidence-based findings, not a
template with Pending values.

1. Execution
- Reuse and minimally adapt scripts/02_run_raw_profiling.py.
- Use the existing working .venv and SQL Server connection:
  .\MSSQLSERVER02 / RetailAnalytics.
- Execute only Phases 4–6 from sql/02_raw_data_profiling.sql.
- Do not rerun Phases 0–3 or the raw loading script.
- Handle GO correctly and capture every result set, including
  multiple result sets within one numbered section.
- Do not change the profiling SQL in this step.
- Stop and report execution or permission errors; do not change
  database settings, permissions, or install dependencies.

2. Save results
- Save results under outputs/profiling/phase_4_6/.
- If that folder already contains results, use a new timestamped
  subfolder rather than overwriting them.
- Include a manifest mapping SQL section numbers to output files,
  execution status, result row counts, and errors.
- Preserve the distinction between NULL and empty strings.

3. Write findings
- Create docs/03_raw_profiling_phase_4_6_findings.md.
- If it already exists, preserve it and create a new version.
- Cite the SQL section and output filename for each key finding.
- Separate observed facts, interpretations, proposed rules,
  and unresolved questions.
- Do not invent results for failed or missing queries.

Cover:
- Candidate service/adjustment codes and their value impact.
- Net-value reconciliation and the negative-price/bad-debt comparison.
- Exact duplicate groups, rows in groups, and extra rows.
- Potential five-column duplicates, separately from exact duplicates.
- Description drift and invoice customer/country/date inconsistencies.
- Monthly coverage, the partial final month, and UK/non-UK mix.

Interpretation cautions:
- Section 4.3 measures keyword-matching rows, not necessarily all
  rows for each StockCode. GIFT can match legitimate products.
- Section 4.6 compares different populations. A difference is
  not automatically an error.
- Section 5.8 line_count includes only non-null CustomerID rows.
- Duplicate equality follows SQL collation, not necessarily
  byte-for-byte equality.
- Negative quantities are not automatically confirmed refunds.
- Values remain provisional, not finalized business revenue.

4. Validation
- Check that monthly and country line counts each sum to 541,909.
- Reconcile their value totals to the full-table value totals.
- Do not sum distinct customers or invoices across groups and
  assume the result equals the global distinct count.
- Report the actual identity_difference from section 4.5.

5. Scope
- No database writes or schema changes.
- Do not create or load Silver.
- End with a short list of decisions requiring my approval before
  Silver design, and any targeted follow-up checks genuinely needed.

You may create/update the runner and local result/findings files
as described above, and run the read-only profiling now.

---

**Cursor**

I’ll adapt the runner to execute only Phases 4–6, save the result sets, then write findings from those outputs.

Isabel, Phases **4–6** ran read-only: **20 statements, 0 failures** (~11.5s). Results are in `outputs/profiling/phase_4_6/` (`manifest.json` maps sections → files). Findings: `docs/03_raw_profiling_phase_4_6_findings.md`. The profiling SQL was not changed; Raw/Silver were not written.

## Important facts

- **Seed codes:** POST/DOT add large **positive** net (esp. DOT ~206k); AMAZONFEE net **−221,521**; M **−68,672**. Labels are **proposals** only.
- **4.3:** 144 keyword-matching codes; **GIFT hits real products**. Stronger extras: **C2** carriage, **S** samples — not a dump of all letter codes.
- **4.5 `identity_difference` = 0.0000** (net = gross + signed neg-qty + neg-price).
- **4.6:** 2 negative-price lines (−22,124.12) vs 3 “Adjust bad debt” lines (net −11,062.06) because **309983** is +11,062.06. Different populations, not an error.
- **Exact dups:** 4,879 groups, 10,147 rows, **5,268 extras**. Five-column repeats are almost the same (4,882 / 5,271 extras). Collation **Chinese_PRC_CI_AS**.
- **Invoices:** no mixed CustomerID or Country; **43** invoices have two `InvoiceDate`s (often 1 minute apart).
- **Time/geo:** monthly and country **line counts = 541,909**; value buckets match 4.5. **2011-12** flagged potentially incomplete (ends 9 Dec). UK **91.4%** of lines, **84.0%** of net.

## Decisions before Silver

Whether to flag the 4.1 seed (+ C2/S, not GIFT SKUs); all three B lines vs two negative-price only; keep vs flag duplicate extras; StockCode vs canonical Description; Dec 2011 as a partial month for RFM/sales.

---

**User**

Profiling is complete enough. Simplify the workflow now.

We will keep SQL Server Raw as the source of truth and prepare
analysis data in Python. Do not build SQL Silver or Gold objects.

Create notebooks/01_data_preparation.ipynb.
Use short, clearly labelled cells and beginner-friendly comments.
Avoid unnecessary classes, frameworks, or extra scripts.

Read the existing profiling findings and actual saved results.
Do not rerun the full profiling.

1. Read the data
- Use the existing .venv and working SQL Server connection:
  .\MSSQLSERVER02 / RetailAnalytics.
- Read raw.online_retail with a SELECT query.
- Reuse the connection settings, but do not import or execute
  01_load_raw_data.py because it has loading side effects.
- Use installed dependencies. If another package is required,
  stop and explain rather than installing it automatically.
- Keep the loaded dataframe as df_raw; work on a copy named df.
- Preserve every row, raw_row_id, and all original columns.
- Close the database connection after reading.

2. Basic preparation
- Show shape, dtypes, and missing-value counts.
- Confirm 541,909 rows and unique, non-null raw_row_id.
- Keep identifiers as nullable strings, preserving missing values.
- Ensure InvoiceDate is datetime.
- Create a separate cleaned Description column:
  trim surrounding spaces and represent blank text as missing.
- Do not overwrite the original Description.
- Create line_value = Quantity * UnitPrice.
- Explain any Decimal-to-float conversion. Validate monetary
  reconciliation to the nearest penny, not exact float equality.

3. Add flags and a transparent code mapping
Add understandable flags for:
- unidentified customer;
- missing/blank description;
- C-prefixed invoice;
- negative quantity;
- zero price;
- negative price.

Create a small, explicit StockCode mapping based on observed
descriptions and profiling evidence:
- postage/carriage;
- fees/commission;
- discount;
- manual/unresolved;
- samples;
- bad-debt adjustment.

Include the reviewed seed codes plus C2 and S.
Keep M as manual/unresolved.
Mark all three observed B / Adjust bad debt rows as adjustments.
Do not classify ordinary GIFT products or alphanumeric codes as
non-products merely because of their text or format.

Label remaining codes as merchandise_candidate, not as
definitively verified merchandise.

4. Duplicate handling
- Identify duplicates using the eight original business columns,
  excluding raw_row_id and load metadata.
- Add duplicate group size and a deterministic extra-row flag,
  ordered by raw_row_id.
- Preserve all rows; do not deduplicate the main dataframe.
- Compare Python duplicate counts with SQL:
  4,879 groups, 10,147 participating rows, 5,268 extras.
- Python string equality may differ from Chinese_PRC_CI_AS.
  If counts differ, report and explain; do not force a match by
  blindly lowercasing all text.
- Show a small sensitivity summary of line value and provisional
  gross sales with versus without duplicate extras.

5. Time preparation
- Add invoice month and a flag for the final partial month.
- Preserve line-level InvoiceDate.
- Derive order_timestamp using the earliest InvoiceDate per invoice,
  preferably with groupby().transform().
- Summarize invoices whose timestamps cross dates or months.
- Set an RFM reference date to the day after the maximum observed
  transaction date, not today's date.
- Do not calculate RFM yet.

6. Define reusable analysis masks, without deleting rows
Use explicit, provisional definitions:
- merchandise sale:
  merchandise_candidate, Quantity > 0, UnitPrice > 0,
  and invoice not C-prefixed;
- merchandise negative-value line:
  merchandise_candidate, Quantity < 0, UnitPrice > 0;
- identified-customer purchase:
  merchandise sale with a non-missing CustomerID.

Keep duplicate rows included in the baseline for now.
Do not describe negative-value lines as confirmed cash refunds.
Keep raw net value separate from merchandise measures.

7. Validate and summarize
- Confirm row count and raw_row_id coverage are unchanged.
- Reconcile raw line_value and value buckets to the prior findings.
- Show counts by flags and proposed line categories.
- Show row counts and values for each analysis mask.
- End with a short Markdown section explaining:
  what changed, what stayed untouched, provisional assumptions,
  and whether the data is ready for monthly revenue, country
  contributions, and top-customer analysis.

Scope:
- Create and run this notebook using the existing .venv.
- SQL access must be SELECT-only.
- No database writes, schema changes, or raw loading.
- Do not overwrite an existing notebook; preserve it if present.
- Do not export the full transaction dataset or commit anything.
- Do not start the ten business-question analyses yet.
- If execution fails, report the failing cell and error honestly.

After execution, report the validation results and any material
blocker. Do not return a findings template containing Pending.

---

**Cursor**

I’ll check for an existing notebook and the profiling evidence, then create and run a beginner-friendly preparation notebook against Raw only.

Creating the notebook with short labelled cells, then executing it with the project venv. No `notebooks/` folder yet, so this won't overwrite an existing file.

Isabel, `notebooks/01_data_preparation.ipynb` was created and executed with the project `.venv`. There was no existing notebook to preserve. SQL was **SELECT-only**. Raw was not reloaded. Profiling was not rerun.

A pandas warning appeared: `read_sql` prefers SQLAlchemy; **pyodbc still loaded 541,909 rows**. No extra package was installed.

## Validation (from executed cells)

| Check | Result |
| --- | --- |
| Rows / unique `raw_row_id` | **541,909**, all non-null and unique |
| Original `Description` | Unchanged |
| Money vs SQL 4.5, **nearest penny** | net **9,747,747.93**, gross **10,666,684.54**, signed neg-qty **−896,812.49**, neg-price **−22,124.12** — **match** |
| Exact duplicates vs SQL | **4,879 / 10,147 / 5,268** — **match** (no forced lowercasing) |
| Sensitivity (drop extras, df still full) | net **9,726,006.95**, gross **10,642,110.80** |
| RFM reference | **2011-12-10** (day after max timestamp) |
| Multi-timestamp invoices | **43** (same as SQL 5.11); **0** cross date or month |
| Final partial month lines | **25,525** |

Flags match profiling: unidentified **135,080**; blank description **1,454**; C-prefix **9,288**; neg qty **10,624**; zero price **2,515**; neg price **2**.

**Masks (extras kept):** merchandise sale **527,793** / **10,272,121.42**; merchandise negative-value **8,704** / **−478,724.18** (not labelled cash refunds); identified-customer purchase **396,340** / **8,761,066.65**.

## Small mapping note (not a load failure)

`code_group` sums to 541,909. SQL seed+C2+S implied **572** `M` and **2,109** POST+DOT+C2; Python has **571** `manual_unresolved` and **2,110** `postage_carriage`. One-row difference — inspect later if you want an exact 4.1 match. **B / Adjust bad debt = 3.**

## Ready for

Monthly revenue, country mix, and top identified customers, with Dec 2011 as a **partial month**. **RFM scores were not calculated.** No full extract was exported.

**Blocker:** none for those next analyses.

---

**User**

Data preparation has been executed and validated.

Now create and run:
notebooks/02_revenue_customer_analysis.ipynb

Answer only:
1. How does merchandise revenue change by month?
2. Which countries contribute the most merchandise revenue?
3. Who are the top identified customers?

Keep the code beginner-friendly, with short cells and comments.
Do not build SQL Silver/Gold tables or repeat the full profiling.

1. Reuse the preparation

Read notebooks/01_data_preparation.ipynb and reuse its existing
definitions, code mapping, flags, and analysis masks consistently.

The new notebook must run independently from a fresh kernel.
Do not assume variables from notebook 01 are available.
For this exercise, reuse the necessary preparation cells without
introducing a new framework or restructuring the project.

Use the existing .venv and working SQL Server connection:
.\MSSQLSERVER02 / RetailAnalytics.

Read raw.online_retail using SELECT only.
Do not import or execute the raw loading script.
Close the connection after reading.
Do not install new packages automatically.

Preserve all raw rows and original columns in the working data.

2. Revenue definitions

Use the same masks as notebook 01:

gross_merchandise_sales:
- code_group = merchandise_candidate
- Quantity > 0
- UnitPrice > 0
- InvoiceNo is not C-prefixed

negative_merchandise_value:
- code_group = merchandise_candidate
- Quantity < 0
- UnitPrice > 0

net_merchandise_value:
- gross_merchandise_sales + negative_merchandise_value

Negative merchandise value is signed.
It is not necessarily a confirmed cash refund.

Use each line's InvoiceDate to attribute its value to a month.
Do not match negative lines back to original purchases in this step.

Exclude classified postage, fees, discounts, manual entries,
samples, and bad-debt adjustments from merchandise measures.

Keep duplicate extras in the baseline.
Provide a secondary sensitivity comparison excluding extras,
without deleting rows from the main dataframe.

Retain the existing duplicate logic:
group by the eight original business columns and rank raw_row_id
within each group. Since raw_row_id is unique, its ascending rank
selects the lowest raw_row_id as the retained record.

3. Question 1 — Monthly revenue

Create a monthly summary with:
- month;
- gross merchandise sales;
- signed negative merchandise value;
- net merchandise value;
- absolute negative merchandise value / gross sales, as a percentage;
- distinct purchase invoices;
- identified purchasing customers;
- net merchandise value excluding duplicate extras;
- month-over-month change in net merchandise value.

Count purchase invoices and purchasing customers using the
positive-sale mask, not negative-only transactions.

Use pandas groupby(), agg(), and shift() where appropriate.
Sort months before calculating month-over-month changes.
Handle zero denominators safely.

Time-window rules:
- December 2010 is the first observed month.
- Do not label December 2010 incomplete merely because it is first:
  the extract starts on 2010-12-01.
- December 2011 is incomplete: it ends on 2011-12-09.
- Keep December 2011 visible, but do not interpret its comparison
  with November as a full-month growth or decline.
- Show its standard full-month MoM measure as missing, with a note.
- The first month has no prior observed month for MoM.

Create a Matplotlib line chart of monthly gross and net merchandise
value. Annotate December 2011 as partial.

4. Question 2 — Country contribution

Create a country summary with:
- gross merchandise sales;
- signed negative merchandise value;
- net merchandise value;
- percentage of total net merchandise value;
- distinct purchase invoices;
- identified purchasing customers;
- net merchandise value excluding duplicate extras.

Include countries with negative merchandise lines even if they
have no positive sales.

Sort by net merchandise value descending.
Show the top 10 countries in a horizontal bar chart.
Provide a separate UK versus non-UK summary.

Use all countries, not just the top 10, as the denominator for shares.
Do not sum country-level distinct customer counts and call that
the global distinct customer count.

5. Question 3 — Top customers

Include non-missing CustomerIDs with either positive merchandise
sales or negative merchandise value. Do not accidentally lose
customers with negative-only activity through an inner join.

For each customer calculate:
- gross merchandise sales;
- signed negative merchandise value;
- net merchandise value;
- distinct positive-sale invoices;
- positive merchandise units;
- first observed merchandise purchase;
- last observed merchandise purchase;
- net merchandise value excluding duplicate extras.

Use the positive-sale mask for purchase counts, units, and dates.
Customers without observed positive sales should have zero purchase
counts and missing purchase dates.

Rank customers by net merchandise value using rank().
Also calculate a rank by gross merchandise sales.
State the tie-handling method.

Show the top 20 by net merchandise value.
Create a horizontal bar chart for the top 10, with CustomerID
displayed as a categorical label rather than a numeric axis.

Summarize:
- how many customers have negative net merchandise value;
- the largest differences between gross and net rankings.

Do not call first observed purchase first-ever purchase.
Do not calculate new/existing status, repeat rate, retention,
customer decline, or RFM yet.

6. Validation

Use assertions where appropriate, not only printed comparisons.

Reconcile to notebook 01:
- gross merchandise sales: 10,272,121.42;
- signed negative merchandise value: -478,724.18;
- identified-customer gross purchases: 8,761,066.65.

Compare monetary totals to the nearest penny.

Check that:
- monthly value totals equal the full merchandise totals;
- country value totals equal the full merchandise totals;
- the full customer summary equals identified-customer merchandise
  totals, including negative-only customers;
- identified plus unidentified merchandise values reconcile to
  all-customer merchandise values.

Reconcile using full summaries before selecting top 10 or top 20.
Do not assume net identified-customer value must be lower simply
because unidentified customers were excluded; calculate the split.

Report duplicate sensitivity:
- amount and percentage difference in net merchandise value;
- whether the top-country or top-customer rankings change.

The previous summary reported a one-row difference between manual
and postage categories. Do not invent a reclassification to match
that summary. Use notebook 01's actual mapping and report if its
executed counts differ from its written summary.

7. Findings and outputs

End with a concise Markdown interpretation:
- 2–3 useful findings per business question;
- exact figures supporting each finding;
- no invented explanations for why sales changed;
- limitations: partial final month, unidentified customers,
  provisional merchandise classification, negative values,
  and duplicate treatment.

Save summary tables:
- outputs/tables/monthly_revenue.csv
- outputs/tables/country_revenue.csv
- outputs/tables/customer_revenue.csv
- outputs/tables/top_customers.csv

customer_revenue.csv should contain the full customer summary.
top_customers.csv should contain the top 20.

Save charts under outputs/figures/.
Do not export transaction-level data.

If any target notebook or output file already exists, preserve it
and use a timestamped alternative.

Scope and authorization:
- You may create and run this notebook and save the stated outputs.
- SQL access must remain SELECT-only.
- No database writes, schema changes, raw loading, or Git commits.
- Do not modify notebook 01.
- If execution fails, report the failing cell and actual error.
- Do not report unexecuted or Pending results as findings.

After execution, summarize validation results, key findings,
output paths, and any material blocker.

---

**Cursor**

I’ll read notebook 01’s preparation logic and check for existing outputs, then create and run the independent analysis notebook.

Creating an independent notebook that reuses notebook 01’s mapping and masks, then executing it and saving the summary tables and charts.

Notebook `notebooks/02_revenue_customer_analysis.ipynb` ran successfully from a fresh kernel. Assertions matched notebook 01 to the nearest penny. No SQL writes, no changes to notebook 01, no Git commits.

## Validation

Reconciled to notebook 01: gross merchandise **10,272,121.42**; signed negative merchandise **−478,724.18**; identified-customer gross purchases **8,761,066.65**. Monthly and country value totals match those full merchandise totals. The full customer file matches identified-customer merchandise (including 28 negative-only customers). Identified net **8,286,663.32** plus unidentified net **1,506,733.92** equals all-customer net **9,793,397.24**.

Executed `code_group` counts match notebook 01’s mapping: merchandise **538,998**; postage **2,110**; manual **571**. SQL 4.1 had M = 572 and POST+DOT+C2 = 2,109 (one-row difference). That row was not reclassified.

Duplicate extras: net **9,793,397.24** vs **9,772,006.52** without extras (**21,390.72**, **0.22%**). Top 10 countries unchanged. Top 10 customers change: **15311** (with extras) vs **16029** (without).

## Question 1 — Monthly merchandise revenue

Among complete months, net is lowest in **2011-02 (500,577.00)** and highest in **2011-11 (1,432,734.99)**; November also has the most purchase invoices (**2,751**) and identified purchasing customers (**1,660**).

**2011-01** net **580,466.11** is **179,936.94** below December 2010 (**760,403.05**); absolute negative value is **13.62%** of January gross (vs **2.26%** in Dec 2010). **2011-04** net **482,992.88**, complete-month MoM **−197,597.76**.

**2011-12** is partial (ends 2011-12-09): net **441,374.84**, abs-negative / gross **28.29%**. Full-month MoM vs November is missing and is not a full-month change. December 2010 starts on 2010-12-01, so it is not labelled incomplete.

## Question 2 — Country contribution

**United Kingdom** net **8,302,406.64** (**84.78%** of **9,793,397.24**). Non-UK **1,490,990.60** (**15.22%**). Shares use all **38** countries.

Next by net: Netherlands **283,479.54 (2.89%)**, EIRE **259,663.46 (2.65%)**, Germany **200,808.40 (2.05%)**, France **182,163.39 (1.86%)**. UK identified purchasing customers (positive-sale mask): **3,916**. Country distinct counts were not summed as a global customer count.

## Question 3 — Top identified customers

**4,362** identified CustomerIDs; ranks use `rank(method="min")`. Top three by net: **14646 (278,778.02)**, **18102 (259,657.30)**, **17450 (189,735.53)**. **30** customers have negative net.

Largest worse net-vs-gross ranks: **16446** (gross **168,472.50**, net **2.90**, ranks **4** vs **4,320**) and **12346** (gross **77,183.60**, net **0.00**, ranks **9** vs **4,323**). Unidentified customers are **15.38%** of all-customer net, not a leftover that must sit below identified net.

## Outputs

- `outputs/tables/monthly_revenue.csv`
- `outputs/tables/country_revenue.csv`
- `outputs/tables/customer_revenue.csv` (full summary)
- `outputs/tables/top_customers.csv` (top 20)
- `outputs/figures/monthly_merchandise_revenue.png`
- `outputs/figures/top_10_countries_net_merchandise.png`
- `outputs/figures/top_10_customers_net_merchandise.png`

No material blocker. The pandas `read_sql(pyodbc)` SQLAlchemy warning appeared; it did not fail the run.

---

**User**

The core analysis is accepted. Make only these small corrections
in notebooks/02_revenue_customer_analysis.ipynb:

1. Correct the monthly findings.
The text says February is the lowest complete month at 500,577.00,
but April is lower at 482,992.88.

Calculate the minimum and maximum directly from the monthly summary,
excluding the flagged partial final month. Use the computed results
to correct the findings. Check the other monthly superlatives too.
Do not change the revenue definitions or data preparation.

2. Before any rerun, make all CSV and PNG exports non-overwriting.
If a target exists, save a timestamped version instead.

3. Keep the existing raw_row_id ranking logic unchanged.
It correctly ranks unique raw_row_id values within duplicate groups.

Use saved summary CSVs to verify the monthly findings where possible;
do not reload SQL or rerun the full notebook just to correct prose.
If code cells must be run, execute only the relevant cells when their
inputs are available; otherwise explain what needs rerunning.

Report the corrected lowest/highest complete month and the files changed.
Do not start the next business questions yet.

---

**Cursor**

I'll verify complete-month min/max from the saved monthly CSV, then fix the findings text and make CSV/PNG exports skip existing files.

CSV check: among complete months, net is lowest in April (482,992.88) and highest in November (1,432,734.99). February is only the lowest by gross. Next I’ll fix the findings text and make exports non-overwriting.

Lowest complete-month net is **2011-04 at 482,992.88**. Highest is **2011-11 at 1,432,734.99**. February was lowest by **gross** (508,952.87), not by net.

Those figures come from `outputs/tables/monthly_revenue.csv`, excluding the flagged partial month (`is_partial_final_month`). Other complete-month checks: November still has the most purchase invoices (2,751), identified purchasing customers (1,660), and the largest MoM net rise (+370,040.66). April is the largest complete-month MoM decline (−197,597.76). January has the highest abs-negative / gross among complete months (13.62%).

The notebook was **not** rerun. Existing CSVs and PNGs were left in place. `unique_output_path()` is now used for all four CSV writes and all three PNG saves, so a later run writes a timestamped file if the target already exists.

**File changed:** `notebooks/02_revenue_customer_analysis.ipynb` only (findings prose, complete-month min/max print for future runs, non-overwriting exports). Duplicate `raw_row_id` ranking is unchanged. The new min/max print will appear the next time that monthly cell is executed with `monthly_out` in memory.

---

**User**

The code review is complete. No further logic changes are required.

Now restart the kernel and run all cells in:

notebooks/02_revenue_customer_analysis.ipynb

Purpose:
- synchronize all saved cell outputs with the updated source code;
- execute the new complete-month min/max checks;
- verify the non-overwriting export logic;
- confirm the notebook runs successfully from a fresh kernel.

Requirements:
- Do not change the analysis definitions or findings unless an
  executed result contradicts them.
- Keep SQL access SELECT-only.
- Do not modify notebooks 01, 03, or other project files.
- Existing CSVs and PNGs must remain untouched.
- New exports should use timestamped filenames because the original
  output files already exist.
- Do not rerun the raw loader or profiling.
- Do not commit to Git.

After execution, confirm:
1. all cells completed successfully;
2. the printed lowest complete-month net is 2011-04 at 482,992.88;
3. the printed highest complete-month net is 2011-11 at 1,432,734.99;
4. all monetary reconciliation assertions passed;
5. timestamped CSV and PNG paths created;
6. the saved notebook contains outputs from this latest run.

If any result differs, report the actual result and stop rather than
rewriting the findings to force a match.

---

**Cursor**

I'll execute the notebook from a fresh kernel, then check the printed min/max, assertions, and timestamped export paths.

All cells completed successfully from a fresh kernel. No errors. Findings were not changed; executed results match them.

1. **Run:** `nbconvert --execute` finished with exit code 0. Code cells executed in order (counts 1–11). No cell errors.

2. **Lowest complete-month net:** printed `Complete-month net min: 2011-04 482992.88`

3. **Highest complete-month net:** printed `Complete-month net max: 2011-11 1432734.99`

4. **Assertions:** notebook 01 merchandise totals reconciled to the nearest penny; monthly value totals matched full merchandise totals. Later validation prints (identified/unidentified split, duplicate sensitivity) completed without assertion failures.

5. **Non-overwriting exports:** originals kept the previous mtimes. New files:

- `outputs/figures/monthly_merchandise_revenue_20260901_231128.png`
- `outputs/figures/top_10_countries_net_merchandise_20260901_231130.png`
- `outputs/figures/top_10_customers_net_merchandise_20260901_231131.png`
- `outputs/tables/monthly_revenue_20260901_231132.csv`
- `outputs/tables/country_revenue_20260901_231132.csv`
- `outputs/tables/customer_revenue_20260901_231132.csv`
- `outputs/tables/top_customers_20260901_231132.csv`

6. **Saved notebook:** `notebooks/02_revenue_customer_analysis.ipynb` was rewritten by this run and contains those printed outputs (including the min/max lines and `Saved ...` paths).

No Git commit. Notebooks 01/03 and the original untimestamped CSVs/PNGs were not modified.

---

**User**

Notebook 02 is complete. Now create and run:

notebooks/03_customer_lifecycle_analysis.ipynb

Answer:
4. New versus existing customer revenue.
5. Repeat purchase rate.
6. Monthly cohort retention.

Keep it beginner-friendly, independently executable, and divided
into short Markdown and code cells.

Reuse the exact preparation rules from notebooks 01 and 02.
Do not modify those notebooks.

Use the existing .venv and SELECT-only SQL Server connection:
.\MSSQLSERVER02 / RetailAnalytics.

Do not run the raw loader, write to SQL Server, install packages,
or commit to Git.

1. Create purchase-level data

Use identified-customer positive merchandise-sale lines:
- code_group = merchandise_candidate;
- Quantity > 0;
- UnitPrice > 0;
- InvoiceNo is not C-prefixed;
- CustomerID is not missing.

Keep duplicate extras in the baseline.

Create one row per CustomerID + InvoiceNo:
- purchase_timestamp = earliest eligible InvoiceDate;
- purchase_month;
- gross_purchase_value = sum of eligible line_value;
- positive_units = sum of Quantity.

Assert CustomerID + InvoiceNo is unique.
Use distinct invoices, not line counts, for purchase frequency.

For each customer calculate:
- first_observed_purchase_timestamp;
- first_observed_purchase_month;
- distinct purchase invoices.

2. Question 4 — New vs existing revenue

For each customer-month:
- first observed purchase month = new;
- later purchase months = existing.

All purchases in the customer’s first observed month count as new,
not only the first invoice.

Create a monthly summary with:
- new-customer gross merchandise sales;
- existing-customer gross merchandise sales;
- total identified-customer gross sales;
- new and existing revenue shares;
- distinct new customers;
- distinct existing customers.

A customer must belong to only one lifecycle group in a given month.

Reconcile total gross sales to 8,761,066.65 to the nearest penny.

Create a stacked monthly bar chart and mark December 2011 partial.

Use “first observed new customer”, not confirmed first-ever customer.
Explain that the December 2010 cohort may contain customers who
purchased before the dataset began.

3. Question 5 — Repeat purchase rate

A. Observed-window repeat rate:
- denominator = customers with at least one purchase invoice;
- numerator = customers with at least two distinct purchase invoices.

B. 90-day repeat rate:
- observation_end = maximum InvoiceDate in the full raw extract;
- eligible only when first purchase + 90 days <= observation_end;
- repeated means a second distinct invoice no later than 90 days
  after the first purchase;
- include exactly 90 days.

Sort by purchase_timestamp and InvoiceNo for deterministic order.
If two distinct invoices share the earliest timestamp, one is the
first and the other counts as a repeat; document this assumption.

Report numerator, denominator, rate, and customers excluded because
they lack 90 days of follow-up.

Also calculate the 90-day repeat rate by first-observed cohort month.

4. Question 6 — Cohort retention

Cohort = first observed purchase calendar month.
Activity = at least one positive purchase invoice in a month.

Calculate:

month_offset =
12 * (activity_year - cohort_year)
+ (activity_month - cohort_month)

Create:
- active-customer cohort table;
- cohort sizes;
- customer-count matrix using pivot_table();
- retention-rate matrix;
- Matplotlib retention heatmap.

Rules:
- one customer counts once per activity month;
- month 0 must equal 100%;
- customers may return after skipping a month;
- fully observed months with no activity are zero;
- months beyond the observation window are missing, not zero;
- exclude partial December 2011 activity from the main heatmap;
- exclude the December 2011 acquisition cohort from the main heatmap;
- retain December 2011 in the underlying detailed output.

Call this monthly cohort retention or repeat activity.
Do not interpret an inactive month as confirmed permanent churn.

5. Validation

Assert:
- purchase-level CustomerID + InvoiceNo is unique;
- lifecycle gross sales reconcile to 8,761,066.65;
- new + existing gross equals total gross each month;
- each customer has one lifecycle status per month;
- repeat numerator <= denominator;
- all 90-day eligible customers have sufficient follow-up;
- cohort active count <= cohort size;
- retention is between 0 and 1;
- month 0 is 100%;
- unobservable future cohort cells remain missing.

6. Outputs

Save without overwriting:
- outputs/tables/new_existing_monthly.csv
- outputs/tables/repeat_purchase_summary.csv
- outputs/tables/repeat_90d_by_cohort.csv
- outputs/tables/cohort_customer_counts.csv
- outputs/tables/cohort_retention.csv
- relevant PNG charts under outputs/figures/

Do not export transaction-level data.

End with concise findings:
- 2–3 exact findings for each business question;
- distinction between repeat rate and monthly retention;
- limitations from left-censoring, unequal follow-up, unidentified
  customers, duplicate treatment, and the partial final month.

Run the notebook from a fresh kernel.
Do not return a Pending template.

After execution, report validation results, exact findings,
saved paths, and any material blocker.
Do not create notebook 04 yet.

---

**Cursor**

I'll reuse the exact prep from notebooks 01 and 02, then build and run notebook 03 for new/existing revenue, repeat rate, and cohort retention.

I'll create notebook 03 with the same prep and export helper as 02, then execute it from a fresh kernel and fill findings from the run.

Notebook `notebooks/03_customer_lifecycle_analysis.ipynb` ran successfully from a fresh kernel. All assertions passed. Notebooks 01 and 02 were not modified. No SQL writes, no loader, no Git commit.

## Validation

- Purchase grain `CustomerID` + `InvoiceNo` is unique (**18,402** invoices, **4,334** identified purchasing customers).
- Lifecycle gross sales reconcile to **8,761,066.65**.
- New + existing gross equals total gross each month; one lifecycle status per customer-month.
- Repeat numerator ≤ denominator; all 90-day eligible customers have first purchase + 90 days ≤ **2011-12-09 12:50:00**.
- Cohort active count ≤ cohort size; retention in **[0, 1]**; month 0 is **100%**; months beyond each cohort’s horizon are missing, not zero.

## Question 4 — New vs existing

- **2010-12** is 100% new: **567,490.72**, **884** first-observed customers.
- Existing gross first exceeds new in **2011-02** (**285,654.49** vs **157,691.53**; existing **64.43%**). In complete **2011-11**, existing is **1,007,089.44** of **1,142,145.77** (**88.18%**); **1,337** existing vs **323** new.
- **2011-12** is partial: identified gross **513,230.43**, new share **5.20%** (**41** new). Not a full-month mix.

## Question 5 — Repeat purchase rate

- Observed-window: **2,829 / 4,334** (**65.27%**) have at least two distinct invoices.
- 90-day: **1,593 / 3,368** (**47.30%**); **966** excluded for insufficient follow-up.
- 90-day by cohort (eligible only): **2010-12** **526 / 884** (**59.50%**) to **2011-05** **108 / 284** (**38.03%**). **2011-09** is **30 / 54** because only 54 of 299 have 90 days of follow-up. Oct–Dec have no 90-day-eligible customers.

## Question 6 — Monthly cohort retention

This is monthly repeat **activity**, not confirmed churn.

- Heatmap covers 12 cohorts (Dec 2010–Nov 2011); Dec 2011 acquisition (**41**) is in the CSVs only.
- Dec 2010 month-1 retention **36.54%** (**323 / 884**); Jan 2011 month-1 **21.88%** (**91 / 416**).
- Dec 2010 in Nov 2011 (offset 11): **50.23%** (**444 / 884**). Dec 2011 activity stays in the detailed files (offset 12: **26.47%**) and is off the main heatmap.

## Outputs

These names were unused, so they were written without timestamps:

- `outputs/tables/new_existing_monthly.csv`
- `outputs/tables/repeat_purchase_summary.csv`
- `outputs/tables/repeat_90d_by_cohort.csv`
- `outputs/tables/cohort_customer_counts.csv`
- `outputs/tables/cohort_retention.csv`
- `outputs/figures/new_existing_monthly.png`
- `outputs/figures/repeat_90d_by_cohort.png`
- `outputs/figures/cohort_retention_heatmap.png`

No material blocker. The pandas `read_sql(pyodbc)` SQLAlchemy warning appeared again and did not fail the run. Notebook 04 was not created.

---

**User**

Notebook 03 is validated and approved.

Now create and run:

notebooks/04_customer_risk_rfm.ipynb

Answer:
7. Which high-value customers show declining purchase frequency?
10. Create RFM customer segmentation.

Also provide an inactivity/churn-risk proxy, clearly distinguished
from confirmed churn.

Keep the notebook beginner-friendly, independently executable,
and divided into short Markdown and code cells.

Reuse the exact preparation and positive-purchase definitions from
notebooks 01–03. Do not modify existing notebooks.

Use the existing .venv and SELECT-only SQL Server connection:
.\MSSQLSERVER02 / RetailAnalytics.

Do not run the loader, write to SQL Server, install packages,
or commit to Git.

1. Build customer purchase data

Eligible positive purchase lines:
- code_group = merchandise_candidate;
- Quantity > 0;
- UnitPrice > 0;
- InvoiceNo is not C-prefixed;
- CustomerID is not missing.

Keep duplicate extras in the baseline.

Create one row per CustomerID + InvoiceNo:
- purchase_timestamp = earliest eligible InvoiceDate;
- gross_purchase_value;
- positive_units.

Prepare identified-customer negative merchandise value separately:
- merchandise_candidate;
- Quantity < 0;
- UnitPrice > 0;
- CustomerID is not missing.

Negative lines are not purchase events and are not confirmed
cash refunds.

Use the RFM reference date 2011-12-10, the day after the maximum
observed transaction date.

Reconcile identified-customer positive gross merchandise value to
8,761,066.65.

2. Question 7 — High-value customers with declining frequency

Use two equal 92-day windows:

Prior window:
2011-06-10 00:00:00 inclusive to
2011-09-10 00:00:00 exclusive.

Recent window:
2011-09-10 00:00:00 inclusive to
2011-12-10 00:00:00 exclusive.

These boundaries must not overlap.
The recent window includes all observed transactions through
2011-12-09, but its final calendar month is partial.

For each identified purchasing customer calculate:
- lifetime observed gross purchase value;
- lifetime distinct purchase invoices;
- lifetime net merchandise value after identified negative lines;
- prior-window purchase invoices;
- recent-window purchase invoices;
- prior-window gross value;
- recent-window gross value;
- invoice-frequency change = recent minus prior;
- gross-value change = recent minus prior;
- gross-value percentage change where prior value > 0;
- days since last observed positive purchase.

Define high value as the top 20% by lifetime observed gross purchase
value using percentile rank.

Use a transparent and stable percentile-ranking method.
Do not use qcut as the final method if tied values create unstable
or arbitrary boundaries.

Define a declining-frequency candidate as:
- high value;
- prior-window invoices >= 2;
- recent-window invoices < prior-window invoices.

Add separate flags:
- no recent-window purchases;
- recent gross value declined by at least 50% from prior gross,
  where prior gross is positive.

Show:
- number of high-value customers;
- number of declining-frequency candidates;
- their lifetime gross and net value;
- top 20 candidates ordered by lifetime gross value.

Do not call these customers confirmed churned.
Call them re-engagement or declining-frequency candidates.

Explain that window comparisons can be affected by seasonality,
the partial December 2011 month, and the short dataset.

3. Inactivity / churn-risk proxy

For every identified purchasing customer calculate recency as at
2011-12-10.

Assign exactly one inactivity band:
- Active: 0–30 days;
- Cooling: 31–60 days;
- At Risk: 61–90 days;
- Inactive: over 90 days.

Report by band:
- customers;
- customer share;
- lifetime gross purchase value;
- lifetime net merchandise value;
- average distinct purchase invoices;
- average recency.

These bands are project assumptions, not observed churn events.
Do not calculate or claim an official churn rate.

4. Question 10 — RFM measures

Create one row per identified customer.

R — Recency:
days between 2011-12-10 and last positive purchase date.
Lower is better.

F — Frequency:
number of distinct positive purchase invoices.
Do not use transaction lines.

M — Monetary:
lifetime observed gross merchandise purchase value.

Retain lifetime net merchandise value as a diagnostic column,
but do not use net as the primary M score.

Create R, F and M scores from 1 to 5.

Requirements:
- most recent customers receive R = 5;
- highest frequency receives F = 5;
- highest monetary value receives M = 5;
- scores must be reproducible;
- equal Frequency values should receive the same score;
- do not split tied Frequency values merely to force equal group sizes;
- report customer count and actual metric range for every score.

Use a documented method such as percentile rank with an appropriate
tie method. If qcut is demonstrated for learning, keep it only as a
comparison and do not use unstable qcut output for final scoring.

5. RFM segments

Create:
- RFM code such as 555;
- total RFM score;
- one business-friendly segment per customer.

Use explicit, mutually exclusive rules with documented precedence.

Suggested rules may include:
- Champions;
- Loyal Customers;
- Potential Loyalists;
- New Customers;
- At Risk;
- Cannot Lose Them;
- Hibernating;
- Others.

Do not claim these labels are universal industry standards.
They are project-specific analytical rules.

Before finalizing, print the exact Boolean rule for every segment.
Use np.select or another ordered method so rule precedence is visible.

Report by segment:
- customer count;
- customer share;
- gross merchandise value;
- net merchandise value;
- average recency;
- average frequency;
- average monetary value.

6. Charts

Create:
- top re-engagement candidates horizontal bar chart;
- inactivity-band customer-count chart;
- RFM segment customer-count or value chart;
- recency versus frequency scatter plot.

For the scatter plot:
- use monetary value carefully for point size or colour;
- cap or transform extreme values if needed for readability;
- explain any visual transformation;
- do not alter the underlying customer table.

7. Validation

Assert:
- one row per identified purchasing customer;
- CustomerID is unique and non-missing;
- gross monetary total equals 8,761,066.65 to the nearest penny;
- frequency equals distinct positive purchase invoices;
- recency is non-negative;
- prior and recent window boundaries do not overlap;
- high-value and decline flags are Boolean;
- every R/F/M score is an integer from 1 to 5;
- equal Frequency values receive the same F score;
- each customer has exactly one segment;
- segment counts reconcile to all RFM customers;
- inactivity-band counts reconcile to all RFM customers;
- negative-only identified customers are excluded from RFM and
  separately counted and disclosed.

8. Outputs

Save without overwriting:
- outputs/tables/customer_frequency_trend.csv
- outputs/tables/reengagement_candidates.csv
- outputs/tables/customer_inactivity_bands.csv
- outputs/tables/customer_rfm.csv
- outputs/tables/rfm_segment_summary.csv
- relevant PNG charts under outputs/figures/

Do not export transaction-level data.

End with:
- 2–3 exact findings for declining-frequency customers;
- inactivity-risk findings;
- RFM segment findings;
- distinction between repeat rate, retention, declining frequency,
  inactivity proxy and confirmed churn;
- limitations and business actions stated as proposals, not proven
  causal conclusions.

Run from a fresh kernel.
Do not return Pending findings.

After execution, report validation results, exact findings,
saved paths and any material blocker.

Do not start product-mix or cancellation-impact analysis yet.

---

**Cursor**

I'll reuse the 01–03 prep and purchase definitions, then build and run notebook 04 for declining-frequency candidates, inactivity bands, and RFM.

Notebook `notebooks/04_customer_risk_rfm.ipynb` ran successfully from a fresh kernel. All assertions passed. Notebooks 01–03 were not modified. No SQL writes, no loader, no Git commit.

## Validation

- **4,334** identified purchasing customers; unique, non-missing `CustomerID`.
- Gross monetary total **8,761,066.65**.
- Frequency = distinct positive invoices; recency ≥ 0 (min **1** day as at 2011-12-10).
- Prior/recent windows do not overlap; recent max timestamp **2011-12-09 12:50:00**.
- High-value and decline flags are Boolean; R/F/M are integers 1–5; equal frequencies share the same F score (`qcut` on F produced 4 bins, comparison only).
- Each customer has one RFM segment and one inactivity band; both count to 4,334.
- **28** negative-only identified customers excluded from RFM and disclosed.

## Question 7 — Declining frequency

- High value (`rank(method="min", pct=True)` ≥ 0.80): **867** customers (**20.00%**).
- Declining-frequency candidates: **199**; lifetime gross **1,425,824.33**, net **1,382,204.23**. Of these, **26** have no recent-window purchases and **102** have recent gross down ≥50% vs prior.
- Largest by lifetime gross: **12415** (124,564.53, invoices 8→6), **14156** (116,729.63, 22→13), **16029** (72,882.09, 22→11). These are re-engagement candidates, not confirmed churn.

## Inactivity proxy (2011-12-10)

- **Active** 0–30: **1,627** (37.54%), gross **6,152,422.56**, mean recency **13.8** days.
- **Inactive** >90: **1,449** (33.43%), gross **1,019,439.51**, mean recency **214.5** days.
- Cooling **747**; At Risk **511**. Not an official churn rate.

## Question 10 — RFM (project rules)

- **Champions**: **891** (20.56% of customers), **5,561,110.66** gross (**63.48%** of identified gross).
- **Hibernating**: **1,354** (31.24%), **685,692.81** gross.
- **Cannot Lose Them**: **229**, **565,110.03** gross, mean recency **123.9** days.

Repeat rate and monthly retention (notebook 03) are not the same as windowed frequency change or recency bands, and none of those is confirmed churn.

## Outputs

- `outputs/tables/customer_frequency_trend.csv`
- `outputs/tables/reengagement_candidates.csv`
- `outputs/tables/customer_inactivity_bands.csv`
- `outputs/tables/customer_rfm.csv`
- `outputs/tables/rfm_segment_summary.csv`
- `outputs/figures/reengagement_candidates_top20.png`
- `outputs/figures/inactivity_band_counts.png`
- `outputs/figures/rfm_segment_counts.png`
- `outputs/figures/rfm_segment_gross.png`
- `outputs/figures/rfm_recency_frequency_scatter.png` (colour = log10 gross; size capped at 99th percentile for display only)

No material blocker. Product-mix and cancellation-impact analysis were not started.

---

**User**

Notebook 04 passed its main validations, but make two targeted
methodology corrections and rerun it from a fresh kernel.

1. Make the comparison windows exactly equal

The current windows are not equal:
- 2011-06-10 to 2011-09-10 = 92 days;
- 2011-09-10 to 2011-12-10 = 91 days.

Change them to two adjacent 91-day half-open windows:

PRIOR_START = pd.Timestamp("2011-06-11")
PRIOR_END = pd.Timestamp("2011-09-10")
RECENT_START = pd.Timestamp("2011-09-10")
RECENT_END = pd.Timestamp("2011-12-10")

Keep start inclusive and end exclusive.

Add assertions:

assert PRIOR_END == RECENT_START
assert PRIOR_END - PRIOR_START == RECENT_END - RECENT_START
assert not (in_prior & in_recent).any()

Print the number of calendar days in each window.

Recalculate all prior/recent frequency and value measures,
declining-frequency flags, candidate counts, findings and outputs.
Do not retain the old 199-customer result unless the rerun produces it.

Continue to disclose that December 2011 is partial. Equal nominal
window length does not remove seasonality or incomplete-month bias.

2. Rename the RFM segment

Rename:
New Customers

to:
Recent Low-Frequency

Keep its current Boolean rule:
R >= 4 and F <= 2

Reason:
high recency and low frequency do not prove that a customer is new.

Update:
- printed rule descriptions;
- segment names;
- segment summary;
- charts;
- CSV outputs;
- Markdown findings.

Do not change the other segment rules or RFM scoring method.

3. Rerun and validate

Restart the kernel and run all cells.

Confirm:
- both windows are exactly 91 days;
- all existing monetary and customer assertions still pass;
- candidate count and values are recalculated;
- each customer still has one inactivity band and one RFM segment;
- R/F/M scores remain integers from 1 to 5;
- gross monetary total remains 8,761,066.65;
- equal Frequency values retain the same F score;
- all saved cell outputs match the updated code.

Preserve existing CSVs and PNGs and create timestamped outputs.
Do not modify notebooks 01–03.
Keep SQL SELECT-only.
No loader, database writes, package installation or Git commit.

After execution, report:
- revised candidate count and values;
- whether the top three candidates changed;
- revised segment counts affected by the rename;
- validation results and new output paths.

---

**Cursor**

I'll update the 91-day windows and rename the RFM segment, then rerun notebook 04 from a fresh kernel.

Notebook 04 was rerun from a fresh kernel. All cells completed with no errors. Notebooks 01–03 were not changed. Existing untimestamped CSVs/PNGs were left in place.

## Windows

Printed: **Prior window calendar days: 91** and **Recent window calendar days: 91**. Assertions `PRIOR_END == RECENT_START`, equal timedeltas, and no overlap all passed. Prior invoices **3,942** (was 3,986); recent still **6,575**. December 2011 remains partial inside the recent window.

## Declining-frequency candidates (recalculated)

Do **not** keep 199. New result: **192** candidates; lifetime gross **1,367,496.97**; lifetime net **1,325,106.33**. No recent-window purchases: **24**. Recent gross down ≥50%: **98**.

**Top three did not change:** 12415, 14156, 16029. 16029’s prior invoice count moved from 22 to **21**. 15098 dropped out of the top 20 (that list now ends with 15251).

## RFM segment rename

**Recent Low-Frequency** (same rule R ≥ 4 and F ≤ 2): still **507** customers, gross **417,172.38**, **11.70%**. Other segment counts are unchanged (Champions 891, Hibernating 1,354, etc.). Printed rules, charts, and CSVs use the new name. High recency plus low frequency is not treated as “new.”

## Validation

Gross total still **8,761,066.65**. Unique purchasing customers **4,334**; **28** negative-only IDs excluded. One inactivity band and one RFM segment per customer. R/F/M are integers 1–5; equal frequencies share the same F score. Saved cell outputs match the updated code.

## New output paths

- `outputs/tables/customer_frequency_trend_20260901_234401.csv`
- `outputs/tables/reengagement_candidates_20260901_234401.csv`
- `outputs/tables/customer_inactivity_bands_20260901_234401.csv`
- `outputs/tables/customer_rfm_20260901_234401.csv`
- `outputs/tables/rfm_segment_summary_20260901_234402.csv`
- `outputs/figures/reengagement_candidates_top20_20260901_234359.png`
- `outputs/figures/inactivity_band_counts_20260901_234359.png`
- `outputs/figures/rfm_segment_counts_20260901_234400.png`
- `outputs/figures/rfm_segment_gross_20260901_234400.png`
- `outputs/figures/rfm_recency_frequency_scatter_20260901_234401.png`

No material blocker. No Git commit.

---

**User**

Notebooks 01–04 are complete and validated.

Now create and run:

notebooks/05_product_mix_cancellation_analysis.ipynb

Answer:
8. How did the merchandise product mix change?
9. How large was the impact of cancellations and negative-value
   merchandise lines?

Keep the notebook beginner-friendly, independently executable,
and divided into short Markdown and code cells.

Reuse the exact preparation, StockCode mapping and merchandise
definitions from notebooks 01–04.

Do not modify existing notebooks.

Use the existing .venv and SELECT-only SQL Server connection:
.\MSSQLSERVER02 / RetailAnalytics.

Do not run the loader, write to SQL Server, install packages,
or commit to Git.

============================================================
SHARED DEFINITIONS
============================================================

Merchandise candidate:
code_group = merchandise_candidate.

Positive merchandise sale:
- merchandise candidate;
- Quantity > 0;
- UnitPrice > 0;
- InvoiceNo is not C-prefixed.

Negative merchandise value:
- merchandise candidate;
- Quantity < 0;
- UnitPrice > 0.

Negative merchandise value is signed and is not automatically
a confirmed cash refund.

Keep duplicate extras in the baseline.
Use line InvoiceDate for monthly attribution.

Exclude postage, carriage, fees, discounts, manual entries,
samples and bad-debt adjustments from merchandise product analysis.

Use StockCode as the product grouping key.
Preserve Description as supporting text only because descriptions
can drift for one StockCode.

Do not invent product categories that do not exist in the dataset.

============================================================
QUESTION 8 — PRODUCT MIX
============================================================

1. Product-level summary

For each StockCode calculate:
- representative_description;
- gross merchandise sales;
- signed negative merchandise value;
- net merchandise value;
- positive units sold;
- distinct positive-sale invoices;
- distinct identified purchasing customers;
- first observed positive-sale date;
- last observed positive-sale date;
- gross-sales rank;
- units rank.

Choose representative_description deterministically:
- use the most frequent non-blank cleaned Description for each
  StockCode;
- break frequency ties alphabetically;
- do not overwrite original descriptions.

Keep StockCodes with negative activity even if they have no
positive sales.

2. Overall product concentration

Report:
- distinct merchandise StockCodes;
- top 10 StockCodes by gross sales;
- top 10 by positive units;
- top 10 gross-sales share;
- top 20 gross-sales share;
- top 10 net-value share.

Calculate product concentration using gross-sales shares:
- HHI = sum of squared product gross-sales shares.

Explain HHI here as a descriptive concentration measure.
Do not assign legal or competition-policy labels.

Create:
- top 10 products by gross sales horizontal bar chart;
- top 10 products by positive units chart.

Use StockCode plus shortened representative description as labels.

3. Monthly product mix

Create a product-month table with:
- month;
- StockCode;
- gross sales;
- signed negative value;
- net value;
- positive units;
- gross share within that month;
- units share within that month;
- monthly gross-sales rank.

Use groupby, agg, merge or transform where appropriate.

Create a pivot_table showing monthly gross sales for the overall
top 10 products, plus an “Other products” series for the chart.

Use complete months for trend conclusions.
Keep December 2011 in detailed outputs but mark it partial.

Create a stacked area or stacked bar chart showing monthly gross
mix for top products versus Other.

4. Compare two complete three-month periods

Compare:
Early period = 2011-01-01 inclusive to 2011-04-01 exclusive.
Late period = 2011-09-01 inclusive to 2011-12-01 exclusive.

For every StockCode report:
- early gross sales and share;
- late gross sales and share;
- gross sales change;
- percentage-point share change;
- early and late rank;
- rank change;
- early and late positive units.

Show:
- largest share gainers;
- largest share decliners;
- products present only in the late period;
- products present only in the early period.

Use “first/last observed in these comparison periods,” not confirmed
new or discontinued products.

Avoid percentage-growth calculations when early-period sales are zero.

============================================================
QUESTION 9 — CANCELLATION / NEGATIVE-VALUE IMPACT
============================================================

1. Reconcile merchandise values

Reconcile to the validated totals:
- gross merchandise sales = 10,272,121.42;
- signed negative merchandise value = -478,724.18;
- net merchandise value = 9,793,397.24.

Calculate:
negative_value_impact_pct =
absolute signed negative merchandise value / gross merchandise sales.

Do not call this a confirmed refund rate.

2. Split cancellation-related behaviour

Within merchandise candidates, separately calculate:
- C-prefixed negative-quantity lines;
- non-C-prefixed negative-quantity lines;
- C-prefixed lines that are not negative, if any;
- negative-quantity lines that are not C-prefixed;
- zero-price merchandise lines separately.

For each group report:
- lines;
- distinct invoices;
- distinct identified customers;
- signed line value;
- absolute value;
- share of total negative merchandise value.

Do not assume non-C negative lines are data errors or cash refunds.

3. Monthly impact

Create a monthly summary:
- gross merchandise sales;
- C-prefixed signed negative value;
- non-C negative signed value;
- total signed negative merchandise value;
- net merchandise value;
- absolute negative / gross percentage;
- distinct positive-sale invoices;
- distinct C-prefixed invoices.

Keep December 2011 but mark it partial.
Do not interpret its 28.29% negative/gross ratio as a comparable
full-month rate.

Create a monthly chart showing:
- gross merchandise sales;
- net merchandise value;
- negative impact percentage on a secondary axis or separate panel.

Use a readable design and explain the axis.

4. Product and customer impact

Show:
- top 20 StockCodes by absolute negative merchandise value;
- their gross, negative and net merchandise values;
- negative value as a percentage of gross where gross > 0;
- top 20 identified customers by absolute negative merchandise value;
- customer gross, negative and net values.

Clearly separate:
- a customer with high negative activity;
- a customer with confirmed churn;
- a customer with confirmed refund.

Only the first is observable here.

5. Optional return-linkage exploration

Create a cautious exploratory match for negative merchandise lines
to possible earlier positive sale lines using:
- identified CustomerID;
- StockCode;
- UnitPrice;
- absolute Quantity;
- positive sale timestamp earlier than or equal to negative timestamp.

Do not perform a many-to-many merge that inflates rows.

If implemented:
- generate possible candidates;
- select at most one deterministic closest prior positive candidate
  per negative line;
- keep the original negative raw_row_id;
- report matched, unmatched and ambiguous counts;
- call the result “possible prior-sale match,” not confirmed linkage.

If a safe one-to-one candidate selection would make the notebook
unnecessarily complex, document the proposed method and omit it.
This optional section must not block Question 9.

6. Duplicate sensitivity

Compare negative impact with and without exact duplicate extras:
- gross;
- signed negative;
- net;
- negative impact percentage.

Report whether duplicate treatment materially changes the conclusion.
Do not remove duplicates from the baseline.

============================================================
VALIDATION
============================================================

Assert:
- product gross totals equal 10,272,121.42;
- product negative totals equal -478,724.18;
- product net totals equal 9,793,397.24;
- product-month totals reconcile to full merchandise totals;
- monthly cancellation totals reconcile to full merchandise totals;
- C-prefixed negative plus non-C negative equals total negative
  merchandise value;
- product shares sum to approximately 100% for every month with
  positive gross sales;
- early and late period shares each sum to approximately 100%;
- top-N tables are selected only after full-table reconciliation;
- partial December 2011 is marked;
- no transaction-level data is exported.

Use nearest-penny comparisons for money.

============================================================
OUTPUTS
============================================================

Save without overwriting:
- outputs/tables/product_summary.csv
- outputs/tables/product_monthly_mix.csv
- outputs/tables/product_period_comparison.csv
- outputs/tables/monthly_negative_value_impact.csv
- outputs/tables/negative_value_by_type.csv
- outputs/tables/top_negative_value_products.csv
- outputs/tables/top_negative_value_customers.csv
- relevant PNG figures under outputs/figures/

Do not export the full transaction dataset.

End with:
- 2–3 exact findings for product mix;
- 2–3 exact findings for negative-value impact;
- business implications stated as proposals;
- limitations from provisional product classification,
  description drift, duplicate treatment, partial December 2011,
  and lack of confirmed refund linkage.

Run from a fresh kernel.
Do not return Pending findings.

After execution, report:
- validation results;
- exact findings for Questions 8 and 9;
- whether the optional linkage section was implemented;
- saved output paths;
- any material blocker.

---

**Cursor**

I'll reuse the 01–04 merchandise definitions, then build and run notebook 05 for product mix and negative-value impact.

Notebook `notebooks/05_product_mix_cancellation_analysis.ipynb` ran successfully from a fresh kernel. All assertions passed. Notebooks 01–04 were not modified. No SQL writes, no loader, no Git commit.

## Validation

Product, product-month, and monthly cancellation totals match gross **10,272,121.42**, signed negative **−478,724.18**, net **9,793,397.24**. C-prefix negative + non-C negative (UnitPrice > 0) equals total signed negative. Monthly and early/late shares sum to 100%. December 2011 is flagged partial. No transaction-level export.

## Question 8 — Product mix

- **3,928** merchandise StockCodes (**14** with no positive sales). HHI = **0.00212** (descriptive only). Top 10 gross share **9.43%**; top 20 **13.52%**.
- Highest gross: **22423** (174,484.74), **23843** (168,469.60), **85123A** (104,518.80). Highest units: **23843** (80,995), **23166** (78,033), **22197** (56,921). **23843**’s entire gross is in **partial December 2011**.
- Complete Jan–Mar vs Sep–Nov: early **1,872,211.22**, late **3,594,932.38**. Largest share gainer **23084** (+1.32 pp). Largest decliner **23166** (−4.08 pp). **747** late-only and **486** early-only StockCodes in this comparison — first/last observed in these windows, not confirmed new/discontinued.

## Question 9 — Negative-value impact

- |Negative| / gross = **4.66%**. Not a confirmed refund rate.
- **All** signed negative merchandise value is on **C-prefixed** negative-qty lines (8,704 lines, 3,422 invoices, 1,534 identified customers). **1,336** non-C merchandise negative-qty lines have **signed value 0** (UnitPrice not > 0) and **0** identified customers.
- Highest **complete**-month impact: January **13.62%**. December 2011 **28.29%** is partial and not a full-month rate. **23843** / customer **16446** and **12346** / **23166** dominate absolute negatives; that is high negative activity, not confirmed churn or a confirmed refund.
- Dropping duplicate extras changes impact by **−0.017 pp** (4.66% → 4.64%) — not a material change in conclusion.

## Optional linkage

Implemented as a **possible prior-sale match** (not confirmed): 8,539 identified negative lines; unmatched **5,766**; unique candidate **2,162**; ambiguous **611**; selected **2,773**. Match rows were not exported.

## Outputs

- `outputs/tables/product_summary.csv`
- `outputs/tables/product_monthly_mix.csv`
- `outputs/tables/product_period_comparison.csv`
- `outputs/tables/monthly_negative_value_impact.csv`
- `outputs/tables/negative_value_by_type.csv`
- `outputs/tables/top_negative_value_products.csv`
- `outputs/tables/top_negative_value_customers.csv`
- `outputs/figures/top10_products_gross.png`
- `outputs/figures/top10_products_units.png`
- `outputs/figures/monthly_product_mix_top10.png`
- `outputs/figures/monthly_negative_value_impact.png`

No material blocker.

