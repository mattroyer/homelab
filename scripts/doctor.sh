#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

read_env() {
  local key="$1"
  grep "^${key}=" "$ENV_FILE" 2>/dev/null | head -n1 | cut -d= -f2- || true
}

status_ok() {
  printf '[OK] %s\n' "$1"
}

status_warn() {
  printf '[WARN] %s\n' "$1"
}

status_fail() {
  printf '[FAIL] %s\n' "$1"
}

failures=0

if [ ! -f "$ENV_FILE" ]; then
  status_fail ".env is missing. Run ./scripts/bootstrap.sh first."
  exit 1
fi

if command -v docker >/dev/null 2>&1; then
  status_ok "docker is installed"
else
  status_fail "docker is not installed"
  failures=$((failures+1))
fi

if docker compose version >/dev/null 2>&1; then
  status_ok "docker compose v2 is available"
else
  status_fail "docker compose v2 is not available"
  failures=$((failures+1))
fi

DOMAIN_NAME="$(read_env DOMAIN_NAME)"
HOMELAB_HOST_IP="$(read_env HOMELAB_HOST_IP)"
MEDIA_ROOT="$(read_env MEDIA_ROOT)"
TRAEFIK_TLS_MODE="$(read_env TRAEFIK_TLS_MODE)"
CF_DNS_API_TOKEN="$(read_env CF_DNS_API_TOKEN)"
LOCAL_CERT_FILE="$(read_env LOCAL_CERT_FILE)"
LOCAL_CERT_KEY_FILE="$(read_env LOCAL_CERT_KEY_FILE)"

if [ -z "$TRAEFIK_TLS_MODE" ]; then
  TRAEFIK_TLS_MODE="selfsigned"
fi

if [ -z "$MEDIA_ROOT" ]; then
  MEDIA_ROOT="./data/media"
fi

if [ -n "$DOMAIN_NAME" ]; then
  status_ok "DOMAIN_NAME=$DOMAIN_NAME"
  if [ "$DOMAIN_NAME" = "example.com" ]; then
    status_warn "DOMAIN_NAME is still example.com; bootstrap now defaults new installs to <host-ip>.sslip.io"
  fi
else
  status_fail "DOMAIN_NAME is empty"
  failures=$((failures+1))
fi

if [ -n "$HOMELAB_HOST_IP" ]; then
  status_ok "HOMELAB_HOST_IP=$HOMELAB_HOST_IP"
else
  status_fail "HOMELAB_HOST_IP is empty"
  failures=$((failures+1))
fi

status_ok "MEDIA_ROOT=$MEDIA_ROOT"

media_root_path="$MEDIA_ROOT"
if [ -n "$MEDIA_ROOT" ] && [ "${MEDIA_ROOT#/}" = "$MEDIA_ROOT" ]; then
  media_root_path="$ROOT_DIR/$MEDIA_ROOT"
fi

if [ -n "$MEDIA_ROOT" ]; then
  if [ -d "$media_root_path" ]; then
    status_ok "MEDIA_ROOT exists on disk"
  else
    status_warn "MEDIA_ROOT does not exist on disk yet: $media_root_path"
  fi
fi

case "$TRAEFIK_TLS_MODE" in
  cloudflare)
    if [ -n "$CF_DNS_API_TOKEN" ]; then
      status_ok "Cloudflare TLS mode is configured"
    else
      status_fail "TRAEFIK_TLS_MODE=cloudflare but CF_DNS_API_TOKEN is empty"
      failures=$((failures+1))
    fi
    ;;
  provided)
    if [ -n "$LOCAL_CERT_FILE" ] && [ -n "$LOCAL_CERT_KEY_FILE" ]; then
      status_ok "Provided certificate mode is configured"
    else
      status_warn "TRAEFIK_TLS_MODE=provided but LOCAL_CERT_FILE/LOCAL_CERT_KEY_FILE are not both set"
    fi
    ;;
  selfsigned)
    if command -v openssl >/dev/null 2>&1; then
      status_ok "Self-signed TLS mode can generate a local wildcard certificate"
    else
      status_warn "openssl is not installed; Traefik will use its default certificate instead"
    fi
    ;;
  *)
    status_fail "Unsupported TRAEFIK_TLS_MODE=$TRAEFIK_TLS_MODE"
    failures=$((failures+1))
    ;;
esac

if [ -f "$ROOT_DIR/apps/glance/config/glance.yml" ]; then
  status_ok "Glance config has been rendered"
else
  status_warn "Glance config has not been rendered yet; run ./scripts/render-configs.sh"
fi

if [ -f "$ROOT_DIR/apps/traefik/traefik.yml" ]; then
  status_ok "Traefik config has been rendered"
else
  status_warn "Traefik config has not been rendered yet; run ./scripts/render-configs.sh"
fi

printf '\nStarter URLs:\n'
printf '  https://glance.%s\n' "$DOMAIN_NAME"
printf '  https://traefik-dashboard.%s\n' "$DOMAIN_NAME"

if [ "$failures" -ne 0 ]; then
  printf '\nDoctor found %s blocking issue(s).\n' "$failures"
  exit 1
fi

printf '\nDoctor checks passed.\n'
