#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# -----------------------------
# pkg-cache.sh
# Server: apt-cacher-ng + verdaccio + devpi (docker compose)
# Client: configure apt proxy + npm registry + pip index-url
# Fixes:
#  - Verdaccio storage permissions (EACCES -> 500) by chown to container uid/gid
#  - APT 404 for security.ubuntu.com via proxy by forcing DIRECT for that host
#  - grep + pipefail safety
# -----------------------------

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STATE_DIR="${HOME}/.pkg-cache-state"

# Put server files under a folder near the script by default
SERVER_DIR="${PKGCACHE_SERVER_DIR:-$SCRIPT_DIR/pkg-cache}"
SERVER_COMPOSE="${SERVER_DIR}/docker-compose.yml"
SERVER_ENV_FILE="${SERVER_DIR}/.env"
VERDACCIO_CONF_DIR="${SERVER_DIR}/verdaccio/conf"
VERDACCIO_CONF="${VERDACCIO_CONF_DIR}/config.yaml"
DATA_DIR="${SERVER_DIR}/data"

APT_PROXY_FILE="/etc/apt/apt.conf.d/01-pkg-cache-proxy"
APT_SECURITY_DIRECT_FILE="/etc/apt/apt.conf.d/02-pkg-cache-security-direct"
CLIENT_STATE_FILE="${STATE_DIR}/client.env"

ROLLBACK_CMDS=()

log()  { echo -e "[$SCRIPT_NAME] $*"; }
warn() { echo -e "[$SCRIPT_NAME] WARNING: $*" >&2; }
die()  { echo -e "[$SCRIPT_NAME] ERROR: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

cmd_str() {
  local out=""
  for a in "$@"; do out+="$(printf '%q ' "$a")"; done
  echo "${out% }"
}

run() {
  log "→ $(cmd_str "$@")"
  "$@"
}

sudo_run() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    need_cmd sudo
    sudo "$@"
  else
    "$@"
  fi
}

sudo_check() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    need_cmd sudo
    sudo -v
  fi
}

push_rollback() { ROLLBACK_CMDS+=("$*"); }

