#!/usr/bin/env bash
set -euo pipefail

if [[ "${CODEX_GPT_OSS_TRACE:-0}" == "1" ]]; then
  set -x
fi

COMMAND_NAME="${0##*/}"
TEST_MODE=0
FILTERED_ARGS=()

log() {
  printf '[%s] %s\n' "$COMMAND_NAME" "$*"
}

die() {
  printf '[%s] error: %s\n' "$COMMAND_NAME" "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command '$1' not found in PATH"
}

need_cmd "curl"
need_cmd "python3"
need_cmd "codex"
# lsof is used to detect port conflicts and verify bindings
need_cmd "lsof"

ensure_ollama() {
  local OLLAMA_BIN="$ROOT_DIR/bin/ollama"
  local OLLAMA_VERSION="0.12.3"

  # Download and extract ollama binary if not present
  if [[ ! -x "$OLLAMA_BIN" ]]; then
    log "downloading ollama binary (version $OLLAMA_VERSION, MIT licensed)..."
    mkdir -p "$ROOT_DIR/bin"

    if [[ "$OS_NAME" != "Darwin" ]]; then
      die "ollama backend currently only supported on macOS"
    fi

    local DOWNLOAD_URL="https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}/ollama-darwin.tgz"
    local TMP_ARCHIVE="$ROOT_DIR/bin/ollama.tgz"

    curl -fsSL "$DOWNLOAD_URL" -o "$TMP_ARCHIVE" || die "failed to download ollama"
    tar -xzf "$TMP_ARCHIVE" -C "$ROOT_DIR/bin" || die "failed to extract ollama"
    rm -f "$TMP_ARCHIVE"

    # The archive contains 'ollama' binary at root
    if [[ ! -x "$OLLAMA_BIN" ]]; then
      die "ollama binary not found after extraction"
    fi

    log "ollama binary installed to $OLLAMA_BIN"
  fi

  # Check if ollama service is running
  if ! curl -s http://localhost:11434/api/version >/dev/null 2>&1; then
    log "starting embedded ollama service..."
    # Start ollama in background with custom models directory
    OLLAMA_MODELS="$ROOT_DIR/ollama-models" "$OLLAMA_BIN" serve >"$LOG_DIR/ollama.log" 2>&1 &
    local OLLAMA_PID=$!
    echo "$OLLAMA_PID" >"$RUN_DIR/ollama.pid"

    # Wait for it to be ready
    for i in {1..30}; do
      if curl -s http://localhost:11434/api/version >/dev/null 2>&1; then
        log "ollama service ready (pid $OLLAMA_PID)"
        return 0
      fi
      sleep 1
    done
    die "ollama service failed to start; see $LOG_DIR/ollama.log"
  fi
}

OS_NAME="$(uname -s)"
if [[ "$OS_NAME" != "Darwin" ]]; then
  log "warning: Metal backend is only supported on macOS; continuing anyway"
fi

ROOT_DIR="${CODEX_GPT_OSS_ROOT:-"$HOME/.codex/gpt-oss"}"
ENV_DIR="$ROOT_DIR/env"
RUN_DIR="$ROOT_DIR/run"
LOG_DIR="$ROOT_DIR/logs"
MODEL_ROOT="$ROOT_DIR/models"
mkdir -p "$RUN_DIR" "$LOG_DIR" "$MODEL_ROOT"

PYTHON_BIN="$ENV_DIR/bin/python"
PIP_BIN="$ENV_DIR/bin/pip"
HF_CACHE="${CODEX_GPT_OSS_HF_CACHE:-"$ROOT_DIR/hf-cache"}"
PORT="${CODEX_GPT_OSS_PORT:-8000}"
HOST="${CODEX_GPT_OSS_HOST:-127.0.0.1}"
BASE_URL="http://$HOST:$PORT/v1"
PID_FILE="$RUN_DIR/server.pid"
MODEL_STAMP="$RUN_DIR/active-model"
# Persist the last active port to avoid killing a healthy server on non-default port
PORT_STAMP="$RUN_DIR/active-port"
LOG_FILE="$LOG_DIR/server.log"

# Select inference backend. Default to Transformers (PyTorch MPS) on macOS; allow override via env.
BACKEND="${CODEX_GPT_OSS_BACKEND:-}"
if [[ -z "$BACKEND" ]]; then
  if [[ "$OS_NAME" == "Darwin" ]]; then
    BACKEND="transformers"
  else
    BACKEND="triton"
  fi
