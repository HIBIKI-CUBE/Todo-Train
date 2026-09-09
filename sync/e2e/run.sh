#!/usr/bin/env bash
# Linux E2E: Swift client ↔ local Worker. No human steps.
set -euo pipefail

E2E_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$E2E_DIR/../.." && pwd)
WORKER_DIR="$ROOT/sync/worker"
PORT="${TODOTRAIN_SYNC_E2E_PORT:-8787}"
BASE_URL="http://127.0.0.1:${PORT}"
export TODOTRAIN_SYNC_E2E_URL="$BASE_URL"
export CI=true

PLAINTEXT_TITLE="週次レポート"
LOG=$(mktemp "${TMPDIR:-/tmp}/todotrain-sync-e2e-wrangler.XXXXXX.log")
PERSIST=$(mktemp -d "${TMPDIR:-/tmp}/todotrain-sync-e2e-persist.XXXXXX")
WRANGLER_PID=""

cleanup() {
  if [[ -n "${WRANGLER_PID}" ]] && kill -0 "${WRANGLER_PID}" 2>/dev/null; then
    kill "${WRANGLER_PID}" 2>/dev/null || true
    wait "${WRANGLER_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "e2e: worker log ${LOG}"
echo "e2e: persist ${PERSIST}"

if [[ ! -d "${WORKER_DIR}/node_modules" ]]; then
  (cd "${WORKER_DIR}" && npm ci)
fi

(
  cd "${WORKER_DIR}"
  npx wrangler dev \
    --local \
    --port "${PORT}" \
    --ip 127.0.0.1 \
    --persist-to "${PERSIST}" \
    --log-level info \
    --show-interactive-dev-session false
) >"${LOG}" 2>&1 &
WRANGLER_PID=$!

ready=0
for _ in $(seq 1 90); do
  if ! kill -0 "${WRANGLER_PID}" 2>/dev/null; then
    echo "e2e: wrangler exited before ready" >&2
    cat "${LOG}" >&2 || true
    exit 1
  fi
  code=$(curl -sS -o /tmp/todotrain-sync-e2e-probe.json -w '%{http_code}' \
    -X POST "${BASE_URL}/v1/offers" \
    -H 'content-type: application/json' \
    -d '{"x":"nope"}' || true)
  if [[ "${code}" == "400" ]]; then
    ready=1
    break
  fi
  sleep 1
done

if [[ "${ready}" -ne 1 ]]; then
  echo "e2e: worker did not become ready on ${BASE_URL}" >&2
  cat "${LOG}" >&2 || true
  exit 1
fi

echo "e2e: worker ready on ${BASE_URL}"

# Swift's bundled clang does not see g++ 13 headers / libstdc++ without extra flags.
# Required to compile swift-crypto / BoringSSL on this Linux image.
CXX_INC="${CXX_INC:-/usr/include/c++/13}"
CXX_INC_ABI="${CXX_INC_ABI:-/usr/include/x86_64-linux-gnu/c++/13}"
GCC_LIB="${GCC_LIB:-/usr/lib/gcc/x86_64-linux-gnu/13}"
SWIFT_CXX_FLAGS=()
if [[ -d "${CXX_INC}" ]]; then
  SWIFT_CXX_FLAGS+=(-Xcc "-I${CXX_INC}")
fi
if [[ -d "${CXX_INC_ABI}" ]]; then
  SWIFT_CXX_FLAGS+=(-Xcc "-I${CXX_INC_ABI}")
fi
if [[ -d "${GCC_LIB}" ]]; then
  SWIFT_CXX_FLAGS+=(-Xlinker "-L${GCC_LIB}")
fi
SWIFT_CXX_FLAGS+=(-Xlinker -lstdc++)

(cd "${E2E_DIR}" && swift test "${SWIFT_CXX_FLAGS[@]}")

if grep -F "${PLAINTEXT_TITLE}" "${LOG}" >/dev/null; then
  echo "e2e: plaintext title leaked into worker logs" >&2
  grep -n -F "${PLAINTEXT_TITLE}" "${LOG}" >&2 || true
  exit 1
fi

echo "e2e: worker logs have no plaintext title"
echo "e2e: ok"
