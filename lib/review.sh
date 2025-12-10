#!/usr/bin/env bash
# =============================================================================
# review.sh - Code Review Agent System
# =============================================================================
# Automated code review functionality including static analysis integration,
# AI-powered review generation, and GitHub PR interaction.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Configuration
# =============================================================================

REVIEW_CONFIG_FILE="${REVIEW_CONFIG_FILE:-.continuous-claude/review-config.json}"
REVIEW_CACHE_DIR="${TMPDIR:-/tmp}/continuous-claude-review-cache"
mkdir -p "$REVIEW_CACHE_DIR" 2>/dev/null || true

# Review severity levels
SEVERITY_BLOCKER="blocker"    # Must fix before merge
SEVERITY_MAJOR="major"        # Should fix, may approve with commitment
SEVERITY_MINOR="minor"        # Nice to have, can merge as-is
SEVERITY_SUGGESTION="suggestion"  # Consider for future improvement

# =============================================================================
# Review Criteria Configuration
# =============================================================================

# Get default review criteria
get_default_review_criteria() {
    cat << 'EOF'
{
    "code_quality": {
        "enabled": true,
        "checks": [
            "Clean code principles",
            "SOLID principles adherence",
            "DRY (Don't Repeat Yourself)",
            "Appropriate naming conventions",
            "Code complexity (cyclomatic)"
        ]
    },
    "security": {
        "enabled": true,
        "checks": [
            "Input validation",
            "SQL injection prevention",
            "XSS prevention",
            "Authentication/Authorization",
            "Sensitive data handling"
        ]
    },
    "performance": {
        "enabled": true,
        "checks": [
            "Algorithm efficiency",
            "Memory usage",
            "Database query optimization",
            "Caching opportunities"
        ]
    },
    "maintainability": {
        "enabled": true,
        "checks": [
            "Documentation quality",
            "Test coverage",
            "Error handling",
            "Logging adequacy"
        ]
    }
}
EOF
}

# Load review configuration
load_review_config() {
    if [[ -f "$REVIEW_CONFIG_FILE" ]]; then
        cat "$REVIEW_CONFIG_FILE"
    else
        get_default_review_criteria
    fi
}

# =============================================================================
# Static Analysis Integration
# =============================================================================

# Run ESLint on JavaScript/TypeScript files
# Usage: run_eslint <files...>
run_eslint() {
    local files=("$@")

    if ! command -v npx &>/dev/null; then
        echo '{"tool": "eslint", "error": "npx not available"}' >&2
        return 1
    fi

    local results
    results=$(npx eslint --format json "${files[@]}" 2>/dev/null || true)

    if [[ -n "$results" ]]; then
        echo "$results" | jq '{
            tool: "eslint",
            files_checked: length,
            errors: [.[].messages[] | select(.severity == 2)] | length,
            warnings: [.[].messages[] | select(.severity == 1)] | length,
            issues: [.[].messages | .[] | {
                file: input_filename,
                line: .line,
                column: .column,
                severity: (if .severity == 2 then "error" else "warning" end),
                message: .message,
                rule: .ruleId
            }]
        }'
    else
        echo '{"tool": "eslint", "files_checked": 0, "errors": 0, "warnings": 0, "issues": []}'
    fi
}

# Run Ruff on Python files
# Usage: run_ruff <files...>
run_ruff() {
    local files=("$@")

    if ! command -v ruff &>/dev/null; then
        echo '{"tool": "ruff", "error": "ruff not available"}' >&2
        return 1
    fi

    local results
    results=$(ruff check --output-format json "${files[@]}" 2>/dev/null || true)

    if [[ -n "$results" ]]; then
        echo "$results" | jq '{
            tool: "ruff",
            files_checked: ([.[].filename] | unique | length),
            errors: [.[] | select(.fix == null)] | length,
            warnings: [.[] | select(.fix != null)] | length,
            issues: [.[] | {
                file: .filename,
                line: .location.row,
                column: .location.column,
                severity: (if .fix == null then "error" else "warning" end),
                message: .message,
                rule: .code
            }]
        }'
    else
        echo '{"tool": "ruff", "files_checked": 0, "errors": 0, "warnings": 0, "issues": []}'
    fi
}

# Run TypeScript type checking
# Usage: run_typecheck <files...>
run_typecheck() {
    local files=("$@")

    if ! command -v npx &>/dev/null; then
        echo '{"tool": "typescript", "error": "npx not available"}' >&2
        return 1
    fi

    local errors=0
    local issues="[]"

    # Run tsc and capture output
    local output
    output=$(npx tsc --noEmit 2>&1 || true)

    if echo "$output" | grep -qE "error TS[0-9]+"; then
        errors=$(echo "$output" | grep -cE "error TS[0-9]+" || echo 0)
        issues=$(echo "$output" | grep -E "error TS[0-9]+" | head -10 | jq -R -s 'split("\n") | map(select(length > 0)) | map({message: .})')
    fi

    jq -n \
        --argjson errors "$errors" \
        --argjson issues "$issues" \
        '{
            tool: "typescript",
            errors: $errors,
            warnings: 0,
            issues: $issues
        }'
}

