from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path
import json
import re
import time

import pyodbc


# Working SQL Server connection (same settings as the load script; this file
# does not import or run 01_load_raw_data.py).
server = r".\MSSQLSERVER02"
database = "RetailAnalytics"
driver = "ODBC Driver 18 for SQL Server"

connection_string = (
    f"DRIVER={{{driver}}};"
    f"SERVER={server};"
    f"DATABASE={database};"
    "Trusted_Connection=yes;"
    "TrustServerCertificate=yes;"
)

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SQL_PATH = PROJECT_ROOT / "sql" / "02_raw_data_profiling.sql"
# Execute only these section prefixes (Phases 4–6). Do not rerun 0–3.
PHASE_PREFIXES = ("4.", "5.", "6.")
OUTPUT_BASE = PROJECT_ROOT / "outputs" / "profiling" / "phase_4_6"

FORBIDDEN = re.compile(
    r"\b(INSERT|UPDATE|DELETE|MERGE|TRUNCATE|DROP|ALTER|CREATE|GRANT|REVOKE|"
    r"SELECT\s+INTO|EXEC|EXECUTE)\b",
    re.IGNORECASE,
)
SECTION_HEADER = re.compile(r"^--\s+(\d+\.\d+)\b")
GO_LINE = re.compile(r"^GO\s*$", re.IGNORECASE)


def _json_default(value):
    if isinstance(value, Decimal):
        return str(value)
    if isinstance(value, datetime):
        return value.isoformat(sep=" ")
    raise TypeError(f"Cannot serialize {type(value)!r}")


def parse_labelled_queries(sql_text: str) -> list[tuple[str, str]]:
    """Split on GO; pair each SELECT with its -- N.N comment. Skip USE."""
    queries: list[tuple[str, str]] = []
    current_section: str | None = None
    current_sql: list[str] = []
    section_occurrence: dict[str, int] = {}
    in_block_comment = False

    def flush():
        nonlocal current_sql, current_section
        text = "\n".join(current_sql).strip()
        current_sql = []
        if not text or text.upper().startswith("USE "):
            return
        if FORBIDDEN.search(text):
            raise RuntimeError(
                f"Refusing to run non-read-only SQL near section {current_section}: {text[:200]}"
            )
        if current_section is None:
            raise RuntimeError(f"SELECT without a section label: {text[:200]}")
        section_occurrence[current_section] = section_occurrence.get(current_section, 0) + 1
        occ = section_occurrence[current_section]
        label = current_section if occ == 1 else f"{current_section}_examples"
        queries.append((label, text.rstrip(";")))

    for raw_line in sql_text.splitlines():
        line = raw_line.rstrip()
        if GO_LINE.match(line.strip()):
            flush()
            current_section = None
            continue
        header = SECTION_HEADER.match(line.strip())
        if header:
            flush()
            current_section = header.group(1)
            continue
        stripped = line.strip()
        if in_block_comment:
            if "*/" in stripped:
                in_block_comment = False
            continue
        if stripped.startswith("/*"):
            if "*/" not in stripped:
                in_block_comment = True
            continue
        if stripped.startswith("--"):
            continue
        if not stripped:
            continue
        current_sql.append(line)
    flush()
    return queries


def fetch_all_result_sets(cursor) -> list[tuple[list[str], list[tuple]]]:
    """Collect every result set from the current execute, including nextset()."""
    sets: list[tuple[list[str], list[tuple]]] = []
    while True:
        if cursor.description is not None:
            columns = [col[0] for col in cursor.description]
            rows = cursor.fetchall()
            sets.append((columns, rows))
        if not cursor.nextset():
            break
    return sets


def resolve_output_dir(base: Path) -> Path:
    """Use base if empty of result files; otherwise a timestamped subfolder."""
    base.mkdir(parents=True, exist_ok=True)
    existing = [p for p in base.iterdir() if p.is_file()]
    if not existing:
        return base
    stamped = base / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    stamped.mkdir(parents=True, exist_ok=False)
    print(f"Existing results in {base}; writing to {stamped}")
    return stamped


def main() -> None:
    output_dir = resolve_output_dir(OUTPUT_BASE)

    sql_text = SQL_PATH.read_text(encoding="utf-8")
    queries = [
        (label, statement)
        for label, statement in parse_labelled_queries(sql_text)
        if any(label.startswith(prefix) for prefix in PHASE_PREFIXES)
    ]
    if not queries:
        raise SystemExit("No Phase 4–6 queries found in the SQL file.")

    # Measures the end-to-end profiling runtime.
    started = time.perf_counter()
    run_started_utc = datetime.now(timezone.utc).isoformat()

    connection = None
    cursor = None
    manifest_queries: list[dict] = []
    try:
        connection = pyodbc.connect(connection_string, timeout=30)
        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON;")

        for label, statement in queries:
            query_started = time.perf_counter()
            status = "completed"
            error = None
            result_files: list[str] = []
            result_row_counts: list[int] = []
            try:
                cursor.execute(statement)
                result_sets = fetch_all_result_sets(cursor)
                if not result_sets:
                    status = "completed_no_result_set"
                for set_index, (columns, rows) in enumerate(result_sets, start=1):
                    payload = {
                        "sql_section": label,
                        "result_set_index": set_index,
                        "source_sql_file": str(SQL_PATH),
                        "columns": columns,
                        "row_count": len(rows),
                        "rows": [
                            dict(zip(columns, tuple(None if v is None else v for v in row)))
                            for row in rows
                        ],
                    }
                    suffix = "" if set_index == 1 else f"_set{set_index}"
                    out_path = output_dir / f"{label}{suffix}.json"
                    out_path.write_text(
                        json.dumps(payload, indent=2, default=_json_default),
                        encoding="utf-8",
                    )
                    result_files.append(out_path.name)
                    result_row_counts.append(len(rows))
            except Exception as exc:
                status = "failed"
                error = f"{type(exc).__name__}: {exc}"
                print(f"FAILED {label}: {error}")

            elapsed_s = round(time.perf_counter() - query_started, 3)
            manifest_queries.append(
                {
                    "sql_section": label,
                    "status": status,
                    "error": error,
                    "elapsed_seconds": elapsed_s,
                    "result_files": result_files,
                    "result_row_counts": result_row_counts,
                }
            )
            if status == "completed":
                print(f"OK {label} ({elapsed_s}s) -> {', '.join(result_files)}")
            elif status == "completed_no_result_set":
                print(f"OK {label} ({elapsed_s}s) no result set")
    finally:
        if cursor is not None:
            cursor.close()
        if connection is not None:
            connection.close()

    total_s = round(time.perf_counter() - started, 3)
    manifest = {
        "source_sql_file": str(SQL_PATH),
        "output_directory": str(output_dir),
        "phase_prefixes": list(PHASE_PREFIXES),
        "run_started_utc": run_started_utc,
        "total_elapsed_seconds": total_s,
        "server": server,
        "database": database,
        "query_count": len(queries),
        "queries": manifest_queries,
    }
    (output_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2),
        encoding="utf-8",
    )
    print(f"Finished in {total_s}s. Manifest: {output_dir / 'manifest.json'}")


if __name__ == "__main__":
    main()