rollback() {
  if ((${#ROLLBACK_CMDS[@]} == 0)); then
    return 0
  fi
  warn "Rolling back due to failure..."
  for ((i=${#ROLLBACK_CMDS[@]}-1; i>=0; i--)); do
    warn "↩ ${ROLLBACK_CMDS[$i]}"
    bash -c "${ROLLBACK_CMDS[$i]}" >/dev/null 2>&1 || true
  done
}

on_err() {
  local exit_code=$?
  local line="${1:-?}"
  local cmd="${2:-?}"
  warn "Install failed (exit code: $exit_code) at line $line"
  warn "Failed command: $cmd"
  rollback
  exit "$exit_code"
}

# Health check helper (returns 0/1)
wait_http() {
  local url="$1"
  local name="$2"
  local tries="${3:-40}"
  local sleep_s="${4:-1}"

  need_cmd curl
  for ((i=1; i<=tries; i++)); do
    if curl -fsS --max-time 2 "$url" >/dev/null 2>&1; then
      log "✓ $name is reachable: $url"
      return 0
    fi
    sleep "$sleep_s"
  done
  return 1
}

detect_debian() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
      ubuntu|debian|linuxmint|pop) return 0 ;;
    esac
  fi
  return 1
}

get_server_ip_hint() {
  if command -v hostname >/dev/null 2>&1; then
    hostname -I 2>/dev/null | awk '{print $1}' || true
  fi
}

is_valid_ipv4() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS='.' read -r a b c d <<<"$ip"
  for n in "$a" "$b" "$c" "$d"; do
    [[ "$n" -ge 0 && "$n" -le 255 ]] || return 1
  done
  return 0
}

validate_server_host() {
  local host="$1"

  if [[ "$host" == *","* ]]; then
    die "Invalid SERVER_IP/host: '$host' (comma found). Use dots, e.g. 192.168.248.68"
  fi

  if is_valid_ipv4 "$host"; then
    return 0
  fi

  if [[ "$host" =~ ^[A-Za-z0-9.-]+$ ]]; then
    return 0
  fi

  die "Invalid SERVER_IP/host: '$host' (example: 192.168.248.68)"
}

ensure_dirs() {
  mkdir -p "$STATE_DIR"
  push_rollback "rm -rf '$STATE_DIR'"

  mkdir -p "$SERVER_DIR" "$DATA_DIR" "$VERDACCIO_CONF_DIR"
  mkdir -p "$DATA_DIR/apt-cacher-ng" "$DATA_DIR/verdaccio" "$DATA_DIR/devpi"
  push_rollback "rm -rf '$SERVER_DIR'"
}

write_server_files() {
  cat >"$SERVER_COMPOSE" <<'YAML'
services:
  aptcacher:
    image: mbentley/apt-cacher-ng:latest
    container_name: apt-cacher-ng
    restart: unless-stopped
    ports:
      - "3142:3142"
    volumes:
      - ./data/apt-cacher-ng:/var/cache/apt-cacher-ng
    environment:
      - TZ=Asia/Colombo

  verdaccio:
    image: verdaccio/verdaccio:latest
    container_name: verdaccio
    restart: unless-stopped
    ports:
      - "4873:4873"
    volumes:
      - ./data/verdaccio:/verdaccio/storage
      - ./verdaccio/conf:/verdaccio/conf

  devpi:
    image: python:3.12-slim
    container_name: devpi
    restart: unless-stopped
    ports:
      - "3141:3141"
    volumes:
      - ./data/devpi:/data
    environment:
      - DEVPI_SERVERDIR=/data
    command: >
      sh -c "pip install --no-cache-dir devpi-server devpi-web &&
             if [ ! -f /data/.inited ]; then
               devpi-init --serverdir /data --root-passwd=\"$${DEVPI_ROOT_PASS:-change-me}\" &&
               touch /data/.inited;
             fi &&
             devpi-server --serverdir /data --host 0.0.0.0 --port 3141"
YAML

  # Verdaccio config (use "log", "logs" deprecated)
  cat >"$VERDACCIO_CONF" <<'YAML'
storage: /verdaccio/storage

auth:
  htpasswd:
    file: /verdaccio/storage/htpasswd
    max_users: 1000

uplinks:
  npmjs:
    url: https://registry.npmjs.org/

packages:
  "@*/*":
    access: $all
    publish: $authenticated
    proxy: npmjs
  "**":
    access: $all
    publish: $authenticated
    proxy: npmjs

listen: 0.0.0.0:4873

log:
  - {type: stdout, format: pretty, level: http}
YAML
}

install_docker_if_needed() {
  detect_debian || die "This script currently supports Debian/Ubuntu-based systems for automatic install."

  if command -v docker >/dev/null 2>&1; then
    if systemctl is-active --quiet docker 2>/dev/null; then
      log "Docker already installed and running."
      return 0
    fi
    warn "Docker installed but not running; starting docker..."
    sudo_run systemctl enable --now docker
    return 0
  fi

  log "Installing Docker (docker.io) and compose plugin..."
  sudo_run apt-get update -y
  sudo_run apt-get install -y docker.io docker-compose-plugin curl ca-certificates

  push_rollback "sudo systemctl disable --now docker >/dev/null 2>&1 || true"
  sudo_run systemctl enable --now docker
}

ensure_docker_group() {
  if getent group docker >/dev/null 2>&1; then :; else sudo_run groupadd -f docker; fi

  if getent group docker | grep -qE "(^|,)\s*${USER}\s*(,|$)"; then
    log "User '$USER' is in docker group."
    return 0
  fi

  sudo_run usermod -aG docker "$USER"
  push_rollback "sudo gpasswd -d '$USER' docker >/dev/null 2>&1 || true"
  warn "Added '$USER' to docker group."
  warn "If docker permission issues happen, the script will fallback to sudo docker."
}

# --- Docker execution wrapper ---
DOCKER_MODE="plain"  # plain | sg | sudo

docker_exec() {
  case "$DOCKER_MODE" in
    plain) run docker "$@" ;;
    sg)
      need_cmd sg
      local cmd; cmd="$(cmd_str docker "$@")"
      log "→ (sg docker) $cmd"
      sg docker -c "$cmd"
      ;;
    sudo)
      log "→ (sudo) $(cmd_str docker "$@")"
      sudo_run docker "$@"
      ;;
    *) die "Unknown DOCKER_MODE: $DOCKER_MODE" ;;
  esac
}

# Capture stdout from docker commands (no logging prefix)
docker_capture() {
  case "$DOCKER_MODE" in
    plain) docker "$@" ;;
    sg)
      need_cmd sg
      local cmd; cmd="$(cmd_str docker "$@")"
      sg docker -c "$cmd"
      ;;
    sudo) sudo_run docker "$@" ;;
    *) return 1 ;;
  esac
}