# Run all applicable static analysis
# Usage: run_static_analysis <directory>
run_static_analysis() {
    local directory="${1:-.}"
    local results="[]"

    # Find files by type
    local js_files ts_files py_files

    js_files=$(find "$directory" -name "*.js" -o -name "*.jsx" 2>/dev/null | head -50)
    ts_files=$(find "$directory" -name "*.ts" -o -name "*.tsx" 2>/dev/null | head -50)
    py_files=$(find "$directory" -name "*.py" 2>/dev/null | head -50)

    # Run ESLint for JS/TS
    if [[ -n "$js_files" || -n "$ts_files" ]]; then
        local eslint_result
        eslint_result=$(run_eslint $js_files $ts_files 2>/dev/null)
        if [[ -n "$eslint_result" ]]; then
            results=$(echo "$results" | jq --argjson r "$eslint_result" '. + [$r]')
        fi
    fi

    # Run TypeScript check
    if [[ -n "$ts_files" ]]; then
        local ts_result
        ts_result=$(run_typecheck $ts_files 2>/dev/null)
        if [[ -n "$ts_result" ]]; then
            results=$(echo "$results" | jq --argjson r "$ts_result" '. + [$r]')
        fi
    fi

    # Run Ruff for Python
    if [[ -n "$py_files" ]]; then
        local ruff_result
        ruff_result=$(run_ruff $py_files 2>/dev/null)
        if [[ -n "$ruff_result" ]]; then
            results=$(echo "$results" | jq --argjson r "$ruff_result" '. + [$r]')
        fi
    fi

    echo "$results"
}

# =============================================================================
# PR Review Functions
# =============================================================================

# Get PR diff
# Usage: get_pr_diff <pr_number> [repo]
get_pr_diff() {
    local pr_number="$1"
    local repo="${2:-}"

    if ! command -v gh &>/dev/null; then
        echo "Error: gh CLI not available" >&2
        return 1
    fi

    local repo_arg=""
    if [[ -n "$repo" ]]; then
        repo_arg="--repo $repo"
    fi

    gh pr diff "$pr_number" $repo_arg 2>/dev/null
}

# Get PR files changed
# Usage: get_pr_files <pr_number> [repo]
get_pr_files() {
    local pr_number="$1"
    local repo="${2:-}"

    if ! command -v gh &>/dev/null; then
        echo "Error: gh CLI not available" >&2
        return 1
    fi

    local repo_arg=""
    if [[ -n "$repo" ]]; then
        repo_arg="--repo $repo"
    fi

    gh pr view "$pr_number" $repo_arg --json files -q '.files[].path' 2>/dev/null
}

# Get PR details
# Usage: get_pr_details <pr_number> [repo]
get_pr_details() {
    local pr_number="$1"
    local repo="${2:-}"

    if ! command -v gh &>/dev/null; then
        echo "Error: gh CLI not available" >&2
        return 1
    fi

    local repo_arg=""
    if [[ -n "$repo" ]]; then
        repo_arg="--repo $repo"
    fi

    gh pr view "$pr_number" $repo_arg --json number,title,body,author,state,additions,deletions,files,headRefName,baseRefName 2>/dev/null
}

# =============================================================================
# Review Generation
# =============================================================================

# Generate review findings structure
# Usage: create_review_finding <severity> <category> <file> <line> <message> [suggestion]
create_review_finding() {
    local severity="$1"
    local category="$2"
    local file="$3"
    local line="$4"
    local message="$5"
    local suggestion="${6:-}"

    jq -n \
        --arg sev "$severity" \
        --arg cat "$category" \
        --arg file "$file" \
        --argjson line "$line" \
        --arg msg "$message" \
        --arg sug "$suggestion" \
        '{
            severity: $sev,
            category: $cat,
            file: $file,
            line: $line,
            message: $msg,
            suggestion: (if $sug == "" then null else $sug end)
        }'
}

# Aggregate findings into review report
# Usage: aggregate_findings <findings_json>
aggregate_findings() {
    local findings="$1"

    echo "$findings" | jq '
        {
            total: length,
            by_severity: group_by(.severity) | map({(.[0].severity): length}) | add,
            by_category: group_by(.category) | map({(.[0].category): length}) | add,
            blockers: [.[] | select(.severity == "blocker")],
            majors: [.[] | select(.severity == "major")],
            minors: [.[] | select(.severity == "minor")],
            suggestions: [.[] | select(.severity == "suggestion")]
        }
    '
}

