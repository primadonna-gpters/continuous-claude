#!/usr/bin/env bash
# =============================================================================
# messaging.sh - Inter-Agent Messaging System
# =============================================================================
# Provides file-based message passing between agents in the swarm.
# Messages are stored as JSON files in inbox/outbox directories.
# =============================================================================

# Message directory structure
SWARM_DIR="${SWARM_DIR:-.continuous-claude}"
MESSAGES_DIR="${SWARM_DIR}/messages"
INBOX_DIR="${MESSAGES_DIR}/inbox"
OUTBOX_DIR="${MESSAGES_DIR}/outbox"

# =============================================================================
# Initialization
# =============================================================================

# Initialize messaging directories for an agent
# Usage: init_messaging <agent_id>
init_messaging() {
    local agent_id="$1"

    if [[ -z "$agent_id" ]]; then
        echo "Error: agent_id is required" >&2
        return 1
    fi

    mkdir -p "${INBOX_DIR}/${agent_id}"
    mkdir -p "${OUTBOX_DIR}/pending"
    mkdir -p "${OUTBOX_DIR}/sent"

    echo "Initialized messaging for agent: ${agent_id}"
}

# Initialize messaging for all standard agents
init_all_messaging() {
    local agents=("orchestrator" "developer" "tester" "reviewer" "documenter" "security")

    for agent in "${agents[@]}"; do
        init_messaging "$agent"
    done

    echo "All messaging directories initialized"
}

# =============================================================================
# Message Creation
# =============================================================================

# Generate a unique message ID
# Usage: generate_message_id
generate_message_id() {
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local random_suffix
    random_suffix=$(openssl rand -hex 4 2>/dev/null || head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 8)
    echo "msg-${timestamp}-${random_suffix}"
}

# Create a new message
# Usage: create_message <from> <to> <type> <subject> [body_json]
# Returns: Message ID
create_message() {
    local from="$1"
    local to="$2"
    local type="$3"
    local subject="$4"
    local body="${5:-"{}"}"

    if [[ -z "$from" || -z "$to" || -z "$type" ]]; then
        echo "Error: from, to, and type are required" >&2
        return 1
    fi

    local msg_id
    msg_id=$(generate_message_id)
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Validate body is valid JSON, if not wrap it as content
    local validated_body
    # Use printf to avoid echo interpretation issues
    if printf '%s' "$body" | jq -e . >/dev/null 2>&1; then
        validated_body=$(printf '%s' "$body" | jq -c .)
    else
        # Escape the body string properly
        validated_body=$(jq -n --arg content "$body" '{"content": $content}')
    fi

    # Ensure outbox directory exists
    mkdir -p "${OUTBOX_DIR}/pending"
    mkdir -p "${OUTBOX_DIR}/sent"

    local msg_file="${OUTBOX_DIR}/pending/${msg_id}.json"

    # Build message using jq
    jq -n \
        --arg id "$msg_id" \
        --arg from "$from" \
        --arg to "$to" \
        --arg type "$type" \
        --arg subject "$subject" \
        --arg timestamp "$timestamp" \
        --argjson body "$validated_body" \
        '{
            id: $id,
            from: $from,
            to: $to,
            type: $type,
            subject: $subject,
            timestamp: $timestamp,
            body: $body,
            read: false,
            priority: "normal"
        }' > "$msg_file"

    echo "$msg_id"
}

# Create a high-priority message
# Usage: create_priority_message <from> <to> <type> <subject> [body_json]
create_priority_message() {
    local from="$1"
    local to="$2"
    local type="$3"
    local subject="$4"
    local body="${5:-"{}"}"

    local msg_id
    msg_id=$(create_message "$from" "$to" "$type" "$subject" "$body")

    # Update priority
    local msg_file="${OUTBOX_DIR}/pending/${msg_id}.json"
    if [[ -f "$msg_file" ]]; then
        local updated
        updated=$(jq '.priority = "high"' "$msg_file")
        echo "$updated" > "$msg_file"
    fi

    echo "$msg_id"
}

# =============================================================================
# Message Delivery
# =============================================================================

