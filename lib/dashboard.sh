#!/usr/bin/env bash
# =============================================================================
# dashboard.sh - Dashboard Server Management
# =============================================================================
# Functions to start, stop, and manage the dashboard server.
# Integrates with the swarm orchestration system.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Support environment variable from install.sh wrapper, fallback to relative path
DASHBOARD_DIR="${CONTINUOUS_CLAUDE_DASHBOARD_DIR:-${SCRIPT_DIR}/../dashboard}"
DASHBOARD_PID_FILE="${TMPDIR:-/tmp}/continuous-claude-dashboard.pid"
DASHBOARD_LOG_FILE="${TMPDIR:-/tmp}/continuous-claude-dashboard.log"
DEFAULT_DASHBOARD_PORT="${DASHBOARD_PORT:-8000}"

# =============================================================================
# Server Management
# =============================================================================

# Check if dashboard server is running
# Usage: is_dashboard_running
is_dashboard_running() {
    if [[ -f "$DASHBOARD_PID_FILE" ]]; then
        local pid
        pid=$(cat "$DASHBOARD_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# Get dashboard server PID
# Usage: get_dashboard_pid
get_dashboard_pid() {
    if [[ -f "$DASHBOARD_PID_FILE" ]]; then
        cat "$DASHBOARD_PID_FILE"
    fi
}

# Start dashboard server
# Usage: start_dashboard [port]
start_dashboard() {
    local port="${1:-$DEFAULT_DASHBOARD_PORT}"

    if is_dashboard_running; then
        echo "Dashboard already running (PID: $(get_dashboard_pid))"
        return 0
    fi

    # Check if Python is available
    if ! command -v python3 &>/dev/null; then
        echo "Error: python3 not found" >&2
        return 1
    fi

    # Check if uvicorn is available in current Python environment
    if ! python3 -c "import uvicorn" 2>/dev/null; then
        echo "Warning: uvicorn not installed in current Python environment." >&2
        echo "Installing dependencies..." >&2
        # Use python3 -m pip to ensure we install into the same Python that will run uvicorn
        (cd "${DASHBOARD_DIR}/backend" && python3 -m pip install -e . 2>&1) || {
            echo "Error: Could not install dependencies" >&2
            echo "Try running: pip install fastapi uvicorn aiosqlite" >&2
            return 1
        }
    fi

    echo "Starting dashboard server on port ${port}..."

    # Start server in background
    (
        cd "${DASHBOARD_DIR}/backend"
        PYTHONPATH="${DASHBOARD_DIR}/backend" python3 -m uvicorn main:app \
            --host 0.0.0.0 \
            --port "$port" \
            >> "$DASHBOARD_LOG_FILE" 2>&1
    ) &

    local pid=$!
    echo "$pid" > "$DASHBOARD_PID_FILE"

    # Wait a moment and check if it started
    sleep 2
    if kill -0 "$pid" 2>/dev/null; then
        echo "Dashboard started successfully"
        echo "  URL: http://localhost:${port}"
        echo "  API Docs: http://localhost:${port}/docs"
        echo "  PID: $pid"
        echo "  Log: $DASHBOARD_LOG_FILE"
        return 0
    else
        echo "Error: Dashboard failed to start. Check log: $DASHBOARD_LOG_FILE" >&2
        rm -f "$DASHBOARD_PID_FILE"
        return 1
    fi
}

# Stop dashboard server
# Usage: stop_dashboard
stop_dashboard() {
    if ! is_dashboard_running; then
        echo "Dashboard not running"
        return 0
    fi

    local pid
    pid=$(get_dashboard_pid)
    echo "Stopping dashboard (PID: $pid)..."

    kill "$pid" 2>/dev/null
    sleep 1

    if kill -0 "$pid" 2>/dev/null; then
        echo "Force killing dashboard..."
        kill -9 "$pid" 2>/dev/null
    fi

    rm -f "$DASHBOARD_PID_FILE"
    echo "Dashboard stopped"
}

# Restart dashboard server
# Usage: restart_dashboard [port]
restart_dashboard() {
    local port="${1:-$DEFAULT_DASHBOARD_PORT}"
    stop_dashboard
    sleep 1
    start_dashboard "$port"
}

# Get dashboard status
# Usage: get_dashboard_status
get_dashboard_status() {
    if is_dashboard_running; then
        local pid
        pid=$(get_dashboard_pid)
        jq -n \
            --arg status "running" \
            --arg pid "$pid" \
            --arg port "$DEFAULT_DASHBOARD_PORT" \
            --arg url "http://localhost:${DEFAULT_DASHBOARD_PORT}" \
            '{
                status: $status,
                pid: ($pid | tonumber),
                port: ($port | tonumber),
                url: $url
            }'
    else
        jq -n '{status: "stopped"}'
    fi
}

# View dashboard logs
# Usage: view_dashboard_logs [lines]
view_dashboard_logs() {
    local lines="${1:-50}"

    if [[ -f "$DASHBOARD_LOG_FILE" ]]; then
        tail -n "$lines" "$DASHBOARD_LOG_FILE"
    else
        echo "No log file found"
    fi
}

# =============================================================================
# API Integration
# =============================================================================

# Send event to dashboard via API
# Usage: send_dashboard_event <session_id> <event_type> <payload_json>
send_dashboard_event() {
    local session_id="$1"
    local event_type="$2"
    local payload="$3"
    local port="${DASHBOARD_PORT:-$DEFAULT_DASHBOARD_PORT}"

    if ! is_dashboard_running; then
        return 1
    fi

    curl -s -X POST "http://localhost:${port}/api/events" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg sid "$session_id" \
            --arg type "$event_type" \
            --argjson payload "$payload" \
            '{session_id: $sid, event: $type, data: $payload}')" \
        2>/dev/null
}

