#!/usr/bin/env bash
# =============================================================================
# learning.sh - Failure Learning Mechanism
# =============================================================================
# Captures, analyzes, and learns from failures to improve future iterations.
# Stores insights in SQLite and injects them into prompts.
# =============================================================================

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Configuration
# =============================================================================

LEARNING_DIR="${LEARNING_DIR:-.continuous-claude/learning}"
INSIGHTS_DB="${LEARNING_DIR}/insights.db"
FAILURES_LOG="${LEARNING_DIR}/failures.json"
MAX_INSIGHTS_IN_PROMPT="${MAX_INSIGHTS_IN_PROMPT:-5}"
INSIGHT_MIN_CONFIDENCE="${INSIGHT_MIN_CONFIDENCE:-0.5}"

# =============================================================================
# Database Initialization
# =============================================================================

# Initialize SQLite database for learning memory
# Usage: init_learning_db
init_learning_db() {
    mkdir -p "$LEARNING_DIR"

    # Check if sqlite3 is available
    if ! command -v sqlite3 &>/dev/null; then
        echo "Warning: sqlite3 not found, using JSON fallback" >&2
        return 1
    fi

    sqlite3 "$INSIGHTS_DB" <<'EOF'
-- Failure records
CREATE TABLE IF NOT EXISTS failures (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    agent_id TEXT NOT NULL,
    iteration INTEGER NOT NULL,
    failure_type TEXT NOT NULL,  -- ci_failure, test_failure, lint_error, review_rejected
    error_message TEXT,
    affected_files TEXT,  -- JSON array
    context TEXT,  -- JSON object with additional context
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Learned insights
CREATE TABLE IF NOT EXISTS insights (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pattern TEXT UNIQUE NOT NULL,  -- Unique identifier for this insight
    failure_type TEXT NOT NULL,
    description TEXT NOT NULL,
    root_cause TEXT,
    solution TEXT NOT NULL,
    code_hint TEXT,  -- Optional code example
    affected_files_pattern TEXT,  -- Glob pattern for files this applies to
    confidence REAL DEFAULT 0.5,  -- 0.0 to 1.0
    times_applied INTEGER DEFAULT 0,
    times_successful INTEGER DEFAULT 0,
    last_applied TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insight application history
CREATE TABLE IF NOT EXISTS insight_applications (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    insight_id INTEGER REFERENCES insights(id),
    session_id TEXT NOT NULL,
    agent_id TEXT NOT NULL,
    iteration INTEGER NOT NULL,
    was_successful BOOLEAN,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_failures_session ON failures(session_id);
CREATE INDEX IF NOT EXISTS idx_failures_type ON failures(failure_type);
CREATE INDEX IF NOT EXISTS idx_insights_pattern ON insights(pattern);
CREATE INDEX IF NOT EXISTS idx_insights_confidence ON insights(confidence DESC);
CREATE INDEX IF NOT EXISTS idx_applications_insight ON insight_applications(insight_id);
EOF

    echo "Learning database initialized: $INSIGHTS_DB"
}

# =============================================================================
# Failure Capture
# =============================================================================

# Capture a failure event
# Usage: capture_failure <session_id> <agent_id> <iteration> <failure_type> <error_message> [affected_files_json] [context_json]
capture_failure() {
    local session_id="$1"
    local agent_id="$2"
    local iteration="$3"
    local failure_type="$4"
    local error_message="$5"
    local affected_files="${6:-"[]"}"
    local context="${7:-"{}"}"

    # Store in SQLite if available
    if command -v sqlite3 &>/dev/null && [[ -f "$INSIGHTS_DB" ]]; then
        sqlite3 "$INSIGHTS_DB" <<EOF
INSERT INTO failures (session_id, agent_id, iteration, failure_type, error_message, affected_files, context)
VALUES ('$session_id', '$agent_id', $iteration, '$failure_type', '$(echo "$error_message" | sed "s/'/''/g")', '$affected_files', '$context');
EOF
    fi

    # Also store in JSON log for backup
    mkdir -p "$LEARNING_DIR"
    local failure_entry
    failure_entry=$(jq -n \
        --arg sid "$session_id" \
        --arg aid "$agent_id" \
        --argjson iter "$iteration" \
        --arg type "$failure_type" \
        --arg msg "$error_message" \
        --argjson files "$affected_files" \
        --argjson ctx "$context" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            session_id: $sid,
            agent_id: $aid,
            iteration: $iter,
            failure_type: $type,
            error_message: $msg,
            affected_files: $files,
            context: $ctx,
            timestamp: $ts
        }')

    if [[ -f "$FAILURES_LOG" ]]; then
        local existing
        existing=$(cat "$FAILURES_LOG")
        echo "$existing" | jq --argjson new "$failure_entry" '. + [$new]' > "$FAILURES_LOG"
    else
        echo "[$failure_entry]" > "$FAILURES_LOG"
    fi

    echo "Captured failure: $failure_type in $agent_id iteration $iteration"
}

# Parse CI log and extract failure information
# Usage: parse_ci_failure <log_file_or_content>
# Can also read from stdin if no argument provided
parse_ci_failure() {
    local input="${1:-}"
    local content

    if [[ -z "$input" ]]; then
        # Read from stdin
        content=$(cat)
    elif [[ -f "$input" ]]; then
        content=$(cat "$input")
    else
        content="$input"
    fi

    local failure_type="ci_failure"
    local error_message=""
    local affected_files="[]"

    # Detect test failures (Jest, pytest, etc.)
    if echo "$content" | grep -qE "(FAIL|FAILED|ERROR|✕|✗|Test Suites:.*failed)"; then
        failure_type="test_failure"

        # Extract failing test names and status lines
        error_message=$(echo "$content" | grep -E "(FAIL[^I]|FAILED|✕|✗|Test Suites:)" | head -5 | tr '\n' '; ' | sed 's/; $//')

        # Extract affected test files
        affected_files=$(echo "$content" | grep -oE "[a-zA-Z0-9_/.:-]+\.(test|spec)\.[a-z]+" | sort -u | jq -R . | jq -s . 2>/dev/null || echo "[]")
    fi

    # Detect lint errors
    if echo "$content" | grep -qiE "(eslint|ruff|mypy|pylint).*error"; then
        failure_type="lint_error"
        error_message=$(echo "$content" | grep -iE "error" | head -5 | tr '\n' '; ')
    fi

    # Detect build failures
    if echo "$content" | grep -qiE "(build failed|compilation error|cannot find module)"; then
        failure_type="build_failure"
        error_message=$(echo "$content" | grep -iE "(error|failed)" | head -5 | tr '\n' '; ')
    fi

    # Detect type errors
    if echo "$content" | grep -qiE "(typescript|tsc|type error|TS[0-9]+)"; then
        failure_type="type_error"
        error_message=$(echo "$content" | grep -iE "error TS[0-9]+" | head -5 | tr '\n' '; ')
    fi

    jq -n \
        --arg type "$failure_type" \
        --arg msg "$error_message" \
        --argjson files "$affected_files" \
        '{
            failure_type: $type,
            error_message: $msg,
            affected_files: $files
        }'
}

# Parse PR review and extract rejection reasons
# Usage: parse_review_rejection <pr_number> [repo]
parse_review_rejection() {
    local pr_number="$1"
    local repo="${2:-$(git remote get-url origin 2>/dev/null | sed 's/.*github.com[:/]\(.*\)\.git/\1/')}"

    if ! command -v gh &>/dev/null; then
        echo '{"error": "gh CLI not available"}' >&2
        return 1
    fi

    # Get review comments
    local reviews
    reviews=$(gh pr view "$pr_number" --repo "$repo" --json reviews,comments 2>/dev/null)

    if [[ -z "$reviews" ]]; then
        echo '{"error": "Could not fetch PR reviews"}' >&2
        return 1
    fi

    # Extract rejection reasons
    local rejections
    rejections=$(echo "$reviews" | jq '[.reviews[] | select(.state == "CHANGES_REQUESTED") | {author: .author.login, body: .body}]')

    # Extract all comments
    local comments
    comments=$(echo "$reviews" | jq '[.comments[] | {author: .author.login, body: .body}]')

    jq -n \
        --argjson rejections "$rejections" \
        --argjson comments "$comments" \
        '{
            failure_type: "review_rejected",
            rejections: $rejections,
            comments: $comments
        }'
}

# =============================================================================
# Insight Management
# =============================================================================

# Create or update an insight
# Usage: create_insight <pattern> <failure_type> <description> <solution> [root_cause] [code_hint] [files_pattern]
create_insight() {
    local pattern="$1"
    local failure_type="$2"
    local description="$3"
    local solution="$4"
    local root_cause="${5:-}"
    local code_hint="${6:-}"
    local files_pattern="${7:-}"

    if command -v sqlite3 &>/dev/null && [[ -f "$INSIGHTS_DB" ]]; then
        sqlite3 "$INSIGHTS_DB" <<EOF
INSERT INTO insights (pattern, failure_type, description, root_cause, solution, code_hint, affected_files_pattern)
VALUES (
    '$pattern',
    '$failure_type',
    '$(echo "$description" | sed "s/'/''/g")',
    '$(echo "$root_cause" | sed "s/'/''/g")',
    '$(echo "$solution" | sed "s/'/''/g")',
    '$(echo "$code_hint" | sed "s/'/''/g")',
    '$files_pattern'
)
ON CONFLICT(pattern) DO UPDATE SET
    description = excluded.description,
    solution = excluded.solution,
    root_cause = excluded.root_cause,
    code_hint = excluded.code_hint,
    updated_at = CURRENT_TIMESTAMP;
EOF
        echo "Created/updated insight: $pattern"
    else
        # JSON fallback
        local insights_file="${LEARNING_DIR}/insights.json"
        mkdir -p "$LEARNING_DIR"

        local insight
        insight=$(jq -n \
            --arg pattern "$pattern" \
            --arg type "$failure_type" \
            --arg desc "$description" \
            --arg solution "$solution" \
            --arg cause "$root_cause" \
            --arg hint "$code_hint" \
            --arg files "$files_pattern" \
            '{
                pattern: $pattern,
                failure_type: $type,
                description: $desc,
                solution: $solution,
                root_cause: $cause,
                code_hint: $hint,
                affected_files_pattern: $files,
                confidence: 0.5,
                times_applied: 0,
                times_successful: 0
            }')

        if [[ -f "$insights_file" ]]; then
            local existing
            existing=$(cat "$insights_file")
            # Remove existing insight with same pattern, add new one
            echo "$existing" | jq --argjson new "$insight" \
                '[.[] | select(.pattern != $new.pattern)] + [$new]' > "$insights_file"
        else
            echo "[$insight]" > "$insights_file"
        fi

        echo "Created/updated insight (JSON): $pattern"
    fi
}

# Get relevant insights for a context
# Usage: get_relevant_insights [failure_type] [file_pattern] [limit]
get_relevant_insights() {
    local failure_type="${1:-}"
    local file_pattern="${2:-}"
    local limit="${3:-$MAX_INSIGHTS_IN_PROMPT}"

    if command -v sqlite3 &>/dev/null && [[ -f "$INSIGHTS_DB" ]]; then
        local where_clause="WHERE confidence >= $INSIGHT_MIN_CONFIDENCE"

        if [[ -n "$failure_type" ]]; then
            where_clause="$where_clause AND failure_type = '$failure_type'"
        fi

        sqlite3 -json "$INSIGHTS_DB" <<EOF
SELECT pattern, failure_type, description, root_cause, solution, code_hint, confidence
FROM insights
$where_clause
ORDER BY confidence DESC, times_successful DESC
LIMIT $limit;
EOF
    else
        # JSON fallback
        local insights_file="${LEARNING_DIR}/insights.json"
        if [[ -f "$insights_file" ]]; then
            local filter=".[] | select(.confidence >= $INSIGHT_MIN_CONFIDENCE)"
            if [[ -n "$failure_type" ]]; then
                filter="$filter | select(.failure_type == \"$failure_type\")"
            fi

            cat "$insights_file" | jq "[$filter] | sort_by(-.confidence) | .[:$limit]"
        else
            echo "[]"
        fi
    fi
}

# Record insight application result
# Usage: record_insight_application <pattern> <session_id> <agent_id> <iteration> <was_successful> [notes]
record_insight_application() {
    local pattern="$1"
    local session_id="$2"
    local agent_id="$3"
    local iteration="$4"
    local was_successful="$5"
    local notes="${6:-}"

    if command -v sqlite3 &>/dev/null && [[ -f "$INSIGHTS_DB" ]]; then
        # Get insight ID
        local insight_id
        insight_id=$(sqlite3 "$INSIGHTS_DB" "SELECT id FROM insights WHERE pattern = '$pattern';")

        if [[ -n "$insight_id" ]]; then
            # Record application
            sqlite3 "$INSIGHTS_DB" <<EOF
INSERT INTO insight_applications (insight_id, session_id, agent_id, iteration, was_successful, notes)
VALUES ($insight_id, '$session_id', '$agent_id', $iteration, $was_successful, '$notes');

-- Update insight statistics
UPDATE insights SET
    times_applied = times_applied + 1,
    times_successful = times_successful + CASE WHEN $was_successful THEN 1 ELSE 0 END,
    confidence = (times_successful + 1.0) / (times_applied + 2.0),  -- Bayesian update
    last_applied = CURRENT_TIMESTAMP
WHERE id = $insight_id;
EOF
            echo "Recorded insight application: $pattern (success: $was_successful)"
        fi
    else
        # JSON fallback - just log it
        echo "Insight applied: $pattern (success: $was_successful)"
    fi
}

# =============================================================================
# Prompt Injection
# =============================================================================

# Generate insights section for prompt injection
# Usage: generate_insights_prompt [failure_type] [file_pattern]
generate_insights_prompt() {
    local failure_type="${1:-}"
    local file_pattern="${2:-}"

    local insights
    insights=$(get_relevant_insights "$failure_type" "$file_pattern")

    if [[ "$insights" == "[]" || -z "$insights" ]]; then
        return 0
    fi

    cat << 'EOF'

## LEARNED INSIGHTS FROM PREVIOUS FAILURES

The following insights were learned from previous failures in this project.
Apply these learnings to avoid repeating past mistakes:

EOF

    local count=1
    echo "$insights" | jq -r '.[] | @base64' | while read -r insight_b64; do
        local insight
        insight=$(echo "$insight_b64" | base64 -d 2>/dev/null || echo "$insight_b64" | base64 -D 2>/dev/null)

        local pattern description root_cause solution code_hint confidence
        pattern=$(echo "$insight" | jq -r '.pattern')
        description=$(echo "$insight" | jq -r '.description')
        root_cause=$(echo "$insight" | jq -r '.root_cause // empty')
        solution=$(echo "$insight" | jq -r '.solution')
        code_hint=$(echo "$insight" | jq -r '.code_hint // empty')
        confidence=$(echo "$insight" | jq -r '.confidence // 0.5')

        echo "### Insight #${count}: ${pattern}"
        echo "- **Pattern**: ${description}"
        if [[ -n "$root_cause" ]]; then
            echo "- **Root Cause**: ${root_cause}"
        fi
        echo "- **Solution**: ${solution}"
        if [[ -n "$code_hint" ]]; then
            echo "- **Code Example**:"
            echo '```'
            echo "$code_hint"
            echo '```'
        fi
        echo "- **Confidence**: $(echo "$confidence * 100" | bc)%"
        echo ""

        count=$((count + 1))
    done
}

# Inject insights into a prompt
# Usage: inject_insights_into_prompt <original_prompt> [failure_type] [file_pattern]
inject_insights_into_prompt() {
    local original_prompt="$1"
    local failure_type="${2:-}"
    local file_pattern="${3:-}"

    local insights_section
    insights_section=$(generate_insights_prompt "$failure_type" "$file_pattern")

    if [[ -z "$insights_section" ]]; then
        echo "$original_prompt"
        return 0
    fi

    # Insert insights before the main task section
    if echo "$original_prompt" | grep -q "## YOUR TASK"; then
        echo "$original_prompt" | sed "/## YOUR TASK/i\\
$insights_section
"
    else
        # Append at the end if no task section found
        echo "$original_prompt"
        echo ""
        echo "$insights_section"
    fi
}

# =============================================================================
# Analysis Functions
# =============================================================================

# Analyze recent failures and suggest insights
# Usage: analyze_failures [session_id] [limit]
analyze_failures() {
    local session_id="${1:-}"
    local limit="${2:-10}"

    local failures

    if command -v sqlite3 &>/dev/null && [[ -f "$INSIGHTS_DB" ]]; then
        local where_clause=""
        if [[ -n "$session_id" ]]; then
            where_clause="WHERE session_id = '$session_id'"
        fi

        failures=$(sqlite3 -json "$INSIGHTS_DB" <<EOF
SELECT failure_type, error_message, affected_files, COUNT(*) as occurrences
FROM failures
$where_clause
GROUP BY failure_type, error_message
ORDER BY occurrences DESC
LIMIT $limit;
EOF
)
    else
        # JSON fallback
        if [[ -f "$FAILURES_LOG" ]]; then
            failures=$(cat "$FAILURES_LOG" | jq \
                'group_by(.failure_type, .error_message)
                | map({
                    failure_type: .[0].failure_type,
                    error_message: .[0].error_message,
                    affected_files: [.[].affected_files[]] | unique,
                    occurrences: length
                })
                | sort_by(-.occurrences)
                | .[:'"$limit"']')
        else
            failures="[]"
        fi
    fi

    echo "$failures"
}

# Get failure statistics
# Usage: get_failure_stats [session_id]
get_failure_stats() {
    local session_id="${1:-}"

    if command -v sqlite3 &>/dev/null && [[ -f "$INSIGHTS_DB" ]]; then
        local where_clause=""
        if [[ -n "$session_id" ]]; then
            where_clause="WHERE session_id = '$session_id'"
        fi

        sqlite3 -json "$INSIGHTS_DB" <<EOF
SELECT
    failure_type,
    COUNT(*) as total,
    COUNT(DISTINCT session_id) as sessions_affected
FROM failures
$where_clause
GROUP BY failure_type
ORDER BY total DESC;
EOF
    else
        # JSON fallback
        if [[ -f "$FAILURES_LOG" ]]; then
            cat "$FAILURES_LOG" | jq '
                group_by(.failure_type)
                | map({
                    failure_type: .[0].failure_type,
                    total: length,
                    sessions_affected: ([.[].session_id] | unique | length)
                })
                | sort_by(-.total)'
        else
            echo "[]"
        fi
    fi
}

# Get insight effectiveness report
# Usage: get_insight_effectiveness
get_insight_effectiveness() {
    if command -v sqlite3 &>/dev/null && [[ -f "$INSIGHTS_DB" ]]; then
        sqlite3 -json "$INSIGHTS_DB" <<'EOF'
SELECT
    pattern,
    failure_type,
    times_applied,
    times_successful,
    ROUND(confidence * 100, 1) as confidence_percent,
    last_applied
FROM insights
WHERE times_applied > 0
ORDER BY confidence DESC;
EOF
    else
        # JSON fallback
        local insights_file="${LEARNING_DIR}/insights.json"
        if [[ -f "$insights_file" ]]; then
            cat "$insights_file" | jq '[.[] | select(.times_applied > 0) | {
                pattern: .pattern,
                failure_type: .failure_type,
                times_applied: .times_applied,
                times_successful: .times_successful,
                confidence_percent: (.confidence * 100 | round)
            }] | sort_by(-.confidence_percent)'
        else
            echo "[]"
        fi
    fi
}

# =============================================================================
# Pre-built Insights
# =============================================================================

# Install common pre-built insights
# Usage: install_prebuilt_insights
install_prebuilt_insights() {
    # JWT expiration check
    create_insight \
        "jwt_expiration_check" \
        "test_failure" \
        "Test failures related to JWT token expiration" \
        "Always validate token expiration by checking decoded.exp < Date.now()/1000 before accepting tokens" \
        "Missing expiration validation in token verification" \
        'if (decoded.exp && decoded.exp < Date.now() / 1000) {
    throw new TokenExpiredError("Token has expired");
}' \
        "**/auth/**"

    # Database connection pool
    create_insight \
        "db_connection_pool" \
        "test_failure" \
        "Intermittent test failures with connection refused or pool exhaustion" \
        "Use poolSize: 5 in test config and add afterAll(() => pool.end()) to cleanup connections" \
        "Database connection pool exhaustion during parallel tests" \
        'afterAll(async () => {
    await pool.end();
});' \
        "**/db/**"

    # Async/await error handling
    create_insight \
        "async_error_handling" \
        "test_failure" \
        "Unhandled promise rejections in async tests" \
        "Always use try/catch in async functions and await expect().rejects for error testing" \
        "Missing error handling in async operations" \
        'await expect(asyncFunction()).rejects.toThrow(ExpectedError);' \
        "**/*.test.*"

    # TypeScript strict null checks
    create_insight \
        "ts_null_checks" \
        "type_error" \
        "TypeScript errors about potentially undefined values" \
        "Use optional chaining (?.) and nullish coalescing (??) operators, or add explicit null checks" \
        "Accessing properties on potentially undefined objects" \
        'const value = obj?.property ?? defaultValue;' \
        "**/*.ts"

    # ESLint unused variables
    create_insight \
        "eslint_unused_vars" \
        "lint_error" \
        "ESLint errors for unused variables" \
        "Prefix intentionally unused variables with underscore (_) or remove them entirely" \
        "Variables declared but not used in code" \
        'const [_ignored, usedValue] = someArray;' \
        "**/*.{ts,js}"

    # Python import order
    create_insight \
        "python_import_order" \
        "lint_error" \
        "Ruff/isort errors about import ordering" \
        "Follow import order: stdlib, third-party, local. Use absolute imports for local modules." \
        "Incorrect import statement ordering" \
        '# Standard library
