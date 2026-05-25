#!/bin/bash
set -euo pipefail

# IB Client Portal Gateway — unified management script
# Usage: gateway.sh <PLUGIN_ROOT> <COMMAND> [ARGS...]
# Commands: start [TIMEOUT_MIN], stop, status, setup, update

PLUGIN_ROOT_ARG="${1:?Usage: gateway.sh <PLUGIN_ROOT> <COMMAND> [ARGS...]}"
COMMAND="${2:?Usage: gateway.sh <PLUGIN_ROOT> <COMMAND> [ARGS...]}"
shift 2

# Resolve to absolute path — all subsequent paths depend on this
if [[ "${PLUGIN_ROOT_ARG}" = /* ]]; then
  PLUGIN_ROOT="${PLUGIN_ROOT_ARG}"
else
  PLUGIN_ROOT="${PWD}/${PLUGIN_ROOT_ARG}"
fi

# Fallback to the standard local install path if PLUGIN_ROOT/gateway does not
# exist (e.g. user invoked the script via Bash with a partial PLUGIN_ROOT).
PLUGIN_SOURCE="$HOME/.claude/plugins/local/plugins/ib-portfolio-management"
GATEWAY_DIR="${PLUGIN_ROOT}/gateway"
if [[ ! -d "${GATEWAY_DIR}" ]]; then
  GATEWAY_DIR="${PLUGIN_SOURCE}/gateway"
fi
PID_FILE="${GATEWAY_DIR}/.pid"
LOG_FILE="${GATEWAY_DIR}/gateway.log"
CONF="${GATEWAY_DIR}/root/conf.yaml"
DOWNLOAD_URL="https://download2.interactivebrokers.com/portal/clientportal.gw.zip"

# Read port from conf.yaml (fallback to 5000, IB out-of-box default)
get_port() {
  if [[ -f "${CONF}" ]]; then
    grep 'listenPort:' "${CONF}" 2>/dev/null | awk '{print $2}' || echo "5000"
  else
    echo "5000"
  fi
}

# Ensure Java is available
ensure_java() {
  if ! java -version &>/dev/null; then
    for JAVA_DIR in /opt/homebrew/opt/openjdk/bin /usr/local/opt/openjdk/bin; do
      if [[ -x "${JAVA_DIR}/java" ]]; then
        export PATH="${JAVA_DIR}:${PATH}"
        return 0
      fi
    done
    echo "ERROR: Java not found. Run /ib-gateway setup for install instructions."
    exit 1
  fi
}

cmd_start() {
  local TIMEOUT_MIN="${1:-30}"
  local PORT
  PORT=$(get_port)

  ensure_java

  if [[ ! -f "${GATEWAY_DIR}/bin/run.sh" ]]; then
    echo "ERROR: Gateway not installed. Run /ib-gateway setup first."
    exit 1
  fi

  # Check if already running
  if [[ -f "${PID_FILE}" ]]; then
    local OLD_PID
    OLD_PID=$(cat "${PID_FILE}")
    if kill -0 "${OLD_PID}" 2>/dev/null; then
      echo "Gateway already running (PID: ${OLD_PID}, port: ${PORT})"
      exit 0
    else
      rm -f "${PID_FILE}"
    fi
  fi

  if pgrep -f "clientportal.gw" >/dev/null 2>&1; then
    echo "WARNING: Gateway process detected but no PID file."
    echo "Run /ib-gateway stop first, then try again."
    exit 1
  fi

  echo "Starting IB Client Portal Gateway..."
  echo "  Port: ${PORT}"
  echo "  Timeout: ${TIMEOUT_MIN} minutes"
  echo "  Log: ${LOG_FILE}"

  cd "${GATEWAY_DIR}"
  bin/run.sh root/conf.yaml > "${LOG_FILE}" 2>&1 &
  local GW_PID=$!
  echo "${GW_PID}" > "${PID_FILE}"

  # Schedule auto-kill
  local TIMEOUT_SEC=$((TIMEOUT_MIN * 60))
  (sleep "${TIMEOUT_SEC}" && kill "${GW_PID}" 2>/dev/null; echo "Gateway auto-stopped after ${TIMEOUT_MIN} minutes" >> "${LOG_FILE}") &
  echo "$!" > "${GATEWAY_DIR}/.timeout_pid"

  echo "Waiting for Gateway to initialize..."
  sleep 4

  if ! kill -0 "${GW_PID}" 2>/dev/null; then
    echo "ERROR: Gateway failed to start. Check log:"
    tail -20 "${LOG_FILE}"
    rm -f "${PID_FILE}"
    exit 1
  fi

  echo ""
  echo "=== Gateway started (PID: ${GW_PID}) ==="
  echo ""
  echo ">>> Open https://localhost:${PORT} in your browser and log in <<<"
  echo ""
  echo "After login, say 'ready' and I'll verify the session."
  echo "Gateway will auto-stop in ${TIMEOUT_MIN} minutes."
}

cmd_stop() {
  local STOPPED=false

  if [[ -f "${PID_FILE}" ]]; then
    local PID
    PID=$(cat "${PID_FILE}")
    if kill -0 "${PID}" 2>/dev/null; then
      echo "Stopping Gateway (PID: ${PID})..."
      kill "${PID}"
      sleep 2
      if kill -0 "${PID}" 2>/dev/null; then
        kill -9 "${PID}" 2>/dev/null || true
      fi
      STOPPED=true
    fi
    rm -f "${PID_FILE}"
  fi

  if pgrep -f "clientportal.gw" >/dev/null 2>&1; then
    echo "Stopping Gateway processes..."
    pkill -f "clientportal.gw" || true
    sleep 1
    pkill -9 -f "clientportal.gw" 2>/dev/null || true
    STOPPED=true
  fi

  # Kill timeout watcher
  local TIMEOUT_PID_FILE="${GATEWAY_DIR}/.timeout_pid"
  if [[ -f "${TIMEOUT_PID_FILE}" ]]; then
    local TPID
    TPID=$(cat "${TIMEOUT_PID_FILE}")
    kill "${TPID}" 2>/dev/null || true
    rm -f "${TIMEOUT_PID_FILE}"
  fi

  if [[ "${STOPPED}" == "true" ]]; then
    echo "Gateway stopped."
  else
    echo "Gateway was not running."
  fi
}

cmd_status() {
  local PORT
  PORT=$(get_port)

  if [[ ! -f "${GATEWAY_DIR}/bin/run.sh" ]]; then
    echo "Status: NOT INSTALLED"
    echo "Run /ib-gateway setup to download Gateway."
    return
  fi

  local RUNNING=false
  if [[ -f "${PID_FILE}" ]]; then
    local PID
    PID=$(cat "${PID_FILE}")
    if kill -0 "${PID}" 2>/dev/null; then
      RUNNING=true
      echo "Process: RUNNING (PID: ${PID})"
    else
      echo "Process: STOPPED (stale PID file)"
      rm -f "${PID_FILE}"
    fi
  elif pgrep -f "clientportal.gw" >/dev/null 2>&1; then
    RUNNING=true
    echo "Process: RUNNING (no PID file)"
  else
    echo "Process: STOPPED"
  fi

  if [[ "${RUNNING}" == "true" ]]; then
    local RESPONSE
    RESPONSE=$(curl -sk "https://localhost:${PORT}/v1/api/tickle" 2>/dev/null || echo "CURL_FAILED")
    if [[ "${RESPONSE}" == "CURL_FAILED" ]]; then
      echo "Session: UNREACHABLE (Gateway may still be starting)"
    elif echo "${RESPONSE}" | grep -q '"authenticated":true'; then
      echo "Session: AUTHENTICATED"
      if echo "${RESPONSE}" | grep -q '"connected":true'; then
        echo "Brokerage: CONNECTED"
      else
        echo "Brokerage: NOT CONNECTED (may need to confirm in browser)"
      fi
    else
      echo "Session: NOT AUTHENTICATED"
      echo ">>> Open https://localhost:${PORT} in browser and log in <<<"
    fi
  else
    echo "Session: N/A (Gateway not running)"
  fi

  echo ""
  echo "Config: port=${PORT}"
}

cmd_setup() {
  local LISTEN_PORT
  LISTEN_PORT=$(get_port)

  # Check Java
  local JAVA_CMD="java"
  if ! java -version &>/dev/null; then
    local HOMEBREW_JAVA=""
    if [[ -x "/opt/homebrew/opt/openjdk/bin/java" ]]; then
      HOMEBREW_JAVA="/opt/homebrew/opt/openjdk/bin"
    elif [[ -x "/usr/local/opt/openjdk/bin/java" ]]; then
      HOMEBREW_JAVA="/usr/local/opt/openjdk/bin"
    fi

    if [[ -n "${HOMEBREW_JAVA}" ]]; then
      JAVA_CMD="${HOMEBREW_JAVA}/java"
      echo "Java found at Homebrew location (not in PATH)."
      echo ""
      echo "To make it available in future shells, add this line to your shell rc"
      echo "  (~/.zshrc, ~/.bashrc, ~/.config/fish/config.fish, etc.):"
      echo ""
      echo "    export PATH=\"${HOMEBREW_JAVA}:\$PATH\""
      echo ""
      echo "Continuing this setup with the direct path."
    else
      echo "MISSING DEPENDENCY: Java Runtime (JRE 8+)"
      echo ""
      if [[ "$(uname)" == "Darwin" ]]; then
        if command -v brew &>/dev/null; then
          echo "Install on macOS:  brew install java"
        else
          echo "Install Homebrew first, then: brew install java"
        fi
      elif [[ -f /etc/debian_version ]]; then
        echo "Install: sudo apt install default-jre"
      else
        echo "Install Java 8+ from: https://adoptium.net"
      fi
      echo ""
      echo "After installing Java, run /ib-gateway setup again."
      exit 1
    fi
  fi

  echo "Java found: $($JAVA_CMD -version 2>&1 | head -1)"

  if [[ -f "${GATEWAY_DIR}/bin/run.sh" ]]; then
    echo "Gateway already installed at ${GATEWAY_DIR}"
    echo "Use /ib-gateway update to check for updates."
    exit 0
  fi

  echo "Downloading IB Client Portal Gateway..."
  local TMPDIR
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "${TMPDIR}"' EXIT

  curl -sL -o "${TMPDIR}/clientportal.gw.zip" "${DOWNLOAD_URL}"
  if [[ ! -f "${TMPDIR}/clientportal.gw.zip" ]]; then
    echo "ERROR: Download failed"
    exit 1
  fi

  echo "Download complete ($(du -h "${TMPDIR}/clientportal.gw.zip" | cut -f1))"
  echo "Extracting..."
  unzip -q "${TMPDIR}/clientportal.gw.zip" -d "${TMPDIR}"

  if [[ -d "${TMPDIR}/clientportal.gw" ]]; then
    mv "${TMPDIR}/clientportal.gw" "${GATEWAY_DIR}"
  else
    mkdir -p "${GATEWAY_DIR}"
    mv "${TMPDIR}"/* "${GATEWAY_DIR}/" 2>/dev/null || true
  fi

  if [[ ! -f "${GATEWAY_DIR}/bin/run.sh" ]]; then
    echo "ERROR: Extraction failed - bin/run.sh not found"
    rm -rf "${GATEWAY_DIR}"
    exit 1
  fi

  chmod +x "${GATEWAY_DIR}/bin/run.sh"

  CONF="${GATEWAY_DIR}/root/conf.yaml"
  if [[ -f "${CONF}" ]]; then
    sed -i '' "s/listenPort: .*/listenPort: ${LISTEN_PORT}/" "${CONF}"
    echo "Configuration patched: port=${LISTEN_PORT}"
  fi

  md5 -q "${TMPDIR}/clientportal.gw.zip" > "${GATEWAY_DIR}/.version_checksum" 2>/dev/null || \
    md5sum "${TMPDIR}/clientportal.gw.zip" | cut -d' ' -f1 > "${GATEWAY_DIR}/.version_checksum" 2>/dev/null || true

  echo ""
  echo "=== IB Client Portal Gateway installed ==="
  echo "Location: ${GATEWAY_DIR}"
  echo "Port: ${LISTEN_PORT}"

  # Flex Web Service setup
  local ENV_FILE="${PLUGIN_ROOT}/.env"
  if [[ -f "${ENV_FILE}" ]] && grep -q "IB_FLEX_TOKEN" "${ENV_FILE}"; then
    echo "Flex Web Service: credentials already configured in .env"
  else
    echo ""
    echo "=== Flex Web Service Setup (optional, for full trade history) ==="
    echo "CP Gateway shows only 7 days of trades."
    echo "For full history: IB Portal -> Flex Queries -> create token + query."
    echo "Add to: ${ENV_FILE}"
    echo '  IB_FLEX_TOKEN="your_token"'
    echo '  IB_FLEX_QUERY_TRADES="your_query_id"'
  fi

  echo ""
  echo "Next: run /ib-gateway start"
}

cmd_update() {
  local CHECKSUM_FILE="${GATEWAY_DIR}/.version_checksum"

  if [[ ! -f "${GATEWAY_DIR}/bin/run.sh" ]]; then
    echo "ERROR: Gateway not installed. Run /ib-gateway setup first."
    exit 1
  fi

  echo "Checking for updates..."
  local TMPDIR
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "${TMPDIR}"' EXIT

  curl -sL -o "${TMPDIR}/clientportal.gw.zip" "${DOWNLOAD_URL}"
  if [[ ! -f "${TMPDIR}/clientportal.gw.zip" ]]; then
    echo "ERROR: Download failed"
    exit 1
  fi

  local NEW_CHECKSUM OLD_CHECKSUM=""
  NEW_CHECKSUM=$(md5 -q "${TMPDIR}/clientportal.gw.zip" 2>/dev/null || md5sum "${TMPDIR}/clientportal.gw.zip" | cut -d' ' -f1)
  if [[ -f "${CHECKSUM_FILE}" ]]; then
    OLD_CHECKSUM=$(cat "${CHECKSUM_FILE}")
  fi

  if [[ "${NEW_CHECKSUM}" == "${OLD_CHECKSUM}" ]]; then
    echo "Gateway is up to date. (checksum: ${NEW_CHECKSUM:0:8}...)"
    exit 0
  fi

  echo "New version available!"
  echo "  Old: ${OLD_CHECKSUM:0:8}..."
  echo "  New: ${NEW_CHECKSUM:0:8}..."

  # Backup conf.yaml
  local CONF_BACKUP="${TMPDIR}/conf.yaml.backup"
  if [[ -f "${CONF}" ]]; then
    cp "${CONF}" "${CONF_BACKUP}"
    echo "Saved conf.yaml backup"
  fi

  # Stop if running
  if pgrep -f "clientportal.gw" >/dev/null 2>&1; then
    echo "Stopping running Gateway..."
    cmd_stop
  fi

  rm -rf "${GATEWAY_DIR}"
  unzip -q "${TMPDIR}/clientportal.gw.zip" -d "${TMPDIR}"

  if [[ -d "${TMPDIR}/clientportal.gw" ]]; then
    mv "${TMPDIR}/clientportal.gw" "${GATEWAY_DIR}"
  else
    mkdir -p "${GATEWAY_DIR}"
    mv "${TMPDIR}"/* "${GATEWAY_DIR}/" 2>/dev/null || true
  fi

  chmod +x "${GATEWAY_DIR}/bin/run.sh"

  if [[ -f "${CONF_BACKUP}" ]]; then
    cp "${CONF_BACKUP}" "${CONF}"
    echo "Restored conf.yaml"
  fi

  echo "${NEW_CHECKSUM}" > "${CHECKSUM_FILE}"

  echo ""
  echo "=== Gateway updated ==="
  echo "Run /ib-gateway start to launch."
}

# Dispatch
case "${COMMAND}" in
  start)  cmd_start "${1:-30}" ;;
  stop)   cmd_stop ;;
  status) cmd_status ;;
  setup)  cmd_setup ;;
  update) cmd_update ;;
  *)
    echo "Unknown command: ${COMMAND}"
    echo "Usage: /ib-gateway <start|stop|status|setup|update>"
    exit 1
    ;;
esac
