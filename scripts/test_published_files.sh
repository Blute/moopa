#!/usr/bin/env bash
#
# Regression harness for publishing a table's files (lib/published_files.cfc: syncRecord, syncAll):
# what saves, failures, retries, contested addresses, a rolled-back transaction and the sweep leave
# in the rows and the store. Starts a throwaway PostgreSQL in Docker, loads
# scripts/published_files_test/fixture.sql, serves scripts/published_files_test/run.cfm with RustCFML
# against this checkout and an in-memory store, and prints the checks. Nothing outside the container
# and a temporary directory is touched.
#
# Needs Docker and a RustCFML binary (RUSTCFML, default: rustcfml on PATH). Run from Moopa's root:
#   bash scripts/test_published_files.sh
#   RUSTCFML=/path/to/rustcfml bash scripts/test_published_files.sh

set -euo pipefail

root="$PWD"
rustcfml="${RUSTCFML:-rustcfml}"
pg_image="${PG_IMAGE:-postgres:16-alpine}"

if [ ! -f "$root/lib/db.cfc" ] || [ ! -f "$root/scripts/published_files_test/run.cfm" ]; then
  echo "Run from Moopa's root." >&2
  exit 2
fi
command -v docker > /dev/null || { echo "Docker is required." >&2; exit 2; }
command -v "$rustcfml" > /dev/null || { echo "RustCFML not found: set RUSTCFML to its binary." >&2; exit 2; }

tmpdir="$(mktemp -d)"
container="moopa-published-files-$$"
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
  < "$root/scripts/published_files_test/fixture.sql"

webroot="$tmpdir/www"
mkdir -p "$webroot"
cp "$root/scripts/published_files_test/"*.cfm "$root/scripts/published_files_test/"*.cfc "$webroot/"
cat > "$webroot/Application.cfc" <<EOF
component {
    this.name = "moopa_published_files_probe_$$";
    this.mappings["/moopa"] = "$root";
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
  if output="$(curl -sS "http://127.0.0.1:$http_port/run.cfm" 2> /dev/null)"; then break; fi
  sleep 1
done

echo "$output"
if printf '%s\n' "$output" | grep -q '^All [0-9]* checks passed'; then
  exit 0
fi
echo "--- server log ---" >&2
cat "$tmpdir/server.log" >&2
exit 1
