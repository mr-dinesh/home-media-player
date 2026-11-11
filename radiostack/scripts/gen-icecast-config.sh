#!/usr/bin/env bash
# Render icecast/icecast.xml from icecast.xml.template using values in .env.
# The rendered file holds real credentials and is gitignored — only the
# template is committed. Re-run this after changing .env.
set -euo pipefail

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$STACK_DIR/.env"
TEMPLATE="$STACK_DIR/icecast/icecast.xml.template"
OUTPUT="$STACK_DIR/icecast/icecast.xml"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: $ENV_FILE not found. Run: cp .env.example .env, then fill it in." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

REQUIRED=(ICECAST_SOURCE_PASSWORD ICECAST_RELAY_PASSWORD ICECAST_ADMIN_USER ICECAST_ADMIN_PASSWORD)
for var in "${REQUIRED[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "error: $var is empty in $ENV_FILE" >&2
    exit 1
  fi
  # These land inside XML text nodes; & < > would produce an invalid config.
  if [[ "${!var}" == *[\&\<\>]* ]]; then
    echo "error: $var contains & < or >, which cannot be used unescaped in XML." >&2
    echo "       Pick a value without those characters (openssl rand -base64 24 is safe)." >&2
    exit 1
  fi
done

envsubst '${ICECAST_SOURCE_PASSWORD} ${ICECAST_RELAY_PASSWORD} ${ICECAST_ADMIN_USER} ${ICECAST_ADMIN_PASSWORD}' \
  < "$TEMPLATE" > "$OUTPUT"
chmod 600 "$OUTPUT"

# Icecast in the container runs as icecast2 (uid 101 in moul/icecast), not as
# us, so mode 600 alone makes it fail with "Permission denied". Grant just that
# uid read access instead of opening the file to everyone.
ICECAST_CONTAINER_UID="${ICECAST_CONTAINER_UID:-101}"
if ! command -v setfacl >/dev/null; then
  echo "error: setfacl not found (apt install acl); icecast cannot read $OUTPUT without it." >&2
  exit 1
fi
setfacl -m "u:${ICECAST_CONTAINER_UID}:r" "$OUTPUT"

echo "wrote $OUTPUT (mode 600, plus read for container uid $ICECAST_CONTAINER_UID)"