init_docker_runner() {
  need_cmd docker

  if ! sudo_run docker info >/dev/null 2>&1; then
    warn "Docker daemon not responding; trying restart..."
    sudo_run systemctl restart docker >/dev/null 2>&1 || true
  fi

  if docker info >/dev/null 2>&1; then
    DOCKER_MODE="plain"
    log "Docker access: OK (plain)."
    return 0
  fi

  if command -v sg >/dev/null 2>&1; then
    if getent group docker | grep -qE "(^|,)\s*${USER}\s*(,|$)"; then
      if sg docker -c "docker info" >/dev/null 2>&1; then
        DOCKER_MODE="sg"
        log "Docker access: OK (sg docker)."
        return 0
      fi
    fi
  fi

  if sudo_run docker info >/dev/null 2>&1; then
    DOCKER_MODE="sudo"
    warn "Docker access requires sudo on this machine/session."
    return 0
  fi

  die "Docker daemon is not accessible. Check: sudo systemctl status docker"
}

write_env_file() {
  local devpi_pass="$1"
  mkdir -p "$SERVER_DIR"
  cat >"$SERVER_ENV_FILE" <<EOF
DEVPI_ROOT_PASS=${devpi_pass}
EOF
  chmod 600 "$SERVER_ENV_FILE"
}

server_up() {
  docker_exec compose version >/dev/null 2>&1 || die "Docker Compose plugin not available."
  (cd "$SERVER_DIR" && docker_exec compose up -d)
  push_rollback "(cd '$SERVER_DIR' && sudo docker compose down -v >/dev/null 2>&1 || true)"
}

# Fix Verdaccio EACCES by matching host dir ownership to container uid/gid
fix_verdaccio_permissions() {
  local host_dir="$DATA_DIR/verdaccio"
  mkdir -p "$host_dir"

  # Try to read uid/gid from container
  local uid gid
  uid="$(docker_capture exec verdaccio sh -lc 'id -u' 2>/dev/null | tr -d '\r' || true)"
  gid="$(docker_capture exec verdaccio sh -lc 'id -g' 2>/dev/null | tr -d '\r' || true)"

  if [[ -z "${uid:-}" || -z "${gid:-}" ]]; then
    warn "Could not detect verdaccio uid/gid; defaulting to 10001:10001"
    uid="10001"; gid="10001"
  fi

  # If owned by root (common when compose ran with sudo), fix it
  sudo_run chown -R "${uid}:${gid}" "$host_dir" || true

  # Restart verdaccio so it can write immediately
  (cd "$SERVER_DIR" && docker_exec compose restart verdaccio) || true
}

server_health_checks() {
  if ! wait_http "http://127.0.0.1:3142/acng-report.html" "apt-cacher-ng" 90 1; then
    die "Health check failed: apt-cacher-ng not reachable at http://127.0.0.1:3142/"
  fi

  if ! wait_http "http://127.0.0.1:4873/" "verdaccio" 90 1; then
    die "Health check failed: verdaccio not reachable at http://127.0.0.1:4873/"
  fi

  if ! wait_http "http://127.0.0.1:3141/" "devpi" 300 2; then
    warn "devpi still not reachable; showing last logs:"
    docker_exec logs --tail 200 devpi || true
    die "Health check failed: devpi not reachable at http://127.0.0.1:3141/"
  fi
}

server_install() {
  trap 'on_err $LINENO "$BASH_COMMAND"' ERR
  ensure_dirs
  install_docker_if_needed
  ensure_docker_group
  init_docker_runner

  write_server_files
  push_rollback "rm -f '$SERVER_COMPOSE' '$VERDACCIO_CONF' '$SERVER_ENV_FILE' >/dev/null 2>&1 || true"

  local devpi_pass_file="${STATE_DIR}/devpi_root_pass"
  if [[ ! -f "$devpi_pass_file" ]]; then
    local pass
    pass="$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 20 || true)"
    [[ -n "$pass" ]] || pass="devpi-$(date +%s)"
    echo "$pass" >"$devpi_pass_file"
    chmod 600 "$devpi_pass_file"
  fi

  local DEVPI_ROOT_PASS
  DEVPI_ROOT_PASS="$(cat "$devpi_pass_file")"
  write_env_file "$DEVPI_ROOT_PASS"

  server_up
  fix_verdaccio_permissions
  server_health_checks

  local ip
  ip="$(get_server_ip_hint)"
  log ""
  log "✅ Server cache is up."
  log "Server dir: $SERVER_DIR"
  log "APT cache report:  http://${ip:-SERVER_IP}:3142/acng-report.html"
  log "Verdaccio (npm):   http://${ip:-SERVER_IP}:4873/"
  log "devpi (pip):       http://${ip:-SERVER_IP}:3141/"
  log ""
  log "Note: APT caching works best when client APT sources use HTTP (not HTTPS)."
  trap - ERR
}

