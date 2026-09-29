"""
Create least-privilege role `zbd_app` and grant it on proxy/clean/canonical.

Run once as a superuser (POSTGRES_ADMIN_* or current POSTGRES_*). Writes
POSTGRES_USER=zbd_app and a new POSTGRES_PASSWORD into `.env`, preserving
admin credentials as POSTGRES_ADMIN_*. Does not print secrets.
"""

import os
import re
import secrets
import string
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from dotenv import load_dotenv

from db import ROOT, get_admin_conn

APP_ROLE = "zbd_app"
SCHEMAS = ("proxy", "clean", "canonical")
IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def _password() -> str:
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(32))


def _ident(value: str, label: str) -> str:
    if not IDENTIFIER.match(value):
        raise ValueError(f"{label} must be a simple SQL identifier")
    return value


def _upsert_env(path: Path, updates: dict) -> None:
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    keys_seen = set()
    out = []
    for line in lines:
        if not line.strip() or line.lstrip().startswith("#") or "=" not in line:
            out.append(line)
            continue
        key = line.split("=", 1)[0]
        if key in updates:
            out.append(f"{key}={updates[key]}")
            keys_seen.add(key)
        else:
            out.append(line)
    for key, value in updates.items():
        if key not in keys_seen:
            out.append(f"{key}={value}")
    path.write_text("\n".join(out) + "\n", encoding="utf-8")


def main() -> None:
    load_dotenv(ROOT / ".env")
    admin_user = _ident(
        os.environ.get("POSTGRES_ADMIN_USER", os.environ["POSTGRES_USER"]),
        "admin user",
    )
    admin_password = os.environ.get(
        "POSTGRES_ADMIN_PASSWORD", os.environ["POSTGRES_PASSWORD"]
    )
    existing_app_pw = (
        os.environ.get("POSTGRES_PASSWORD")
        if os.environ.get("POSTGRES_USER") == APP_ROLE
        else None
    )
    app_password = os.environ.get("ZBD_APP_PASSWORD") or existing_app_pw or _password()
    dbname = _ident(os.environ["POSTGRES_DB"], "database")

    conn = get_admin_conn()
    conn.autocommit = True
    try:
        with conn.cursor() as cur:
            cur.execute("select 1 from pg_roles where rolname = %s", (APP_ROLE,))
            exists = cur.fetchone() is not None
            if exists:
                cur.execute(
                    f"alter role {APP_ROLE} with login password %s",
                    (app_password,),
                )
            else:
                cur.execute(
                    f"create role {APP_ROLE} login password %s",
                    (app_password,),
                )
            cur.execute(f"grant connect, temporary on database {dbname} to {APP_ROLE}")
            for schema in SCHEMAS:
                cur.execute(f"grant usage, create on schema {schema} to {APP_ROLE}")
                cur.execute(
                    f"grant all privileges on all tables in schema {schema} to {APP_ROLE}"
                )
                cur.execute(
                    f"grant all privileges on all sequences in schema {schema} to {APP_ROLE}"
                )
                cur.execute(
                    f"alter default privileges for role {admin_user} in schema {schema} "
                    f"grant all on tables to {APP_ROLE}"
                )
                cur.execute(
                    """
                    select format(
                        'alter table %%I.%%I owner to %%I',
                        n.nspname,
                        c.relname,
                        %s
                    )
                    from pg_class c
                    join pg_namespace n on n.oid = c.relnamespace
                    where n.nspname = %s
                      and c.relkind in ('r', 'p', 'v', 'm')
                    """,
                    (APP_ROLE, schema),
                )
                for (stmt,) in cur.fetchall():
                    cur.execute(stmt)
    finally:
        conn.close()

    _upsert_env(
        ROOT / ".env",
        {
            "POSTGRES_ADMIN_USER": admin_user,
            "POSTGRES_ADMIN_PASSWORD": admin_password,
            "POSTGRES_USER": APP_ROLE,
            "POSTGRES_PASSWORD": app_password,
        },
    )
    print(f"role {APP_ROLE} granted on {dbname}; .env application user updated", flush=True)


if __name__ == "__main__":
    main()