# Determine review decision based on findings
# Usage: determine_decision <findings_json>
determine_decision() {
    local findings="$1"

    local blockers majors
    blockers=$(echo "$findings" | jq '[.[] | select(.severity == "blocker")] | length')
    majors=$(echo "$findings" | jq '[.[] | select(.severity == "major")] | length')

    if [[ "$blockers" -gt 0 ]]; then
        echo "REQUEST_CHANGES"
    elif [[ "$majors" -gt 2 ]]; then
        echo "REQUEST_CHANGES"
    elif [[ "$majors" -gt 0 ]]; then
        echo "COMMENT"
    else
        echo "APPROVE"
    fi
}

# Generate markdown review report
# Usage: generate_review_markdown <pr_number> <findings_json> <decision>
generate_review_markdown() {
    local pr_number="$1"
    local findings="$2"
    local decision="$3"

    local aggregated
    aggregated=$(aggregate_findings "$findings")

    local decision_emoji
    case "$decision" in
        APPROVE) decision_emoji="✅" ;;
        REQUEST_CHANGES) decision_emoji="🔴" ;;
        COMMENT) decision_emoji="🟡" ;;
        *) decision_emoji="⚪" ;;
    esac

    cat << EOF
## Code Review Summary

**PR**: #${pr_number}
**Reviewer**: 👁️ Code Review Agent
**Decision**: ${decision_emoji} ${decision}

---

### Overview

$(echo "$aggregated" | jq -r '
    "Total findings: \(.total)\n" +
    "- Blockers: \(.by_severity.blocker // 0)\n" +
    "- Major: \(.by_severity.major // 0)\n" +
    "- Minor: \(.by_severity.minor // 0)\n" +
    "- Suggestions: \(.by_severity.suggestion // 0)"
')

### Findings

$(echo "$aggregated" | jq -r '
    if .blockers | length > 0 then
        "#### 🔴 Blockers (\(.blockers | length))\n" +
        (.blockers | to_entries | map(
            "\(.key + 1). **[\(.value.category | ascii_upcase)]** \(.value.message)\n" +
            "   - File: `\(.value.file):\(.value.line)`\n" +
            (if .value.suggestion then "   - Suggestion: \(.value.suggestion)\n" else "" end)
        ) | join("\n"))
    else "" end
')

$(echo "$aggregated" | jq -r '
    if .majors | length > 0 then
        "#### 🟠 Major (\(.majors | length))\n" +
        (.majors | to_entries | map(
            "\(.key + 1). **[\(.value.category | ascii_upcase)]** \(.value.message)\n" +
            "   - File: `\(.value.file):\(.value.line)`"
        ) | join("\n"))
    else "" end
')

$(echo "$aggregated" | jq -r '
    if .minors | length > 0 then
        "#### 🟢 Minor (\(.minors | length))\n" +
        (.minors | to_entries | map(
            "\(.key + 1). \(.value.message) (`\(.value.file)`)"
        ) | join("\n"))
    else "" end
')

---

$(if [[ "$decision" == "REQUEST_CHANGES" ]]; then
    echo "### Required Actions"
    echo "$aggregated" | jq -r '.blockers | to_entries | map("- [ ] Fix: \(.value.message)") | join("\n")'
    echo ""
    echo "### Next Steps"
    echo "After fixes are applied, please notify for re-review."
fi)

---
*🤖 Generated by Code Review Agent*
EOF
}

# =============================================================================
# GitHub Integration
# =============================================================================

# Submit review to GitHub PR
# Usage: submit_pr_review <pr_number> <decision> <body> [repo]
submit_pr_review() {
    local pr_number="$1"
    local decision="$2"
    local body="$3"
    local repo="${4:-}"

    if ! command -v gh &>/dev/null; then
        echo "Error: gh CLI not available" >&2
        return 1
    fi

    local repo_arg=""
    if [[ -n "$repo" ]]; then
        repo_arg="--repo $repo"
    fi

    # Map decision to gh flag
    local review_flag
    case "$decision" in
        APPROVE) review_flag="--approve" ;;
        REQUEST_CHANGES) review_flag="--request-changes" ;;
        COMMENT) review_flag="--comment" ;;
        *) review_flag="--comment" ;;
    esac

    gh pr review "$pr_number" $repo_arg $review_flag --body "$body"
}