server_reset() {
  log "Resetting server cache setup..."
  if [[ -d "$SERVER_DIR" ]]; then
    if command -v docker >/dev/null 2>&1; then
      init_docker_runner || true
      (cd "$SERVER_DIR" && docker_exec compose down -v) || true
    fi
    rm -rf "$SERVER_DIR"
  fi
  rm -rf "$STATE_DIR" || true
  log "✅ Server reset done."
}

client_install() {
  local server_host="${1:-}"
  [[ -n "$server_host" ]] || die "client install requires SERVER_IP/host. Example: $SCRIPT_NAME client install 192.168.1.50"
  validate_server_host "$server_host"

  trap 'on_err $LINENO "$BASH_COMMAND"' ERR

  mkdir -p "$STATE_DIR"
  push_rollback "rm -rf '$STATE_DIR'"

  # ---- APT proxy (needs sudo) ----
  if detect_debian && command -v apt-get >/dev/null 2>&1; then
    sudo_check
    log "Configuring APT proxy at $APT_PROXY_FILE"
    sudo_run mkdir -p "$(dirname "$APT_PROXY_FILE")"

    sudo_run tee "$APT_PROXY_FILE" >/dev/null <<EOF
Acquire::http::Proxy "http://${server_host}:3142";
Acquire::https::Proxy "http://${server_host}:3142";
EOF
    push_rollback "sudo rm -f '$APT_PROXY_FILE' >/dev/null 2>&1 || true"

    # Force DIRECT for security.ubuntu.com (prevents 404 via apt-cacher-ng)
    sudo_run tee "$APT_SECURITY_DIRECT_FILE" >/dev/null <<'EOF'
Acquire::http::Proxy::security.ubuntu.com "DIRECT";
Acquire::https::Proxy::security.ubuntu.com "DIRECT";
EOF
    push_rollback "sudo rm -f '$APT_SECURITY_DIRECT_FILE' >/dev/null 2>&1 || true"

    local https_count
    https_count="$(
      (grep -RhsE '^\s*deb\s+https://' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null || true) \
      | wc -l | tr -d ' '
    )"
    if [[ "${https_count:-0}" != "0" ]]; then
      warn "Your APT sources include HTTPS entries. APT will work, but apt-cacher-ng won't cache HTTPS downloads."
      warn "To see APT cache HITs, switch APT mirrors to HTTP."
    fi
  else
    warn "APT not detected or not Debian/Ubuntu; skipping APT proxy config."
  fi

  # ---- npm registry ----
  if command -v npm >/dev/null 2>&1; then
    local prev_npm_reg=""
    prev_npm_reg="$(npm config get registry 2>/dev/null || true)"

    : > "$CLIENT_STATE_FILE"
    printf 'PREV_NPM_REGISTRY=%q\n' "$prev_npm_reg" >> "$CLIENT_STATE_FILE"

    push_rollback "if command -v npm >/dev/null 2>&1; then npm config set registry $(printf %q "$prev_npm_reg") >/dev/null 2>&1 || true; fi"

    run npm config set registry "http://${server_host}:4873/"
  else
    warn "npm not found; skipping npm config."
  fi

  # ---- pip config ----
  if command -v python3 >/dev/null 2>&1 && python3 -m pip --version >/dev/null 2>&1; then
    local prev_index="" prev_trusted=""
    prev_index="$(python3 -m pip config get global.index-url 2>/dev/null || true)"
    prev_trusted="$(python3 -m pip config get global.trusted-host 2>/dev/null || true)"

    [[ -f "$CLIENT_STATE_FILE" ]] || : > "$CLIENT_STATE_FILE"
    printf 'PREV_PIP_INDEX_URL=%q\n' "$prev_index" >> "$CLIENT_STATE_FILE"
    printf 'PREV_PIP_TRUSTED_HOST=%q\n' "$prev_trusted" >> "$CLIENT_STATE_FILE"

    push_rollback "python3 -m pip config unset global.index-url >/dev/null 2>&1 || true"
    push_rollback "python3 -m pip config unset global.trusted-host >/dev/null 2>&1 || true"
    [[ -n "$prev_index" ]] && push_rollback "python3 -m pip config set global.index-url $(printf %q "$prev_index") >/dev/null 2>&1 || true"
    [[ -n "$prev_trusted" ]] && push_rollback "python3 -m pip config set global.trusted-host $(printf %q "$prev_trusted") >/dev/null 2>&1 || true"

    run python3 -m pip config set global.index-url "http://${server_host}:3141/root/pypi/+simple/"
    run python3 -m pip config set global.trusted-host "${server_host}"
  else
    if command -v python3 >/dev/null 2>&1; then
      warn "python3 is present but pip is not. Install it with: sudo apt install python3-pip"
    else
      warn "python3/pip not found; skipping pip config."
    fi
  fi

  # ---- Reachability checks ----
  if command -v curl >/dev/null 2>&1; then
    wait_http "http://${server_host}:3142/acng-report.html" "apt-cacher-ng (server)" 20 1 || warn "Cannot reach apt-cacher-ng at http://${server_host}:3142"
    wait_http "http://${server_host}:4873/" "verdaccio (server)" 20 1 || warn "Cannot reach verdaccio at http://${server_host}:4873"
    wait_http "http://${server_host}:3141/" "devpi (server)" 20 1 || warn "Cannot reach devpi at http://${server_host}:3141"
  fi

  log "✅ Client configured to use server ${server_host}"
  log "Tip tests:"
  log "  - npm:  npm cache clean --force && npm i lodash"
  log "  - pip:  python3 -m pip cache purge && python3 -m pip install requests"
  log "  - apt:  sudo apt clean && sudo apt update && sudo apt install python3-pip"
  trap - ERR
}

