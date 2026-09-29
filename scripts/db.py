"""
Shared Postgres connection helpers for local load scripts.

Credentials and connection settings are read from the project-root `.env`
file so scripts never hard-code secrets. Callers should import `get_conn`
and `schema_name` rather than opening connections themselves.
"""

import os
from pathlib import Path

import psycopg2
from dotenv import load_dotenv

# Repo root is one level above `scripts/`. Using this path keeps `.env`
# resolution stable regardless of the working directory used to invoke a script.
ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / ".env")


def schema_name() -> str:
    """
    Return the landing-zone schema for source tables.

    Defaults to `proxy` so loaders and dbt share the same target when
    `POSTGRES_SCHEMA` is omitted from `.env`.
    """
    return os.environ.get("POSTGRES_SCHEMA", "proxy")


def get_conn():
    """
    Open a new psycopg2 connection to `zbd_development` (or whatever
    `POSTGRES_DB` is set to). Uses POSTGRES_USER from `.env` (the
    application role `zbd_app` after provisioning).

    The caller owns commit/rollback/close. Required env vars:
    POSTGRES_HOST, POSTGRES_PORT, POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB.
    """
    return psycopg2.connect(
        host=os.environ["POSTGRES_HOST"],
        port=os.environ["POSTGRES_PORT"],
        user=os.environ["POSTGRES_USER"],
        password=os.environ["POSTGRES_PASSWORD"],
        dbname=os.environ["POSTGRES_DB"],
    )


def get_admin_conn():
    """
    Superuser (or owner) connection for role provisioning only.

    Uses POSTGRES_ADMIN_USER / POSTGRES_ADMIN_PASSWORD when set, otherwise
    the same credentials as get_conn().
    """
    return psycopg2.connect(
        host=os.environ["POSTGRES_HOST"],
        port=os.environ["POSTGRES_PORT"],
        user=os.environ.get("POSTGRES_ADMIN_USER", os.environ["POSTGRES_USER"]),
        password=os.environ.get(
            "POSTGRES_ADMIN_PASSWORD", os.environ["POSTGRES_PASSWORD"]
        ),
        dbname=os.environ["POSTGRES_DB"],
    )