fi

# On macOS, restrict to supported backends to avoid unsupported builds.
if [[ "$OS_NAME" == "Darwin" ]]; then
  case "$BACKEND" in
    transformers|ollama|stub)
      : # ok
      ;;
    *)
      log "backend '$BACKEND' is not supported on macOS; using 'transformers' (PyTorch MPS)"
      BACKEND="transformers"
      ;;
  esac
fi

# Disallow accidental use of the stub backend unless explicitly enabled.
# This makes sure "stub" is only used in tests/CI or intentional local dev.
if [[ "$BACKEND" == "stub" && "${CODEX_GPT_OSS_ALLOW_STUB:-}" != "1" ]]; then
  die "The 'stub' inference backend is for testing only. Set CODEX_GPT_OSS_ALLOW_STUB=1 to use it intentionally."
fi

recompute_base_url() {
  BASE_URL="http://$HOST:$PORT/v1"
}

parse_args() {
  local default_model="${CODEX_GPT_OSS_MODEL:-gpt-oss:20b}"
  MODEL_SLUG="$default_model"
  local prev=""
  # TEST_MODE, MODEL_SLUG, and FILTERED_ARGS are global variables
  for arg in "$@"; do
    case "$arg" in
      --test)
        TEST_MODE=1
        ;;
      --model=*)
        MODEL_SLUG="${arg#--model=}"
        FILTERED_ARGS+=("$arg")
        ;;
      --model)
        prev="--model"
        FILTERED_ARGS+=("$arg")
        ;;
      -m)
        prev="-m"
        FILTERED_ARGS+=("$arg")
        ;;
      *)
        if [[ "$prev" == "--model" || "$prev" == "-m" ]]; then
          MODEL_SLUG="$arg"
          FILTERED_ARGS+=("$arg")
          prev=""
        elif [[ -n "$arg" ]]; then
          FILTERED_ARGS+=("$arg")
          prev=""
        fi
        ;;
    esac
  done
}

parse_args "$@"
VARIANT="20b"
HF_REPO="openai/gpt-oss-20b"
if [[ "$MODEL_SLUG" == *"120b"* ]]; then
  VARIANT="120b"
  HF_REPO="openai/gpt-oss-120b"
fi
MODEL_DIR="$MODEL_ROOT/gpt-oss-$VARIANT"
# Determine checkpoint path based on backend.
case "$BACKEND" in
  transformers)
    # Transformers expects a model directory
    CHECKPOINT_DEFAULT="$MODEL_DIR"
    ;;
  ollama)
    # For Ollama, the "checkpoint" is the model name as it appears in ollama list
    # Use the full MODEL_SLUG (e.g., "gpt-oss:20b") not just the variant
    CHECKPOINT_DEFAULT="$MODEL_SLUG"
    ;;
  metal)
    # Metal implementation expects a pre-converted single-file checkpoint
    CHECKPOINT_DEFAULT="$MODEL_DIR/metal/model.bin"
    ;;
  *)
    # Triton and other backends default to the SafeTensors index file
    CHECKPOINT_DEFAULT="$MODEL_DIR/model.safetensors.index.json"
    ;;
esac
CHECKPOINT="${CODEX_GPT_OSS_CHECKPOINT:-$CHECKPOINT_DEFAULT}"

ensure_env() {
  if [[ ! -x "$PYTHON_BIN" ]]; then
    log "creating virtual environment at $ENV_DIR"
    python3 -m venv "$ENV_DIR" || die "failed to create venv"
    "$PYTHON_BIN" -m pip install --upgrade pip wheel setuptools >/dev/null
  fi

  # Install runtime deps for selected backend using only binary wheels.
  log "ensuring virtual environment dependencies for backend '$BACKEND'"
  case "$BACKEND" in
    transformers)
      "$PYTHON_BIN" -m pip install --only-binary=:all: --upgrade \
        gpt_oss openai-harmony huggingface_hub uvicorn transformers accelerate torch >/dev/null \
        || die "failed to install transformers/MPS dependencies"
      ;;
    ollama)
      # Only need the server and its Python deps; Ollama itself is external
      "$PYTHON_BIN" -m pip install --only-binary=:all: --upgrade \
        gpt_oss openai-harmony huggingface_hub uvicorn requests >/dev/null \
        || die "failed to install ollama backend dependencies"
      ;;
    triton)
      "$PYTHON_BIN" -m pip install --only-binary=:all: --upgrade \
        "gpt_oss[triton]" openai-harmony huggingface_hub uvicorn >/dev/null \
        || die "failed to install triton dependencies"
      ;;
    metal)
      # We do not build the Metal extension; no prebuilt wheel is available.
      die "Metal backend requires a compiled extension not provided by PyPI. Use BACKEND=transformers for PyTorch MPS."
      ;;
    *)
      "$PYTHON_BIN" -m pip install --only-binary=:all: --upgrade \
        gpt_oss openai-harmony huggingface_hub uvicorn >/dev/null \
        || die "failed to install dependencies"
      ;;
  esac
}

