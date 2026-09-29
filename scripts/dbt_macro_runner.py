"""
Generic runner for dbt macros (`dbt run-operation`).

This is intentionally not tied to a single macro. Pass the macro name as the
first argument so future DDL or utility macros can reuse the same entrypoint
without a new script.

Environment:
    Loads `.env` from the repo root and sets `DBT_PROFILES_DIR` to that root
    so `profiles.yml` can resolve `env_var(...)` credentials.

Examples:
    python scripts/dbt_macro_runner.py create_source_tables
    python scripts/dbt_macro_runner.py some_macro --args '{"key": "value"}'
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path

from dotenv import load_dotenv

# Repo root (parent of `scripts/`). dbt must run with this as cwd so
# `dbt_project.yml` and `macros/` are discovered.
ROOT = Path(__file__).resolve().parents[1]


def dbt_executable() -> Path:
    """
    Locate the dbt CLI next to the current Python interpreter.

    Using the venv's `python.exe` sibling (`dbt.exe` on Windows, `dbt` elsewhere)
    avoids `python -m dbt`, which is not a valid entrypoint for this install.
    """
    dbt = Path(sys.executable).with_name("dbt.exe")
    if not dbt.exists():
        dbt = Path(sys.executable).with_name("dbt")
    return dbt


def parse_args() -> argparse.Namespace:
    """Parse the macro name and optional dbt `--args` payload."""
    parser = argparse.ArgumentParser(description="Run a dbt macro via run-operation.")
    parser.add_argument("macro", help="Name of the dbt macro to run")
    parser.add_argument(
        "--args",
        dest="macro_args",
        help="Optional YAML/JSON args string passed to dbt --args",
    )
    return parser.parse_args()


def main() -> None:
    """Load env, point dbt at this project's profiles.yml, then run the macro."""
    args = parse_args()
    load_dotenv(ROOT / ".env")
    # profiles.yml lives in the repo so CI/local runs do not depend on ~/.dbt.
    os.environ["DBT_PROFILES_DIR"] = str(ROOT)

    command = [str(dbt_executable()), "run-operation", args.macro]
    if args.macro_args:
        # Forwarded unchanged; dbt parses YAML/JSON for macro kwargs.
        command.extend(["--args", args.macro_args])

    subprocess.check_call(command, cwd=ROOT)


if __name__ == "__main__":
    main()
