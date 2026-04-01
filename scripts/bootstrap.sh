#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
EXAMPLE_FILE="$ROOT_DIR/.env.example"

random_string() {
  local length="${1:-32}"
  local output=""

  while [ "${#output}" -lt "$length" ]; do
    output="${output}$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$length" || true)"
  done

  printf '%s' "${output:0:length}"
}

escape_sed() {
  printf '%s' "$1" | sed 's/[\/&]/\\&/g'
}

ensure_env_file() {
  if [ ! -f "$ENV_FILE" ]; then
    cp "$EXAMPLE_FILE" "$ENV_FILE"
  fi
}

detect_host_ip() {
  local detected
  detected="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  if [ -z "$detected" ]; then
    detected="127.0.0.1"
  fi
  printf '%s' "$detected"
}

set_env_value() {
  local key="$1"
  local value="$2"
  local escaped
  escaped="$(escape_sed "$value")"
  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i "s/^${key}=.*/${key}=${escaped}/" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >>"$ENV_FILE"
  fi
}

ensure_value() {
  local key="$1"
  local value="$2"
  local current
  current="$(grep "^${key}=" "$ENV_FILE" 2>/dev/null | head -n1 | cut -d= -f2- || true)"
  if [ -z "$current" ]; then
    set_env_value "$key" "$value"
  fi
}

build_traefik_credentials() {
  local user password
  user="$(grep '^TRAEFIK_DASHBOARD_USER=' "$ENV_FILE" | cut -d= -f2- || true)"
  password="$(grep '^TRAEFIK_DASHBOARD_PASSWORD=' "$ENV_FILE" | cut -d= -f2- || true)"

  if [ -z "$user" ]; then
    user="admin"
    set_env_value "TRAEFIK_DASHBOARD_USER" "$user"
  fi

  if [ -z "$password" ]; then
    password="$(random_string 24)"
    set_env_value "TRAEFIK_DASHBOARD_PASSWORD" "$password"
  fi

  if command -v openssl >/dev/null 2>&1; then
    local hash
    hash="$(openssl passwd -apr1 "$password")"
    hash="${hash//$/\$\$}"
    set_env_value "TRAEFIK_DASHBOARD_CREDENTIALS" "${user}:${hash}"
  fi
}

prepare_directories() {
  mkdir -p \
    "$ROOT_DIR/apps/comfyui/config" \
    "$ROOT_DIR/apps/comfyui/output" \
    "$ROOT_DIR/apps/glance/config" \
    "$ROOT_DIR/apps/homeassistant/.storage" \
    "$ROOT_DIR/apps/homeassistant/deps" \
    "$ROOT_DIR/apps/homeassistant/tts" \
    "$ROOT_DIR/apps/lazylibrarian/data" \
    "$ROOT_DIR/apps/n8n/data" \
    "$ROOT_DIR/apps/pihole/dnsmasq.d" \
    "$ROOT_DIR/apps/postgres/data" \
    "$ROOT_DIR/apps/traefik/certs" \
    "$ROOT_DIR/backups" \
    "$ROOT_DIR/data/immich-db" \
    "$ROOT_DIR/data/media/audiobooks" \
    "$ROOT_DIR/data/media/books" \
    "$ROOT_DIR/data/media/downloads/complete" \
    "$ROOT_DIR/data/media/downloads/incomplete" \
    "$ROOT_DIR/data/media/magazines" \
    "$ROOT_DIR/data/media/movies" \
    "$ROOT_DIR/data/media/podcasts" \
    "$ROOT_DIR/data/media/tvseries" \
    "$ROOT_DIR/data/media/youtube" \
    "$ROOT_DIR/data/photos"

  if [ ! -f "$ROOT_DIR/apps/traefik/acme.json" ]; then
    : >"$ROOT_DIR/apps/traefik/acme.json"
    chmod 600 "$ROOT_DIR/apps/traefik/acme.json"
  fi
}

ensure_env_file

HOST_IP="$(detect_host_ip)"

ensure_value "TZ" "UTC"
ensure_value "DOMAIN_NAME" "${HOST_IP}.sslip.io"
ensure_value "HOMELAB_HOST_IP" "$HOST_IP"
ensure_value "LOCAL_SUBDOMAIN" "*"
ensure_value "ACME_EMAIL" "admin@example.com"
ensure_value "MEDIA_ROOT" "./data/media"
ensure_value "TRAEFIK_TLS_MODE" "selfsigned"
ensure_value "MINIFLUX_ADMIN_USERNAME" "admin"
ensure_value "MINIFLUX_DB_NAME" "miniflux"
ensure_value "MINIFLUX_DB_USER" "miniflux"
ensure_value "PG_USER" "jellystat"
ensure_value "PGVECTOR_DB" "homelab"
ensure_value "PGVECTOR_USER" "homelab"
ensure_value "IMMICH_DB_DATABASE_NAME" "immich"
ensure_value "IMMICH_DB_USERNAME" "immich"
ensure_value "IMMICH_DB_DATA_LOCATION" "./data/immich-db"
ensure_value "PHOTO_UPLOAD_LOCATION" "./data/photos"
ensure_value "SEAFILE_ADMIN_EMAIL" "admin@example.com"

ensure_value "TRAEFIK_DASHBOARD_PASSWORD" "$(random_string 24)"
ensure_value "PIHOLE_WEB_PASSWORD" "$(random_string 24)"
ensure_value "N8N_PASSWORD" "$(random_string 24)"
ensure_value "MINIFLUX_ADMIN_PASSWORD" "$(random_string 24)"
ensure_value "MINIFLUX_DB_PASSWORD" "$(random_string 24)"
ensure_value "PG_PASSWORD" "$(random_string 32)"
ensure_value "JWT_SECRET" "$(random_string 48)"
ensure_value "PGVECTOR_PASSWORD" "$(random_string 32)"
ensure_value "LINKWARDEN_PG_PASSWORD" "$(random_string 32)"
ensure_value "CODER_POSTGRES_PASSWORD" "$(random_string 32)"
ensure_value "SEAFILE_ADMIN_PASSWORD" "$(random_string 24)"
ensure_value "SEAFILE_DB_ROOT_PASSWORD" "$(random_string 32)"
ensure_value "IMMICH_DB_PASSWORD" "$(random_string 32)"

build_traefik_credentials
prepare_directories
"$ROOT_DIR/scripts/render-configs.sh"

echo "Bootstrap complete."
echo "Review $ENV_FILE and fill in any blank external credentials before starting the stack."
echo "Starter apps will be available at https://glance.$(grep '^DOMAIN_NAME=' "$ENV_FILE" | cut -d= -f2- || true)"
echo "Media apps will use $(grep '^MEDIA_ROOT=' "$ENV_FILE" | cut -d= -f2- || true) by default."