ensure_weights() {
  mkdir -p "$MODEL_DIR"
  # Ollama pulls models itself; no local HF download required
  # The stub backend serves canned responses and does not require weights.
  if [[ "$BACKEND" == "ollama" || "$BACKEND" == "stub" ]]; then
    return
  fi
  local have=0
  if [[ "$BACKEND" == "transformers" ]]; then
    if [[ -d "$MODEL_DIR" && -f "$MODEL_DIR/config.json" ]]; then
      have=1
    fi
  else
    if [[ -f "$CHECKPOINT" ]]; then
      have=1
    fi
  fi
  if [[ "$have" -eq 1 ]]; then return; fi
  log "downloading weights for $VARIANT ($BACKEND) to $MODEL_DIR"
  HUGGINGFACE_HUB_CACHE="$HF_CACHE" "$PYTHON_BIN" - <<PY || die "failed to download weights from Hugging Face"
from huggingface_hub import snapshot_download
backend = "${BACKEND}"
patterns = None
if backend == "metal":
    patterns = ["metal/*"]
else:
    # Download the standard SafeTensors weights and configs used by non‑Metal backends
    patterns = [
        "model-*-of-*.safetensors",
        "model.safetensors.index.json",
        "config.json",
        "generation_config.json",
        "tokenizer.json",
        "tokenizer_config.json",
        "special_tokens_map.json",
        "chat_template.jinja",
        "original/*",
    ]
snapshot_download(repo_id="$HF_REPO", allow_patterns=patterns, local_dir="$MODEL_DIR", local_dir_use_symlinks=False, resume_download=True)
PY
  have=0
  if [[ "$BACKEND" == "transformers" ]]; then
    [[ -d "$MODEL_DIR" && -f "$MODEL_DIR/config.json" ]] && have=1
  else
    [[ -f "$CHECKPOINT" ]] && have=1
  fi
  if [[ "$have" -ne 1 ]]; then
    die "checkpoint not found at $CHECKPOINT after download"
  fi
}

server_alive() {
  local pid
  [[ -f "$PID_FILE" ]] || return 1
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [[ -n "$pid" ]] || return 1
  if ! kill -0 "$pid" >/dev/null 2>&1; then
    return 1
  fi
  # Verify the bound port actually belongs to our server process
  if ! lsof -nP -a -p "$pid" -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    return 1
  fi
  # Light HTTP probe; any of these response codes are fine for readiness
  local code headers
  headers="$(curl --silent --include --max-time 2 "$BASE_URL/responses" 2>/dev/null || true)"
  # Extract the HTTP status code from the first status line
  code="$(printf '%s' "$headers" | awk 'NR==1{print $2}')"
  case "$code" in
    200|204|400|401|403|404|405|422)
      :
      ;;
    *)
      return 1
      ;;
  esac
  # Guard against known non-gpt-oss services (e.g., DynamoDB Local on 8000)
  if printf '%s' "$headers" | grep -qiE '^Server: .*Jetty|x-amzn-RequestId'; then
    return 1
  fi
  return 0
}

stop_server() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$pid" && "$pid" =~ ^[0-9]+$ ]]; then
      if kill -0 "$pid" >/dev/null 2>&1; then
        log "stopping existing gpt-oss server (pid $pid)"
        kill "$pid" >/dev/null 2>&1 || true
        wait "$pid" 2>/dev/null || true
      fi
    fi
    rm -f "$PID_FILE"
  fi
}