# Add inline comment to PR
# Usage: add_pr_comment <pr_number> <file> <line> <body> [repo]
add_pr_comment() {
    local pr_number="$1"
    local file="$2"
    local line="$3"
    local body="$4"
    local repo="${5:-}"

    if ! command -v gh &>/dev/null; then
        echo "Error: gh CLI not available" >&2
        return 1
    fi

    local repo_arg=""
    if [[ -n "$repo" ]]; then
        repo_arg="--repo $repo"
    fi

    # Use GitHub API to add review comment
    gh api \
        $repo_arg \
        "repos/{owner}/{repo}/pulls/${pr_number}/comments" \
        -f body="$body" \
        -f path="$file" \
        -F line="$line" \
        -f side="RIGHT"
}

# =============================================================================
# Main Review Function
# =============================================================================

# Perform automated code review
# Usage: review_pr <pr_number> [repo] [--submit]
review_pr() {
    local pr_number="$1"
    local repo="${2:-}"
    local submit="${3:-}"

    echo "🔍 Starting code review for PR #${pr_number}..."

    # Get PR details
    local pr_details
    pr_details=$(get_pr_details "$pr_number" "$repo")

    if [[ -z "$pr_details" ]]; then
        echo "Error: Could not fetch PR details" >&2
        return 1
    fi

    echo "  Title: $(echo "$pr_details" | jq -r '.title')"
    echo "  Files: $(echo "$pr_details" | jq '.files | length')"
    echo "  +$(echo "$pr_details" | jq '.additions') -$(echo "$pr_details" | jq '.deletions')"

    # Get changed files
    local files
    files=$(get_pr_files "$pr_number" "$repo")

    # Run static analysis on changed files (if we have local checkout)
    local static_results="[]"
    if [[ -d ".git" ]]; then
        echo "  Running static analysis..."
        static_results=$(run_static_analysis ".")
    fi

    # Convert static analysis to findings
    local findings="[]"
    for result in $(echo "$static_results" | jq -c '.[]'); do
        local tool issues
        tool=$(echo "$result" | jq -r '.tool')
        issues=$(echo "$result" | jq '.issues')

        for issue in $(echo "$issues" | jq -c '.[]'); do
            local file line message severity
            file=$(echo "$issue" | jq -r '.file // "unknown"')
            line=$(echo "$issue" | jq -r '.line // 0')
            message=$(echo "$issue" | jq -r '.message')
            severity=$(echo "$issue" | jq -r '.severity')

            # Map severity
            local mapped_severity="minor"
            if [[ "$severity" == "error" ]]; then
                mapped_severity="major"
            fi

            local finding
            finding=$(create_review_finding "$mapped_severity" "$tool" "$file" "$line" "$message")
            findings=$(echo "$findings" | jq --argjson f "$finding" '. + [$f]')
        done
    done

    # Determine decision
    local decision
    decision=$(determine_decision "$findings")

    echo "  Decision: $decision"
    echo "  Findings: $(echo "$findings" | jq 'length')"

    # Generate review markdown
    local review_body
    review_body=$(generate_review_markdown "$pr_number" "$findings" "$decision")

    # Output or submit review
    if [[ "$submit" == "--submit" ]]; then
        echo "  Submitting review..."
        submit_pr_review "$pr_number" "$decision" "$review_body" "$repo"
        echo "✅ Review submitted!"
    else
        echo ""
        echo "=== Review Preview ==="
        echo "$review_body"
        echo ""
        echo "To submit this review, run: review.sh pr $pr_number [repo] --submit"
    fi

    # Return decision for automation
    echo "$decision"
}

# =============================================================================
# CLI Interface
# =============================================================================

review_cli() {
    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        pr)
            review_pr "${1:-}" "${2:-}" "${3:-}"
            ;;
        diff)
            get_pr_diff "${1:-}" "${2:-}"
            ;;
        files)
            get_pr_files "${1:-}" "${2:-}"
            ;;
        static)
            run_static_analysis "${1:-.}"
            ;;
        criteria)
            load_review_config
            ;;
        help|*)
            echo "Usage: review.sh <command> [args]"
            echo ""
            echo "Review Commands:"
            echo "  pr <pr_number> [repo] [--submit]    Review a pull request"
            echo "  diff <pr_number> [repo]             Get PR diff"
            echo "  files <pr_number> [repo]            List PR changed files"
            echo ""
            echo "Analysis Commands:"
            echo "  static [directory]                  Run static analysis"
            echo "  criteria                            Show review criteria"
            echo ""
            echo "Examples:"
            echo "  review.sh pr 123                    Preview review for PR #123"
            echo "  review.sh pr 123 owner/repo --submit    Submit review"
            echo "  review.sh static ./src              Analyze src directory"
            ;;
    esac
}

# Run CLI if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    review_cli "$@"
fi
