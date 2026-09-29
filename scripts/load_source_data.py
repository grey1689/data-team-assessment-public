"""
Load a single CSV file into a single Postgres table.

Intended to run after source tables exist (created by dbt macros). Each
invocation truncates the destination table and COPY-loads the given file so
reruns are idempotent and one source file maps to one table.

The destination schema comes from `POSTGRES_SCHEMA` (default `proxy`). Table
names are not inferred from the filename; both path and table are required
arguments so loaders stay explicit.

Example:
    python scripts/load_source_data.py data/games.csv games_proxy
"""

import argparse
import re
import sys
from pathlib import Path

# Allow `from db import ...` when this file is executed as a script from
# the repo root (Python does not put `scripts/` on sys.path automatically).
sys.path.insert(0, str(Path(__file__).resolve().parent))

from db import ROOT, get_conn, schema_name

# Only unquoted identifiers are interpolated into SQL. This blocks COPY/TRUNCATE
# injection via the table-name argument.
IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def parse_args() -> argparse.Namespace:
    """Require one CSV path and one destination table name."""
    parser = argparse.ArgumentParser(
        description="Load one CSV file into one Postgres table."
    )
    parser.add_argument("filename", help="Path to the CSV file")
    parser.add_argument("table", help="Destination Postgres table name")
    return parser.parse_args()


def qualify(schema: str, table: str) -> str:
    """
    Build `schema.table` after validating both parts as SQL identifiers.

    Raises:
        ValueError: if schema or table contains characters unsafe to interpolate.
    """
    if not IDENTIFIER.match(schema) or not IDENTIFIER.match(table):
        raise ValueError("schema and table must be simple SQL identifiers")
    return f"{schema}.{table}"


def load_csv(cur, csv_path: Path, qualified: str) -> int:
    """
    Replace all rows in `qualified` with the contents of `csv_path`.

    Uses Postgres COPY with CSV HEADER so the first row is treated as column
    names and must match the table definition. Returns the post-load row count.
    """
    cur.execute(f"truncate table {qualified}")
    with csv_path.open("r", encoding="utf-8") as handle:
        cur.copy_expert(
            f"copy {qualified} from stdin with csv header",
            handle,
        )
    cur.execute(f"select count(*) from {qualified}")
    return cur.fetchone()[0]


def main() -> None:
    """Resolve the CSV path, open a connection, load, and print a row-count summary."""
    args = parse_args()
    csv_path = Path(args.filename)
    # Relative paths are interpreted from the repo root, not the current cwd,
    # so `data/games.csv` works from any working directory.
    if not csv_path.is_absolute():
        csv_path = (ROOT / csv_path).resolve()
    if not csv_path.is_file():
        raise FileNotFoundError(f"CSV not found: {csv_path}")

    schema = schema_name()
    qualified = qualify(schema, args.table)
    conn = get_conn()
    try:
        # `with conn` commits on success and rolls back on exception.
        with conn:
            with conn.cursor() as cur:
                count = load_csv(cur, csv_path, qualified)
                print(f"loaded {count} rows into {qualified} from {csv_path}")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
