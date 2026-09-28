#!/usr/bin/env python3
"""A PostgreSQL database of its own for each real-suite run, and for each database the scorer builds.

usage: db.py create <admin-url> <name>  -> prints the backend's settings for it, KEY=VALUE per line
       db.py drop <admin-url> <name>

<admin-url> is postgresql://<user>[:<password>]@<host>[:<port>]/<db>, reached over TCP: the backend
connects to the same host. Its user needs CREATEDB and CREATEROLE. The new role can log in and
owns its database, nothing more: no superuser, no CREATEDB, no CREATEROLE, and no other role may
connect to its database. <name> is lowercase letters, digits and underscores; the role and the
database both take it. psql does the work (PG_BIN, else PATH), with the admin password in its
environment rather than on its command line. The settings name the database and a first superuser
for the app, with values drawn fresh for every database.
"""

import os
import re
import secrets
import shutil
import subprocess
import sys
from urllib.parse import unquote, urlsplit, urlunsplit

NAME = re.compile(r"^[a-z][a-z0-9_]{0,62}$")


def psql():
    d = os.environ.get("PG_BIN", "")
    if d and os.path.exists(os.path.join(d, "psql")):
        return os.path.join(d, "psql")
    found = shutil.which("psql")
    if not found:
        sys.exit("db.py: psql not found (set PG_BIN)")
    return found


def run_sql(url, *statements):
    """Each statement on its own: CREATE and DROP DATABASE refuse to run inside a transaction."""
    where = urlsplit(url)
    env = dict(os.environ)
    if where.password is not None:
        env["PGPASSWORD"] = unquote(where.password)
        host = where.netloc.rsplit("@", 1)[1]
        user = where.netloc.rsplit("@", 1)[0].split(":", 1)[0]
        url = urlunsplit(where._replace(netloc=f"{user}@{host}"))
    cmd = [psql(), url, "-X", "-q", "-v", "ON_ERROR_STOP=1"]
    for s in statements:
        cmd += ["-c", s]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=60, env=env)
    if r.returncode:
        sys.exit(f"db.py: {r.stderr.strip() or 'psql failed'}")


def create(url, name):
    where = urlsplit(url)
    if not where.hostname:
        sys.exit(
            "db.py: the admin URL needs a TCP host, which the backend connects to as well"
        )
    secret = secrets.token_hex(16)  # [0-9a-f] only, so it needs no quoting in SQL
    run_sql(
        url,
        f"CREATE ROLE {name} LOGIN PASSWORD '{secret}' NOSUPERUSER NOCREATEDB NOCREATEROLE",
        f"CREATE DATABASE {name} OWNER {name} ENCODING 'UTF8' TEMPLATE template0",
        f"REVOKE CONNECT, TEMPORARY ON DATABASE {name} FROM PUBLIC",
    )
    settings = {
        "PROJECT_NAME": "bench",
        "ENVIRONMENT": "local",
        "POSTGRES_SERVER": where.hostname,
        "POSTGRES_PORT": str(where.port or 5432),
        "POSTGRES_USER": name,
        "POSTGRES_PASSWORD": secret,
        "POSTGRES_DB": name,
        "FIRST_SUPERUSER": "admin@example.com",
        "FIRST_SUPERUSER_PASSWORD": secrets.token_hex(12),
        "SECRET_KEY": secrets.token_hex(32),
    }
    for k, v in settings.items():
        print(f"{k}={v}")


def drop(url, name):
    run_sql(
        url,
        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)",
        f"DROP ROLE IF EXISTS {name}",
    )


def main(argv):
    if len(argv) != 3 or argv[0] not in ("create", "drop"):
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    verb, url, name = argv
    if not NAME.match(name):
        sys.exit(f"db.py: bad name {name!r}")
    (create if verb == "create" else drop)(url, name)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