# Deliver all pending messages to their recipients
# Usage: deliver_messages
deliver_messages() {
    local pending_dir="${OUTBOX_DIR}/pending"
    local sent_dir="${OUTBOX_DIR}/sent"
    local delivered=0

    if [[ ! -d "$pending_dir" ]]; then
        return 0
    fi

    for msg_file in "${pending_dir}"/*.json; do
        [[ -f "$msg_file" ]] || continue

        local recipient
        recipient=$(jq -r '.to' "$msg_file")
        local msg_id
        msg_id=$(jq -r '.id' "$msg_file")

        if [[ -n "$recipient" && "$recipient" != "null" ]]; then
            # Ensure recipient inbox exists
            mkdir -p "${INBOX_DIR}/${recipient}"

            # Copy to recipient's inbox
            cp "$msg_file" "${INBOX_DIR}/${recipient}/${msg_id}.json"

            # Move to sent folder
            mv "$msg_file" "${sent_dir}/${msg_id}.json"

            ((delivered++))
        fi
    done

    echo "$delivered"
}

# Deliver a specific message immediately
# Usage: deliver_message <message_id>
deliver_message() {
    local msg_id="$1"
    local msg_file="${OUTBOX_DIR}/pending/${msg_id}.json"

    if [[ ! -f "$msg_file" ]]; then
        echo "Error: Message not found: ${msg_id}" >&2
        return 1
    fi

    local recipient
    recipient=$(jq -r '.to' "$msg_file")

    mkdir -p "${INBOX_DIR}/${recipient}"
    cp "$msg_file" "${INBOX_DIR}/${recipient}/${msg_id}.json"
    mv "$msg_file" "${OUTBOX_DIR}/sent/${msg_id}.json"

    echo "Delivered: ${msg_id} -> ${recipient}"
}

# =============================================================================
# Message Reading
# =============================================================================

# Get all unread messages for an agent
# Usage: get_unread_messages <agent_id>
get_unread_messages() {
    local agent_id="$1"
    local inbox="${INBOX_DIR}/${agent_id}"

    if [[ ! -d "$inbox" ]]; then
        echo "[]"
        return 0
    fi

    local messages="[]"
    local files=("${inbox}"/*.json)

    # Check if glob matched any files
    if [[ ! -e "${files[0]}" ]]; then
        echo "[]"
        return 0
    fi

    for msg_file in "${files[@]}"; do
        [[ -f "$msg_file" ]] || continue

        local is_read
        is_read=$(jq -r '.read' "$msg_file" 2>/dev/null)

        if [[ "$is_read" == "false" ]]; then
            local msg
            msg=$(cat "$msg_file")
            messages=$(echo "$messages" | jq --argjson msg "$msg" '. + [$msg]' 2>/dev/null || echo "$messages")
        fi
    done

    # Sort by priority (high first) then by timestamp
    echo "$messages" | jq 'sort_by(if .priority == "high" then 0 else 1 end, .timestamp)' 2>/dev/null || echo "[]"
}

# Get all messages for an agent (including read)
# Usage: get_all_messages <agent_id>
get_all_messages() {
    local agent_id="$1"
    local inbox="${INBOX_DIR}/${agent_id}"

    if [[ ! -d "$inbox" ]]; then
        echo "[]"
        return 0
    fi

    local messages="[]"
    local files=("${inbox}"/*.json)

    # Check if glob matched any files
    if [[ ! -e "${files[0]}" ]]; then
        echo "[]"
        return 0
    fi

    for msg_file in "${files[@]}"; do
        [[ -f "$msg_file" ]] || continue

        local msg
        msg=$(cat "$msg_file")
        messages=$(echo "$messages" | jq --argjson msg "$msg" '. + [$msg]' 2>/dev/null || echo "$messages")
    done

    echo "$messages" | jq 'sort_by(.timestamp) | reverse' 2>/dev/null || echo "[]"
}

# Read a specific message and mark as read
# Usage: read_message <agent_id> <message_id>
read_message() {
    local agent_id="$1"
    local msg_id="$2"
    local msg_file="${INBOX_DIR}/${agent_id}/${msg_id}.json"

    if [[ ! -f "$msg_file" ]]; then
        echo "Error: Message not found" >&2
        return 1
    fi

    # Mark as read
    local updated
    updated=$(jq '.read = true' "$msg_file")
    echo "$updated" > "$msg_file"

    # Return message content
    echo "$updated"
}

# Get unread message count for an agent
# Usage: get_unread_count <agent_id>
get_unread_count() {
    local agent_id="$1"
    local inbox="${INBOX_DIR}/${agent_id}"

    if [[ ! -d "$inbox" ]]; then
        echo "0"
        return 0
    fi

    local count=0
    local files=("${inbox}"/*.json)

    # Check if glob matched any files
    if [[ ! -e "${files[0]}" ]]; then
        echo "0"
        return 0
    fi

    for msg_file in "${files[@]}"; do
        [[ -f "$msg_file" ]] || continue

        local is_read
        is_read=$(jq -r '.read' "$msg_file" 2>/dev/null)

        if [[ "$is_read" == "false" ]]; then
            ((count++))
        fi
    done

    echo "$count"
}

# =============================================================================
# Message Filtering
# =============================================================================

# Get messages by type
# Usage: get_messages_by_type <agent_id> <type>
get_messages_by_type() {
    local agent_id="$1"
    local msg_type="$2"

    get_all_messages "$agent_id" | jq --arg type "$msg_type" '[.[] | select(.type == $type)]'
}

# Get messages from a specific sender
# Usage: get_messages_from <agent_id> <sender>
get_messages_from() {
    local agent_id="$1"
    local sender="$2"

    get_all_messages "$agent_id" | jq --arg from "$sender" '[.[] | select(.from == $from)]'
}

# Get recent messages (last N)
# Usage: get_recent_messages <agent_id> [count]
get_recent_messages() {
    local agent_id="$1"
    local count="${2:-10}"

    get_all_messages "$agent_id" | jq --argjson n "$count" '.[:$n]'
}

# =============================================================================
# Message Deletion
# =============================================================================

# Delete a message
# Usage: delete_message <agent_id> <message_id>
delete_message() {
    local agent_id="$1"
    local msg_id="$2"
    local msg_file="${INBOX_DIR}/${agent_id}/${msg_id}.json"

    if [[ -f "$msg_file" ]]; then
        rm "$msg_file"
        echo "Deleted: ${msg_id}"
    else
        echo "Error: Message not found" >&2
        return 1
    fi
}

# Delete all read messages for an agent
# Usage: cleanup_read_messages <agent_id>
cleanup_read_messages() {
    local agent_id="$1"
    local inbox="${INBOX_DIR}/${agent_id}"
    local deleted=0

    if [[ ! -d "$inbox" ]]; then
        echo "0"
        return 0
    fi

    for msg_file in "${inbox}"/*.json; do
        [[ -f "$msg_file" ]] || continue

        local is_read
        is_read=$(jq -r '.read' "$msg_file")

        if [[ "$is_read" == "true" ]]; then
            rm "$msg_file"
            ((deleted++))
        fi
    done

    echo "$deleted"
}

# =============================================================================
# Predefined Message Types
# =============================================================================

# Send a task assignment message
# Usage: send_task_assignment <from> <to> <task_description> [task_details_json]
send_task_assignment() {
    local from="$1"
    local to="$2"
    local description="$3"
    local details="${4:-"{}"}"

    local body
    body=$(jq -n \
        --arg desc "$description" \
        --argjson details "$details" \
        '{
            description: $desc,
            details: $details,
            assigned_at: (now | todate)
        }'
    )

    local msg_id
    msg_id=$(create_priority_message "$from" "$to" "task.assigned" "New task assignment" "$body")
    deliver_message "$msg_id"
    echo "$msg_id"
}

# Send a feature complete notification
# Usage: send_feature_complete <from> <feature_name> <files_changed_json> [notes]
send_feature_complete() {
    local from="$1"
    local feature="$2"
    local files="$3"
    local notes="${4:-}"

    local body
    body=$(jq -n \
        --arg feature "$feature" \
        --argjson files "$files" \
        --arg notes "$notes" \
        '{
            feature: $feature,
            files_changed: $files,
            notes: $notes,
            completed_at: (now | todate)
        }'
    )

    # Send to tester
    local msg_id
    msg_id=$(create_message "$from" "tester" "feature.implemented" "Feature ready for testing: ${feature}" "$body")
    deliver_message "$msg_id"
    echo "$msg_id"
}

# Send test results
# Usage: send_test_results <passed|failed> <test_summary_json> [failure_details]
send_test_results() {
    local status="$1"
    local summary="$2"
    local details="${3:-"{}"}"

    local body
    body=$(jq -n \
        --arg status "$status" \
        --argjson summary "$summary" \
        --argjson details "$details" \
        '{
            status: $status,
            summary: $summary,
            details: $details,
            tested_at: (now | todate)
        }'
    )

    local recipient="reviewer"
    local msg_type="test.passed"

    if [[ "$status" == "failed" ]]; then
        recipient="developer"
        msg_type="test.failed"
    fi

    local msg_id
    msg_id=$(create_message "tester" "$recipient" "$msg_type" "Test results: ${status}" "$body")
    deliver_message "$msg_id"
    echo "$msg_id"
}

# Send review feedback
# Usage: send_review_feedback <decision> <comments_json> [pr_number]
send_review_feedback() {
    local decision="$1"  # approve, request_changes, comment
    local comments="$2"
    local pr_number="${3:-}"

    local body
    body=$(jq -n \
        --arg decision "$decision" \
        --argjson comments "$comments" \
        --arg pr "$pr_number" \
        '{
            decision: $decision,
            comments: $comments,
            pr_number: $pr,
            reviewed_at: (now | todate)
        }'
    )

    local recipient="developer"
    local subject="Code review: ${decision}"

    if [[ "$decision" == "approve" ]]; then
        recipient="orchestrator"
        subject="PR approved for merge"
    fi

    local msg_id
    msg_id=$(create_message "reviewer" "$recipient" "review.${decision}" "$subject" "$body")
    deliver_message "$msg_id"
    echo "$msg_id"
}

# =============================================================================
# Utility Functions
# =============================================================================

# Format message for display
# Usage: format_message <message_json>
format_message() {
    local msg="$1"

    echo "$msg" | jq -r '
        "[\(.timestamp | split("T")[1] | split("Z")[0])] " +
        "[\(.from) → \(.to)] " +
        (if .priority == "high" then "🔴 " else "" end) +
        "\(.subject)"
    '
}

# Print message summary for an agent
# Usage: print_inbox_summary <agent_id>
print_inbox_summary() {
    local agent_id="$1"
    local unread
    unread=$(get_unread_count "$agent_id")
    local messages
    messages=$(get_recent_messages "$agent_id" 5)

    echo "📬 Inbox for ${agent_id}: ${unread} unread message(s)"
    echo "─────────────────────────────────────────"

    echo "$messages" | jq -r '.[] |
        "[\(.timestamp | split("T")[1] | split("Z")[0])] " +
        (if .read then "  " else "● " end) +
        "[\(.from)] " +
        (if .priority == "high" then "🔴 " else "" end) +
        "\(.subject)"
    '
}

# Wait for a message matching criteria
# Usage: wait_for_message <agent_id> <type> [timeout_seconds]
wait_for_message() {
    local agent_id="$1"
    local msg_type="$2"
    local timeout="${3:-300}"  # Default 5 minutes

    local start_time
    start_time=$(date +%s)

    while true; do
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [[ $elapsed -ge $timeout ]]; then
            echo "Error: Timeout waiting for message type: ${msg_type}" >&2
            return 1
        fi

        local messages
        messages=$(get_messages_by_type "$agent_id" "$msg_type")
        local unread_of_type
        unread_of_type=$(echo "$messages" | jq '[.[] | select(.read == false)]')
        local count
        count=$(echo "$unread_of_type" | jq 'length')

        if [[ $count -gt 0 ]]; then
            echo "$unread_of_type" | jq '.[0]'
            return 0
        fi

        sleep 2
    done
}

# =============================================================================
# Main (for testing)
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        init)
            init_all_messaging
            ;;
        send)
            create_message "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-"{}"}"
            ;;
        deliver)
            deliver_messages
            ;;
        inbox)
            print_inbox_summary "${2:-}"
            ;;
        unread)
            get_unread_messages "${2:-}"
            ;;
        read)
            read_message "${2:-}" "${3:-}"
            ;;
        *)
            echo "Usage: $0 {init|send|deliver|inbox|unread|read}"
            echo ""
            echo "Commands:"
            echo "  init                    - Initialize all messaging directories"
            echo "  send <from> <to> <type> <subject> [body] - Create and queue message"
            echo "  deliver                 - Deliver all pending messages"
            echo "  inbox <agent_id>        - Show inbox summary"
            echo "  unread <agent_id>       - Get unread messages as JSON"
            echo "  read <agent_id> <msg_id> - Read and mark message"
            ;;
    esac
fi