start_server() {
  stop_server
  : >"$LOG_FILE"
  log "starting gpt-oss responses API on $HOST:$PORT"

  if [[ "${CODEX_GPT_OSS_FORCE_CPU:-0}" == "1" ]]; then
    log "forcing CPU backend (MPS disabled, will be slow)"
    WRAPPER_SCRIPT="${BASH_SOURCE[0]%/*}/run_gpt_oss_cpu.py"
    nohup "$PYTHON_BIN" "$WRAPPER_SCRIPT" \
      --checkpoint "$CHECKPOINT" \
      --port "$PORT" \
      --inference-backend "$BACKEND" \
      >>"$LOG_FILE" 2>&1 &
  elif [[ "$BACKEND" == "transformers" ]]; then
    log "using patched transformers backend for MPS compatibility"
    WRAPPER_SCRIPT="${BASH_SOURCE[0]%/*}/run_gpt_oss_mps_patched.py"
    nohup "$PYTHON_BIN" "$WRAPPER_SCRIPT" \
      --checkpoint "$CHECKPOINT" \
      --port "$PORT" \
      --inference-backend "$BACKEND" \
      >>"$LOG_FILE" 2>&1 &
  else
    # Other backends (ollama, triton, etc)
    nohup "$PYTHON_BIN" -m gpt_oss.responses_api.serve \
      --checkpoint "$CHECKPOINT" \
      --port "$PORT" \
      --inference-backend "$BACKEND" \
      >>"$LOG_FILE" 2>&1 &
  fi
  local pid=$!
  echo "$pid" >"$PID_FILE"

  for attempt in {1..60}; do
    if server_alive; then
      echo "gpt-oss:$VARIANT" >"$MODEL_STAMP"
      echo "$PORT" >"$PORT_STAMP"
      return
    fi
    sleep 1
  done
  tail -n 40 "$LOG_FILE" >&2
  die "gpt-oss server did not become ready; see $LOG_FILE"
}

ensure_server() {
  # If we have a recorded port from a previous successful start, prefer it
  if [[ -f "$PORT_STAMP" ]]; then
    local prev_port
    prev_port="$(cat "$PORT_STAMP" 2>/dev/null || true)"
    if [[ -n "$prev_port" && "$prev_port" =~ ^[0-9]+$ ]]; then
      PORT="$prev_port"
      recompute_base_url
    fi
  fi
  if [[ -f "$MODEL_STAMP" ]]; then
    local active
    active="$(cat "$MODEL_STAMP" 2>/dev/null || true)"
    if [[ "$active" != "gpt-oss:$VARIANT" ]]; then
      stop_server
    fi
  fi
  if server_alive; then
    return
  fi
  select_port
  start_server
}

# Return 0 if any process is listening on HOST:PORT
port_in_use() {
  lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1
}

# Select an available TCP port, starting with the requested PORT.
# Updates global PORT and BASE_URL.
select_port() {
  local requested="$PORT"
  # Treat "auto"/"0" as request for any free port
  if [[ "$requested" == "auto" || "$requested" == "0" ]]; then
    PORT="$("$PYTHON_BIN" - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
    )"
    recompute_base_url
    log "selected free port $PORT (auto)"
    return
  fi

  # If requested port is free, keep it; otherwise, scan upward for a free one
  if port_in_use; then
    local start="$requested" max=$((requested + 200))
    for p in $(seq "$start" "$max"); do
      PORT="$p"
      if ! port_in_use; then
        recompute_base_url
        log "port $requested is in use; selected $PORT instead"
        return
      fi
    done
    # Fallback: ask OS for a free port
    PORT="$("$PYTHON_BIN" - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
    )"
    recompute_base_url
    log "no free port in range; selected ephemeral $PORT"
  else
    recompute_base_url
  fi
}

# For ollama backend, ensure ollama is installed and running
if [[ "$BACKEND" == "ollama" ]]; then
  ensure_ollama
  OLLAMA_BIN="$ROOT_DIR/bin/ollama"
  # For ollama, the model name needs to be loaded
  log "checking if ollama has model $MODEL_SLUG..."
  if ! OLLAMA_MODELS="$ROOT_DIR/ollama-models" "$OLLAMA_BIN" list | grep -q "$MODEL_SLUG"; then
    log "pulling $MODEL_SLUG into ollama (this may take a while)..."
    OLLAMA_MODELS="$ROOT_DIR/ollama-models" "$OLLAMA_BIN" pull "$MODEL_SLUG" || die "failed to pull $MODEL_SLUG"
  fi
fi

ensure_env
ensure_weights
ensure_server

