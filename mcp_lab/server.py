from mcp.server import MCPServer


mcp = MCPServer("Retail MCP Lab")


@mcp.tool()
def get_project_summary() -> str:
    """Return a short summary of the Retail Transaction Analytics project."""
    return (
        "Retail Transaction Analytics analyses the UCI Online Retail dataset "
        "using Python, pandas, SQL Server, and Jupyter notebooks. "
        "The project covers revenue, customer lifecycle, retention, RFM, "
        "product mix, and cancellations."
    )


if __name__ == "__main__":
    mcp.run()