from pathlib import Path

import pandas as pd
import pyodbc


# Existing working SQL Server connection configuration.
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

EXPECTED_COLUMNS = [
    "InvoiceNo",
    "StockCode",
    "Description",
    "Quantity",
    "InvoiceDate",
    "UnitPrice",
    "CustomerID",
    "Country",
]
EXCEL_PATH = Path(__file__).resolve().parent.parent / "data" / "raw" / "Online Retail.xlsx"
BATCH_SIZE = 10_000


def _as_source_string(value):
    """Keep identifier values as strings, without a trailing '.0' from Excel floats."""
    if value is None or pd.isna(value):
        return None
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    text = str(value)
    if text.endswith(".0"):
        stem = text[:-2]
        if stem.lstrip("-").isdigit():
            return stem
    return text


def _to_python(value):
    """Convert pandas/NumPy values to pyodbc-safe Python types (None for SQL NULL)."""
    if value is None or pd.isna(value):
        return None
    if isinstance(value, pd.Timestamp):
        return value.to_pydatetime()
    # fast_executemany does not accept NumPy scalars (e.g. int64, float64).
    if hasattr(value, "item") and not isinstance(value, (bytes, str)):
        return value.item()
    return value


print(f"Starting load from {EXCEL_PATH}")

# Read the source Excel file; keep every row (no business cleaning).
df = pd.read_excel(EXCEL_PATH)
excel_row_count = len(df)

# Fail fast if the file schema is not the expected UCI Online Retail columns.
if list(df.columns) != EXPECTED_COLUMNS:
    raise ValueError(
        "Unexpected Excel columns. "
        f"Expected {EXPECTED_COLUMNS}, found {list(df.columns)}."
    )

# Align pandas dtypes with SQL Server only; do not drop cancellations, refunds,
# null CustomerIDs, or duplicates.
df["InvoiceNo"] = df["InvoiceNo"].map(_as_source_string)
df["StockCode"] = df["StockCode"].map(_as_source_string)
# Description is NOT NULL in SQL Server; keep missing Excel text as empty string.
df["Description"] = df["Description"].where(df["Description"].notna(), "")
df["Quantity"] = df["Quantity"].astype(int)
df["InvoiceDate"] = pd.to_datetime(df["InvoiceDate"])
df["UnitPrice"] = pd.to_numeric(df["UnitPrice"])
df["CustomerID"] = df["CustomerID"].map(_as_source_string)
df["Country"] = df["Country"].astype(str)

insert_sql = """
INSERT INTO raw.online_retail (
    InvoiceNo,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    UnitPrice,
    CustomerID,
    Country
)
VALUES (?, ?, ?, ?, ?, ?, ?, ?);
"""

connection = None
cursor = None
try:
    connection = pyodbc.connect(connection_string)
    cursor = connection.cursor()

    # Load only into an empty raw table so this script is not accidentally re-run.
    cursor.execute("SELECT COUNT(*) FROM raw.online_retail;")
    existing_row_count = cursor.fetchone()[0]
    if existing_row_count:
        raise RuntimeError(
            "raw.online_retail already contains "
            f"{existing_row_count} rows. Stopped without inserting."
        )

    # Batch insert; SQL Server supplies raw_row_id, source_file, and loaded_at.
    cursor.fast_executemany = True
    for start in range(0, excel_row_count, BATCH_SIZE):
        chunk = df.iloc[start : start + BATCH_SIZE]
        rows = [
            tuple(_to_python(value) for value in record)
            for record in chunk.itertuples(index=False, name=None)
        ]
        cursor.executemany(insert_sql, rows)
        loaded_so_far = start + len(chunk)
        print(f"Loaded {loaded_so_far:,} / {excel_row_count:,} rows")

    cursor.execute("SELECT COUNT(*) FROM raw.online_retail;")
    sql_row_count = cursor.fetchone()[0]
    if sql_row_count != excel_row_count:
        raise RuntimeError(
            "Row count mismatch after load: "
            f"Excel={excel_row_count}, SQL Server={sql_row_count}."
        )

    connection.commit()
    print(
        f"Loaded {sql_row_count} rows into raw.online_retail "
        f"(matches Excel row count {excel_row_count})."
    )
except Exception:
    if connection is not None:
        connection.rollback()
    raise
finally:
    if cursor is not None:
        cursor.close()
    if connection is not None:
        connection.close()
