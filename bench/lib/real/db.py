#!/usr/bin/env python3
"""A PostgreSQL database of its own for each real-suite run, and for each database the scorer builds.

usage: db.py name <run-dir>   -> the run's database name, derived from the run dir's path, so that
                                 no file the agent can write decides what is dropped
       db.py create <name>    -> prints the backend's settings for it, KEY=VALUE per line
       db.py drop <name>
       db.py exists <name>    -> exits 0 if the database exists, 1 if not
       db.py check-auth       -> exits 1 if the server lets its admin, or postgres, in with no password
       db.py ping             -> exits 0 if the admin can reach the server, 1 if not
env:   PG_URL  the admin URL, postgresql://<user>[:<password>]@<host>[:<port>]/<db>, reached over TCP:
               the backend connects to the same host. Its user needs CREATEDB and CREATEROLE.

The admin URL is read from the environment and never put on a command line, which every process on
the machine can read; psql gets its password in its environment (PGPASSWORD, and no password file)
and the SQL, a new role's password included, on its stdin. A name is a run's (r and 12 hex digits)
or a scorer's (s, 10 hex digits, an underscore and a letter from a to e): nothing else is created or
dropped. The new role can log in and owns its database, nothing more: no superuser, no CREATEDB, no
CREATEROLE, and no other role may connect to its database. The settings name the database and a
first superuser for the app, with values drawn fresh for every database.
"""

import hashlib
import os
import re
import secrets
import shutil
import subprocess
import sys
from urllib.parse import unquote, urlsplit, urlunsplit

NAME = re.compile(r"r[0-9a-f]{12}|s[0-9a-f]{10}_[a-e]")


def psql():
    d = os.environ.get("PG_BIN", "")
    if d and os.path.exists(os.path.join(d, "psql")):
        return os.path.join(d, "psql")
    found = shutil.which("psql")
    if not found:
        sys.exit("db.py: psql not found (set PG_BIN)")
    return found


def admin_url():
    url = os.environ.get("PG_URL", "")
    if not url:
        sys.exit("db.py: set PG_URL, the PostgreSQL admin URL")
    return url


def run_sql(statements, user=None, flags=()):
    """The statements on psql's stdin, one per line, so each runs on its own, as CREATE and DROP
    DATABASE need. As the admin, with its password in psql's environment; or, with user=, as that
    user with no password at all."""
    where = urlsplit(admin_url())
    raw_user, _, host = where.netloc.rpartition("@")
    raw_user = raw_user.split(":", 1)[0]
    env = {k: v for k, v in os.environ.items() if k not in ("PG_URL", "PGPASSWORD")}
    env["PGPASSFILE"] = os.devnull
    if user is None and where.password is not None:
        env["PGPASSWORD"] = unquote(where.password)
    who = raw_user if user is None else user
    url = urlunsplit(where._replace(netloc=f"{who}@{host}" if who else host))
    return subprocess.run(
        [psql(), url, "-X", "-q", "-w", "-v", "ON_ERROR_STOP=1", *flags],
        input="".join(s + ";\n" for s in statements),
        capture_output=True,
        text=True,
        timeout=60,
        env=env,
    )


def must(r):
    if r.returncode:
        sys.exit(f"db.py: {r.stderr.strip() or 'psql failed'}")
    return r


def create(name):
    where = urlsplit(admin_url())
    if not where.hostname:
        sys.exit(
            "db.py: the admin URL needs a TCP host, which the backend connects to as well"
        )
    secret = secrets.token_hex(16)  # [0-9a-f] only, so it needs no quoting in SQL
    must(
        run_sql(
            [
                f"CREATE ROLE {name} LOGIN PASSWORD '{secret}' NOSUPERUSER NOCREATEDB NOCREATEROLE",
                f"CREATE DATABASE {name} OWNER {name} ENCODING 'UTF8' TEMPLATE template0",
                f"REVOKE CONNECT, TEMPORARY ON DATABASE {name} FROM PUBLIC",
            ]
        )
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


def drop(name):
    must(
        run_sql(
            [
                f"DROP DATABASE IF EXISTS {name} WITH (FORCE)",
                f"DROP ROLE IF EXISTS {name}",
            ]
        )
    )


def exists(name):
    r = must(
        run_sql([f"SELECT 1 FROM pg_database WHERE datname = '{name}'"], flags=("-tA",))
    )
    return 0 if r.stdout.strip() == "1" else 1


def check_auth():
    """A run gets its database server's host and port. If the admin user, or postgres, can log in
    there with no password, an agent can too, as that user."""
    where = urlsplit(admin_url())
    raw_user = where.netloc.rpartition("@")[0].split(":", 1)[0]
    for user in dict.fromkeys(u for u in (raw_user, "postgres") if u):
        if run_sql(["SELECT 1"], user=user).returncode == 0:
            print(
                f"db.py: {where.hostname}:{where.port or 5432} lets {unquote(user)} log in with no "
                "password, so an agent could too. Use a server that asks for one, or no --pg-url "
                "(a throwaway cluster).",
                file=sys.stderr,
            )
            return 1
    return 0


def main(argv):
    arity = {"name": 1, "create": 1, "drop": 1, "exists": 1, "check-auth": 0, "ping": 0}
    if not argv or argv[0] not in arity or len(argv) != arity[argv[0]] + 1:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    verb = argv[0]
    if verb == "name":
        print("r" + hashlib.sha256(os.path.realpath(argv[1]).encode()).hexdigest()[:12])
        return 0
    if verb == "check-auth":
        return check_auth()
    if verb == "ping":
        return 0 if run_sql(["SELECT 1"]).returncode == 0 else 1
    name = argv[1]
    if not NAME.fullmatch(name):
        sys.exit(
            f"db.py: bad name {name!r}: a run's is r and 12 hex digits, a scorer's s0123456789_a"
        )
    if verb == "exists":
        return exists(name)
    (create if verb == "create" else drop)(name)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
