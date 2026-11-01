#!/usr/bin/env bash
#
# Regression harness for application.lib.db's search() and idsInSearchTerm(): the order of text
# search results (score, then the table's order_by, then id) and search()'s sql_type argument.
# Starts a throwaway PostgreSQL in Docker, loads scripts/test_db_search/fixture.sql, serves
# scripts/test_db_search/probe.cfm with RustCFML against this checkout, and prints what the probe
# found. Nothing outside the container and a temporary directory is touched.
#
# Needs Docker and a RustCFML binary (RUSTCFML, default: rustcfml on PATH). Run from Moopa's root:
#   bash scripts/test_db_search.sh
#   RUSTCFML=/path/to/rustcfml bash scripts/test_db_search.sh

set -euo pipefail

root="$PWD"
rustcfml="${RUSTCFML:-rustcfml}"
pg_image="${PG_IMAGE:-postgres:16-alpine}"

if [ ! -f "$root/lib/db.cfc" ] || [ ! -f "$root/scripts/test_db_search/probe.cfm" ]; then
  echo "Run from Moopa's root." >&2
  exit 2
fi
command -v docker > /dev/null || { echo "Docker is required." >&2; exit 2; }
command -v "$rustcfml" > /dev/null || { echo "RustCFML not found: set RUSTCFML to its binary." >&2; exit 2; }

tmpdir="$(mktemp -d)"
container="moopa-db-search-$$"
server_pid=""
cleanup() {
  if [ -n "$server_pid" ]; then kill "$server_pid" 2> /dev/null || true; fi
  docker rm -f "$container" > /dev/null 2>&1 || true
  rm -rf "$tmpdir"
}
trap cleanup EXIT

free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

# A local, throwaway database with no password: it listens on 127.0.0.1 only and is removed on exit.
docker run -d --name "$container" -e POSTGRES_DB=probe -e POSTGRES_USER=probe \
  -e POSTGRES_HOST_AUTH_METHOD=trust -p 127.0.0.1::5432 "$pg_image" > /dev/null
pg_port="$(docker port "$container" 5432/tcp | head -n 1 | sed 's/.*://')"

for _ in $(seq 1 60); do
  # The image's init runs a temporary server first, so wait for the real one on TCP.
  if docker exec "$container" pg_isready -h 127.0.0.1 -U probe -d probe > /dev/null 2>&1; then break; fi
  sleep 1
done
docker exec -i "$container" psql -q -v ON_ERROR_STOP=1 -h 127.0.0.1 -U probe -d probe \
  < "$root/scripts/test_db_search/fixture.sql"

webroot="$tmpdir/www"
mkdir -p "$webroot"
cp "$root/scripts/test_db_search/probe.cfm" "$webroot/probe.cfm"
cat > "$webroot/Application.cfc" <<EOF
component {
    this.name = "moopa_db_search_probe_$$";
    this.mappings["/moopa"] = "$root";
    this.mappings["/db_search_fixture"] = "$root/scripts/test_db_search/fixture";
    this.datasources["probe"] = {
        driver: "postgresql",
        host: "127.0.0.1",
        port: "$pg_port",
        database: "probe",
        username: "probe",
        password: ""
    };
    this.datasource = "probe";
}
EOF

http_port="$(free_port)"
"$rustcfml" --serve "$webroot" --port "$http_port" > "$tmpdir/server.log" 2>&1 &
server_pid=$!

output=""
for _ in $(seq 1 30); do
  if output="$(curl -sS "http://127.0.0.1:$http_port/probe.cfm" 2> /dev/null)"; then break; fi
  sleep 1
done

echo "$output"
if printf '%s\n' "$output" | grep -q '^PASS '; then
  exit 0
fi
echo "--- server log ---" >&2
cat "$tmpdir/server.log" >&2
exit 1