# Update agent status in dashboard
# Usage: update_agent_dashboard <session_id> <agent_id> <status> [iteration] [cost]
update_agent_dashboard() {
    local session_id="$1"
    local agent_id="$2"
    local status="$3"
    local iteration="${4:-}"
    local cost="${5:-}"
    local port="${DASHBOARD_PORT:-$DEFAULT_DASHBOARD_PORT}"

    if ! is_dashboard_running; then
        return 1
    fi

    local payload="{\"status\": \"$status\""
    if [[ -n "$iteration" ]]; then
        payload+=", \"iteration\": $iteration"
    fi
    if [[ -n "$cost" ]]; then
        payload+=", \"cost\": $cost"
    fi
    payload+="}"

    curl -s -X PATCH "http://localhost:${port}/api/agents/${agent_id}" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        2>/dev/null
}

# Create log entry in dashboard
# Usage: log_to_dashboard <session_id> <level> <message> [agent_id] [data_json]
log_to_dashboard() {
    local session_id="$1"
    local level="$2"
    local message="$3"
    local agent_id="${4:-}"
    local data="${5:-"{}"}"
    local port="${DASHBOARD_PORT:-$DEFAULT_DASHBOARD_PORT}"

    if ! is_dashboard_running; then
        return 1
    fi

    local url="http://localhost:${port}/api/logs?session_id=${session_id}&level=${level}&message=$(echo "$message" | jq -sRr @uri)"
    if [[ -n "$agent_id" ]]; then
        url+="&agent_id=${agent_id}"
    fi

    curl -s -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "$data" \
        2>/dev/null
}

# Get dashboard state for a session
# Usage: get_dashboard_state <session_id>
get_dashboard_state() {
    local session_id="$1"
    local port="${DASHBOARD_PORT:-$DEFAULT_DASHBOARD_PORT}"

    if ! is_dashboard_running; then
        echo '{"error": "Dashboard not running"}' >&2
        return 1
    fi

    curl -s "http://localhost:${port}/api/dashboard/${session_id}" 2>/dev/null
}

# =============================================================================
# CLI Interface
# =============================================================================

dashboard_cli() {
    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        start)
            start_dashboard "${1:-}"
            ;;
        stop)
            stop_dashboard
            ;;
        restart)
            restart_dashboard "${1:-}"
            ;;
        status)
            get_dashboard_status
            ;;
        logs)
            view_dashboard_logs "${1:-50}"
            ;;
        state)
            get_dashboard_state "${1:-}"
            ;;
        help|*)
            echo "Usage: dashboard.sh <command> [args]"
            echo ""
            echo "Server Commands:"
            echo "  start [port]        Start dashboard server (default: 8000)"
            echo "  stop                Stop dashboard server"
            echo "  restart [port]      Restart dashboard server"
            echo "  status              Get server status as JSON"
            echo "  logs [lines]        View server logs (default: 50 lines)"
            echo ""
            echo "API Commands:"
            echo "  state <session_id>  Get dashboard state for a session"
            echo ""
            echo "Environment Variables:"
            echo "  DASHBOARD_PORT      Default server port (default: 8000)"
            ;;
    esac
}

# Run CLI if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    dashboard_cli "$@"
fi