import os

# Third-party
import fastapi

# Local
from ai_tutor_api.services import AuthService' \
        "**/*.py"

    echo "Installed pre-built insights"
}

# =============================================================================
# CLI Interface
# =============================================================================

learning_cli() {
    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        init)
            init_learning_db
            ;;
        capture)
            capture_failure "${1:-}" "${2:-}" "${3:-0}" "${4:-}" "${5:-}" "${6:-"[]"}" "${7:-"{}"}"
            ;;
        parse-ci)
            if [[ -n "${1:-}" ]]; then
                parse_ci_failure "$1"
            else
                parse_ci_failure ""
            fi
            ;;
        parse-review)
            parse_review_rejection "${1:-}" "${2:-}"
            ;;
        create-insight)
            create_insight "${1:-}" "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}" "${7:-}"
            ;;
        get-insights)
            get_relevant_insights "${1:-}" "${2:-}" "${3:-}"
            ;;
        record-application)
            record_insight_application "${1:-}" "${2:-}" "${3:-}" "${4:-0}" "${5:-false}" "${6:-}"
            ;;
        generate-prompt)
            generate_insights_prompt "${1:-}" "${2:-}"
            ;;
        inject)
            inject_insights_into_prompt "${1:-}" "${2:-}" "${3:-}"
            ;;
        analyze)
            analyze_failures "${1:-}" "${2:-10}"
            ;;
        stats)
            get_failure_stats "${1:-}"
            ;;
        effectiveness)
            get_insight_effectiveness
            ;;
        install-prebuilt)
            install_prebuilt_insights
            ;;
        help|*)
            echo "Usage: learning.sh <command> [args]"
            echo ""
            echo "Database Commands:"
            echo "  init                              Initialize learning database"
            echo "  install-prebuilt                  Install pre-built common insights"
            echo ""
            echo "Capture Commands:"
            echo "  capture <session> <agent> <iter> <type> <msg> [files] [ctx]"
            echo "                                    Capture a failure event"
            echo "  parse-ci <log_file>               Parse CI log for failures"
            echo "  parse-review <pr_number> [repo]   Parse PR review rejections"
            echo ""
            echo "Insight Commands:"
            echo "  create-insight <pattern> <type> <desc> <solution> [cause] [hint] [files]"
            echo "                                    Create or update an insight"
            echo "  get-insights [type] [pattern] [limit]"
            echo "                                    Get relevant insights"
            echo "  record-application <pattern> <session> <agent> <iter> <success> [notes]"
            echo "                                    Record insight application result"
            echo ""
            echo "Prompt Commands:"
            echo "  generate-prompt [type] [pattern]  Generate insights prompt section"
            echo "  inject <prompt> [type] [pattern]  Inject insights into prompt"
            echo ""
            echo "Analysis Commands:"
            echo "  analyze [session_id] [limit]      Analyze recent failures"
            echo "  stats [session_id]                Get failure statistics"
            echo "  effectiveness                     Get insight effectiveness report"
            ;;
    esac
}

# Run CLI if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    learning_cli "$@"
fi