client_reset() {
  log "Resetting client configuration..."

  if [[ -f "$APT_PROXY_FILE" ]]; then
    sudo_run rm -f "$APT_PROXY_FILE"
    log "Removed $APT_PROXY_FILE"
  fi

  if [[ -f "$APT_SECURITY_DIRECT_FILE" ]]; then
    sudo_run rm -f "$APT_SECURITY_DIRECT_FILE"
    log "Removed $APT_SECURITY_DIRECT_FILE"
  fi

  if [[ -f "$CLIENT_STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CLIENT_STATE_FILE" || true

    if command -v npm >/dev/null 2>&1 && [[ -n "${PREV_NPM_REGISTRY:-}" ]]; then
      npm config set registry "${PREV_NPM_REGISTRY}" >/dev/null 2>&1 || true
      log "Restored npm registry"
    fi

    if command -v python3 >/dev/null 2>&1 && python3 -m pip --version >/dev/null 2>&1; then
      python3 -m pip config unset global.index-url >/dev/null 2>&1 || true
      python3 -m pip config unset global.trusted-host >/dev/null 2>&1 || true

      if [[ -n "${PREV_PIP_INDEX_URL:-}" ]]; then
        python3 -m pip config set global.index-url "${PREV_PIP_INDEX_URL}" >/dev/null 2>&1 || true
      fi
      if [[ -n "${PREV_PIP_TRUSTED_HOST:-}" ]]; then
        python3 -m pip config set global.trusted-host "${PREV_PIP_TRUSTED_HOST}" >/dev/null 2>&1 || true
      fi
      log "Restored pip config (best-effort)"
    fi
  fi

  rm -rf "$STATE_DIR" || true
  log "✅ Client reset done."
}

usage() {
  cat <<EOF
Usage:
  # On your laptop (server)
  $SCRIPT_NAME server install
  $SCRIPT_NAME server reset

  # On friends' laptops (clients)
  $SCRIPT_NAME client install <SERVER_IP_or_host>
  $SCRIPT_NAME client reset

Notes:
  - APT caching with apt-cacher-ng works best when APT sources use HTTP (not HTTPS).
  - This script forces DIRECT for security.ubuntu.com on clients to avoid proxy 404s.
  - npm uses Verdaccio at :4873, pip uses devpi at :3141
  - Server files are created in: $SERVER_DIR
EOF
}

main() {
  local role="${1:-}"
  local action="${2:-}"

  case "$role:$action" in
    server:install) server_install ;;
    server:reset)   server_reset ;;
    client:install) client_install "${3:-}" ;;
    client:reset)   client_reset ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