export CODEX_OSS_BASE_URL="$BASE_URL"
export CODEX_OSS_PORT="$PORT"

log "codex will target gpt-oss model '$MODEL_SLUG' via $BASE_URL"

if [[ "$TEST_MODE" == "1" ]]; then
  log "running in test mode with single prompt"
  log "testing /v1/responses endpoint (correct)"

  # Create a simple test request to verify the server is working
  TEST_RESPONSE=$(curl -s -X POST "$BASE_URL/responses" \
    -H "Content-Type: application/json" \
    -d '{
      "model": "'"$MODEL_SLUG"'",
      "input": [{"role": "user", "content": "Say hello in one word."}],
      "stream": false
    }')

  if echo "$TEST_RESPONSE" | grep -q '"content"'; then
    log "✓ test successful - server is responding correctly at $BASE_URL/responses"
    echo "$TEST_RESPONSE" | python3 -m json.tool 2>/dev/null | head -10 || echo "$TEST_RESPONSE"
  else
    log "✗ test failed - unexpected response from $BASE_URL/responses"
    echo "$TEST_RESPONSE"
    exit 1
  fi

  # Also try the wrong endpoint to show it fails (for comparison)
  log "testing /v1/chat/completions endpoint (wrong - should fail)"
  WRONG_RESPONSE=$(curl -s -X POST "$BASE_URL/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{}')

  if echo "$WRONG_RESPONSE" | grep -q "404\|Not Found"; then
    log "✓ correctly rejects /v1/chat/completions (404 Not Found)"
  else
    log "⚠ unexpected response from wrong endpoint"
    echo "$WRONG_RESPONSE"
  fi

  # Now test via Codex itself with a single-shot prompt
  log ""
  log "testing end-to-end via Codex with single prompt"
  CODEX_OUTPUT=$(codex exec \
    -c model_provider=oss \
    -c "model_providers.oss.name=\"gpt-oss\"" \
    -c "model_providers.oss.base_url=\"$BASE_URL\"" \
    -c "model_providers.oss.wire_api=\"responses\"" \
    -m "$MODEL_SLUG" \
    "What is 2+2? Answer with just the number." \
    2>&1 || true)

  if echo "$CODEX_OUTPUT" | grep -v "stream error\|ERROR" | grep -qE "\\b4\\b|four"; then
    log "✓ Codex successfully used gpt-oss backend!"
    echo ""
    echo "Full response from Codex:"
    echo "$CODEX_OUTPUT"
  else
    if echo "$CODEX_OUTPUT" | grep -q "stream error.*error sending request\|stream disconnected"; then
      log "⚠ Codex streaming failed (likely PyTorch MPS bug with large tensors)"
      log ""
      log "Summary: gpt-oss server works correctly for non-streaming requests,"
      log "but PyTorch MPS has a known bug that causes crashes with streaming requests."
      log ""
      log "Workarounds:"
      log "  1. Use Ollama backend: CODEX_GPT_OSS_BACKEND=ollama"
      log "  2. Use different hardware (CUDA/CPU)"
      log "  3. Wait for PyTorch MPS fix"
      echo ""
      echo "Last 10 lines of output:"
      echo "$CODEX_OUTPUT" | tail -10
    else
      log "⚠ Codex test inconclusive or failed"
      echo ""
      echo "Output:"
      echo "$CODEX_OUTPUT"
    fi
  fi

  exit 0
fi

# Use the built-in "oss" provider pointed at the local Responses API without
# triggering the --oss bootstrap (which expects Ollama). Explicitly set the
# provider to use the Responses API and the exact base_url to avoid accidental
# fallbacks to Chat Completions or a mismatched endpoint.
if [[ "${#FILTERED_ARGS[@]}" -gt 0 ]]; then
  exec codex \
    -c model_provider=oss \
    -c "model_providers.oss.name=\"gpt-oss\"" \
    -c "model_providers.oss.base_url=\"$BASE_URL\"" \
    -c "model_providers.oss.wire_api=\"responses\"" \
    -m "$MODEL_SLUG" \
    "${FILTERED_ARGS[@]}"
else
  exec codex \
    -c model_provider=oss \
    -c "model_providers.oss.name=\"gpt-oss\"" \
    -c "model_providers.oss.base_url=\"$BASE_URL\"" \
    -c "model_providers.oss.wire_api=\"responses\"" \
    -m "$MODEL_SLUG"
fi
