from pathlib import Path

import pandas as pd
from mcp.server import MCPServer


mcp = MCPServer(name="Retail MCP Lab")

PROJECT_ROOT = Path(__file__).resolve().parents[1]
TOP_CUSTOMERS_CSV = PROJECT_ROOT / "outputs" / "tables" / "top_customers.csv"


@mcp.tool()
def get_project_summary() -> str:
    """Return a short summary of the Retail Transaction Analytics project."""
    return (
        "Retail Transaction Analytics analyses the UCI Online Retail dataset "
        "using Python, pandas, SQL Server, and Jupyter notebooks. "
        "The project covers revenue, customer lifecycle, retention, RFM, "
        "product mix, and cancellations."
    )
@mcp.tool()
def get_project_topics(limit: int = 3) -> list[str]:
    """Return the main analysis topics covered by the retail project."""
    topics = [
        "Revenue analysis",
        "Customer lifecycle",
        "Retention",
        "RFM segmentation",
        "Customer risk",
        "Product mix",
        "Cancellations",
    ]

    return topics[:limit]

@mcp.tool()
def get_top_customers(n: int = 5) -> list[dict]:
    """Return the top customers ranked by gross merchandise sales."""
    if n < 1 or n > 20:
        raise ValueError("n must be between 1 and 20")

    df = pd.read_csv(TOP_CUSTOMERS_CSV)

    top = (
        df.sort_values("gross_merchandise_sales", ascending=False)
        .head(n)
    )

    return [
        {
            "customer_id": int(row.CustomerID),
            "gross_merchandise_sales": round(
                float(row.gross_merchandise_sales), 2
            ),
            "positive_sale_invoices": int(row.positive_sale_invoices),
            "positive_merchandise_units": float(
                row.positive_merchandise_units
            ),
        }
        for row in top.itertuples(index=False)
    ]

@mcp.resource(
    "retail://project/overview",
    mime_type="text/plain",
)
def project_overview() -> str:
    """Provide an overview of the Retail Transaction Analytics project."""
    return (
        "Retail Transaction Analytics uses the UCI Online Retail dataset. "
        "The project includes raw-data profiling, revenue analysis, "
        "customer lifecycle and retention, RFM segmentation, customer risk, "
        "product mix, and cancellation analysis."
    )

@mcp.prompt()
def analyze_retail_metric(metric: str) -> str:
    """Create a prompt for analyzing a retail business metric."""
    return (
        f"Analyze the retail metric '{metric}'. "
        "Explain the business meaning, relevant calculation logic, "
        "important data-quality caveats, and the most useful visualisation."
    )

if __name__ == "__main__":
    mcp.run()