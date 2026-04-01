#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
TRAEFIK_CERT_DIR="$ROOT_DIR/apps/traefik/certs"
GENERATED_CERT_FILE="$TRAEFIK_CERT_DIR/local-default.pem"
GENERATED_KEY_FILE="$TRAEFIK_CERT_DIR/local-default.key"

if [ ! -f "$ENV_FILE" ]; then
  echo ".env not found. Run ./scripts/bootstrap.sh first." >&2
  exit 1
fi

read_env() {
  local key="$1"
  grep "^${key}=" "$ENV_FILE" 2>/dev/null | head -n1 | cut -d= -f2- || true
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

write_dynamic_cert() {
  local cert_file="$1"
  local key_file="$2"
  local staged_cert="$cert_file"
  local staged_key="$key_file"

  if [ "$cert_file" != "$GENERATED_CERT_FILE" ] || [ "$key_file" != "$GENERATED_KEY_FILE" ]; then
    staged_cert="$TRAEFIK_CERT_DIR/provided-default.pem"
    staged_key="$TRAEFIK_CERT_DIR/provided-default.key"
    cp "$cert_file" "$staged_cert"
    cp "$key_file" "$staged_key"
    chmod 600 "$staged_key"
  fi

  cat >"$ROOT_DIR/apps/traefik/dynamic.toml" <<EOF
[tls]
  [[tls.certificates]]
    certFile = "/certs/$(basename "$staged_cert")"
    keyFile = "/certs/$(basename "$staged_key")"
EOF
}

write_dynamic_placeholder() {
  cat >"$ROOT_DIR/apps/traefik/dynamic.toml" <<'EOF'
# No local certificate configured.
# Traefik will use its internal default certificate for HTTPS.
# Set TRAEFIK_TLS_MODE=cloudflare for ACME certificates, or set
# LOCAL_CERT_FILE and LOCAL_CERT_KEY_FILE with TRAEFIK_TLS_MODE=provided.
EOF
}

generate_self_signed_cert() {
  if ! command -v openssl >/dev/null 2>&1; then
    return 1
  fi

  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "$GENERATED_KEY_FILE" \
    -out "$GENERATED_CERT_FILE" \
    -days 825 \
    -subj "/CN=${DOMAIN_NAME}" \
    -addext "subjectAltName=DNS:${DOMAIN_NAME},DNS:*.${DOMAIN_NAME}" \
    >/dev/null 2>&1
  chmod 600 "$GENERATED_KEY_FILE"
}

render_traefik_cloudflare() {
  cat >"$ROOT_DIR/apps/traefik/traefik.yml" <<EOF
api:
  dashboard: true
  debug: false
  insecure: true

log:
  level: INFO

accessLog:
  filePath: /var/log/access.log
  fields:
    defaultMode: keep
    headers:
      defaultMode: keep

entryPoints:
  http:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: https
          scheme: https
  https:
    address: ":443"
    http:
      tls:
        certResolver: cloudflare
        domains:
          - main: "${DOMAIN_NAME}"
            sans:
              - "*.${DOMAIN_NAME}"

serversTransport:
  insecureSkipVerify: true

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
  file:
    filename: /dynamic.toml
    watch: true

certificatesResolvers:
  cloudflare:
    acme:
      email: ${ACME_EMAIL}
      storage: /acme.json
      caServer: https://acme-v02.api.letsencrypt.org/directory
      dnsChallenge:
        provider: cloudflare
        resolvers:
          - "1.1.1.1:53"
          - "1.0.0.1:53"

http:
  routers:
    ha:
      rule: "Host(\`ha.${DOMAIN_NAME}\`)"
      service: ha
      entryPoints:
        - https
      tls: {}
  services:
    ha:
      loadBalancer:
        servers:
          - url: "http://host.docker.internal:8123"
EOF
}

render_traefik_local() {
  cat >"$ROOT_DIR/apps/traefik/traefik.yml" <<EOF
api:
  dashboard: true
  debug: false
  insecure: true

log:
  level: INFO

accessLog:
  filePath: /var/log/access.log
  fields:
    defaultMode: keep
    headers:
      defaultMode: keep

entryPoints:
  http:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: https
          scheme: https
  https:
    address: ":443"

serversTransport:
  insecureSkipVerify: true

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
  file:
    filename: /dynamic.toml
    watch: true

http:
  routers:
    ha:
      rule: "Host(\`ha.${DOMAIN_NAME}\`)"
      service: ha
      entryPoints:
        - https
      tls: {}
  services:
    ha:
      loadBalancer:
        servers:
          - url: "http://host.docker.internal:8123"
EOF
}

render_glance_config() {
  cat >"$ROOT_DIR/apps/glance/config/glance.yml" <<EOF
pages:
  - name: Home
    columns:
      - size: small
        widgets:
          - type: server-stats
            servers:
              - type: local
                name: host
      - size: full
        widgets:
          - type: docker-containers
            title: Services
            hide-by-default: true
      - size: small
        widgets:
          - type: bookmarks
            groups:
              - title: Stack
                links:
                  - title: Traefik
                    url: https://traefik-dashboard.${DOMAIN_NAME}
                  - title: Pi-hole
                    url: https://pihole.${DOMAIN_NAME}
                  - title: Home Assistant
                    url: https://ha.${DOMAIN_NAME}
EOF
}

DOMAIN_NAME="$(read_env DOMAIN_NAME)"
ACME_EMAIL="$(read_env ACME_EMAIL)"
HOMELAB_HOST_IP="$(read_env HOMELAB_HOST_IP)"
LOCAL_CERT_FILE="$(read_env LOCAL_CERT_FILE)"
LOCAL_CERT_KEY_FILE="$(read_env LOCAL_CERT_KEY_FILE)"
TRAEFIK_TLS_MODE="$(lower "$(read_env TRAEFIK_TLS_MODE)")"
CF_DNS_API_TOKEN="$(read_env CF_DNS_API_TOKEN)"

: "${DOMAIN_NAME:?DOMAIN_NAME is required}"
: "${HOMELAB_HOST_IP:?HOMELAB_HOST_IP is required}"

mkdir -p \
  "$ROOT_DIR/apps/glance/config" \
  "$ROOT_DIR/apps/traefik/certs" \
  "$ROOT_DIR/apps/pihole/dnsmasq.d"

TLS_SUMMARY=""

case "$TRAEFIK_TLS_MODE" in
  cloudflare)
    : "${ACME_EMAIL:?ACME_EMAIL is required for cloudflare mode}"
    : "${CF_DNS_API_TOKEN:?CF_DNS_API_TOKEN is required for cloudflare mode}"
    render_traefik_cloudflare
    if [ -n "${LOCAL_CERT_FILE:-}" ] && [ -n "${LOCAL_CERT_KEY_FILE:-}" ]; then
      write_dynamic_cert "$LOCAL_CERT_FILE" "$LOCAL_CERT_KEY_FILE"
      TLS_SUMMARY="cloudflare ACME with provided local fallback certificate"
    else
      write_dynamic_placeholder
      TLS_SUMMARY="cloudflare ACME"
    fi
    ;;
  provided)
    render_traefik_local
    if [ -n "${LOCAL_CERT_FILE:-}" ] && [ -n "${LOCAL_CERT_KEY_FILE:-}" ]; then
      write_dynamic_cert "$LOCAL_CERT_FILE" "$LOCAL_CERT_KEY_FILE"
      TLS_SUMMARY="provided local certificate"
    else
      write_dynamic_placeholder
      TLS_SUMMARY="provided mode requested, but no LOCAL_CERT_FILE/LOCAL_CERT_KEY_FILE were set; using Traefik default certificate"
    fi
    ;;
  selfsigned|"")
    render_traefik_local
    if generate_self_signed_cert; then
      write_dynamic_cert "$GENERATED_CERT_FILE" "$GENERATED_KEY_FILE"
      TLS_SUMMARY="generated self-signed wildcard certificate"
    else
      write_dynamic_placeholder
      TLS_SUMMARY="Traefik default certificate because openssl was not available"
    fi
    ;;
  *)
    echo "Unsupported TRAEFIK_TLS_MODE: $TRAEFIK_TLS_MODE" >&2
    exit 1
    ;;
esac

cat >"$ROOT_DIR/apps/pihole/dnsmasq.d/99-custom-cname.conf" <<EOF
address=/${DOMAIN_NAME}/${HOMELAB_HOST_IP}
EOF

render_glance_config

echo "Rendered Traefik, Glance config, and Pi-hole config from .env."
echo "TLS mode: $TLS_SUMMARY"
