#!/usr/bin/env bash
# usage: pg.sh start <dir>  -> starts a throwaway PostgreSQL cluster in <dir> on a free 127.0.0.1
#                              port, and prints its admin URL
#        pg.sh stop <dir>
# For the real suite when run.sh has no --pg-url, and for verify.sh --real. PG_BIN names the server
# binaries (default: `pg_config --bindir`, else /usr/lib/postgresql/16/bin).
# - The cluster is UTF-8, since psycopg returns bytes from an SQL_ASCII one.
# - It listens on 127.0.0.1 only and has no Unix socket, whose path a long <dir> would overflow. It
#   lives as long as the batch.
# - Every login needs a password: the admin URL carries the superuser's, drawn fresh here, and a
#   run's environment carries only its own database's. So an agent that reaches for the superuser
#   out of habit cannot touch another run's database. It is no barrier to one that goes looking:
#   the admin URL is in the environment of run.sh and its children, which the same user can read.
# - Postgres refuses to run as root, so as root the server runs as the postgres user, and <dir>
#   must be somewhere that user can reach.
set -euo pipefail
cmd="${1:-}" dir="${2:-}"
[ -n "$cmd" ] && [ -n "$dir" ] || { echo "usage: pg.sh start|stop <dir>" >&2; exit 2; }
bin="${PG_BIN:-$(pg_config --bindir 2>/dev/null || echo /usr/lib/postgresql/16/bin)}"
[ -x "$bin/initdb" ] && [ -x "$bin/pg_ctl" ] ||
  { echo "pg.sh: no initdb or pg_ctl in $bin (set PG_BIN, or give run.sh --pg-url)" >&2; exit 2; }
as_pg=()
[ "$(id -u)" != 0 ] || as_pg=(runuser -u postgres --)
case "$cmd" in
  start)
    mkdir -p "$dir"
    if [ "$(id -u)" = 0 ]; then
      chown postgres "$dir"
      runuser -u postgres -- test -w "$dir" ||
        { echo "pg.sh: the postgres user cannot reach $dir; give a directory under /tmp" >&2; exit 2; }
    fi
    port="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
    admin="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
    ( umask 077 && printf '%s\n' "$admin" > "$dir/admin" )
    [ "$(id -u)" != 0 ] || chown postgres "$dir/admin"
    ${as_pg[@]+"${as_pg[@]}"} "$bin/initdb" -D "$dir/data" -A scram-sha-256 --pwfile="$dir/admin" \
      -U postgres -E UTF8 --no-locale > "$dir/initdb.log" 2>&1 || { cat "$dir/initdb.log" >&2; exit 1; }
    rm -f "$dir/admin"
    ${as_pg[@]+"${as_pg[@]}"} "$bin/pg_ctl" -D "$dir/data" -l "$dir/server.log" -w \
      -o "-p $port -c listen_addresses=127.0.0.1 -c unix_socket_directories=" start > /dev/null ||
      { cat "$dir/server.log" >&2; exit 1; }
    echo "postgresql://postgres:$admin@127.0.0.1:$port/postgres"
    ;;
  stop)
    ${as_pg[@]+"${as_pg[@]}"} "$bin/pg_ctl" -D "$dir/data" -m fast -w stop > /dev/null 2>&1 || true
    ;;
  *) echo "pg.sh: unknown command '$cmd' (start|stop)" >&2; exit 2 ;;
esac
