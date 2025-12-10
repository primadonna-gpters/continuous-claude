#!/usr/bin/env bash
# =============================================================================
# personas.sh - Persona Management System
# =============================================================================
# Provides functions to load, validate, and manage agent personas.
# Personas define agent roles, responsibilities, and communication patterns.
# =============================================================================

# Persona directory
PERSONAS_DIR="${PERSONAS_DIR:-personas}"

# Cache for loaded personas (using file-based cache for bash 3 compatibility)
PERSONA_CACHE_DIR="${TMPDIR:-/tmp}/continuous-claude-persona-cache"
mkdir -p "$PERSONA_CACHE_DIR" 2>/dev/null || true

# =============================================================================
# YAML Parsing (using yq if available, otherwise basic parsing)
# =============================================================================

# Check if yq is available
has_yq() {
    command -v yq &> /dev/null
}

# Parse a YAML value using yq or fallback
# Usage: yaml_get <file> <path>
yaml_get() {
    local file="$1"
    local path="$2"

    if has_yq; then
        yq eval "$path" "$file" 2>/dev/null
    else
        # Basic fallback for simple paths like .persona.id
        # This handles single-level nested values
        local key="${path##*.}"
        grep -E "^\s*${key}:" "$file" | head -1 | sed 's/.*:\s*//' | tr -d '"' | tr -d "'"
    fi
}

# Parse YAML array to JSON array
# Usage: yaml_get_array <file> <path>
yaml_get_array() {
    local file="$1"
    local path="$2"

    if has_yq; then
        yq eval "$path | @json" "$file" 2>/dev/null
    else
        # Basic fallback - extract indented list items
        local key="${path##*.}"
        local in_section=0
        local result="["
        local first=1

        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*${key}: ]]; then
                in_section=1
                continue
            fi
            if [[ $in_section -eq 1 ]]; then
                if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*(.*) ]]; then
                    local item="${BASH_REMATCH[1]}"
                    item="${item%\"}"
                    item="${item#\"}"
                    if [[ $first -eq 0 ]]; then
                        result+=","
                    fi
                    result+="\"${item}\""
                    first=0
                elif [[ "$line" =~ ^[[:space:]]*[a-z_]+: ]]; then
                    break
                fi
            fi
        done < "$file"

        result+="]"
        echo "$result"
    fi
}

# =============================================================================
# Persona Loading
# =============================================================================

# Load a persona from YAML file
# Usage: load_persona <persona_id>
load_persona() {
    local persona_id="$1"
    local persona_file="${PERSONAS_DIR}/${persona_id}.yaml"

    if [[ ! -f "$persona_file" ]]; then
        echo "Error: Persona file not found: ${persona_file}" >&2
        return 1
    fi

    # Check cache (file-based)
    local cache_file="${PERSONA_CACHE_DIR}/${persona_id}.json"
    if [[ -f "$cache_file" ]]; then
        cat "$cache_file"
        return 0
    fi

    # Parse persona data
    local id name emoji role

    if has_yq; then
        id=$(yq eval '.persona.id' "$persona_file")
        name=$(yq eval '.persona.name' "$persona_file")
        emoji=$(yq eval '.persona.emoji' "$persona_file")
        role=$(yq eval '.persona.role' "$persona_file")
    else
        # Extract values and trim whitespace
        id=$(grep -E "^[[:space:]]*id:" "$persona_file" | head -1 | sed 's/.*:[[:space:]]*//' | tr -d '"' | xargs)
        name=$(grep -E "^[[:space:]]*name:" "$persona_file" | head -1 | sed 's/.*:[[:space:]]*//' | tr -d '"' | xargs)
        emoji=$(grep -E "^[[:space:]]*emoji:" "$persona_file" | head -1 | sed 's/.*:[[:space:]]*//' | tr -d '"' | xargs)
        # Extract multiline role (everything after "role: |" until next key)
        role=$(awk '/^[[:space:]]*role:[[:space:]]*\|/{found=1; next} found && /^[[:space:]]*[a-z_]+:/{exit} found{gsub(/^[[:space:]]+/, ""); printf "%s ", $0}' "$persona_file" | sed 's/[[:space:]]*$//')
    fi

    # Build JSON representation
    local json
    json=$(jq -n \
        --arg id "$id" \
        --arg name "$name" \
        --arg emoji "$emoji" \
        --arg role "$role" \
        --arg file "$persona_file" \
        '{
            id: $id,
            name: $name,
            emoji: $emoji,
            role: $role,
            file: $file
        }'
    )

    # Cache the result (file-based)
    echo "$json" > "$cache_file"

    echo "$json"
}

# Load all available personas
# Usage: load_all_personas
load_all_personas() {
    local personas="[]"

    for persona_file in "${PERSONAS_DIR}"/*.yaml; do
        [[ -f "$persona_file" ]] || continue

        local persona_id
        persona_id=$(basename "$persona_file" .yaml)

        local persona
        persona=$(load_persona "$persona_id")

        if [[ -n "$persona" ]]; then
            personas=$(echo "$personas" | jq --argjson p "$persona" '. + [$p]')
        fi
    done

    echo "$personas"
}

# Get list of available persona IDs
# Usage: list_personas
list_personas() {
    local ids=""
    for persona_file in "${PERSONAS_DIR}"/*.yaml; do
        [[ -f "$persona_file" ]] || continue
        local id
        id=$(basename "$persona_file" .yaml)
        if [[ -n "$ids" ]]; then
            ids+=" "
        fi
        ids+="$id"
    done
    echo "$ids"
}

# =============================================================================
# Persona Properties
# =============================================================================

# Get persona ID
# Usage: get_persona_id <persona_json>
get_persona_id() {
    echo "$1" | jq -r '.id'
}

# Get persona name
# Usage: get_persona_name <persona_json>
get_persona_name() {
    echo "$1" | jq -r '.name'
}

# Get persona emoji
# Usage: get_persona_emoji <persona_json>
get_persona_emoji() {
    echo "$1" | jq -r '.emoji'
}

# Get persona role description
# Usage: get_persona_role <persona_json>
get_persona_role() {
    echo "$1" | jq -r '.role'
}

# Get persona responsibilities (from YAML file)
# Usage: get_persona_responsibilities <persona_id>
get_persona_responsibilities() {
    local persona_id="$1"
    local persona_file="${PERSONAS_DIR}/${persona_id}.yaml"

    yaml_get_array "$persona_file" ".persona.responsibilities"
}

# Get persona constraints (from YAML file)
# Usage: get_persona_constraints <persona_id>
get_persona_constraints() {
    local persona_id="$1"
    local persona_file="${PERSONAS_DIR}/${persona_id}.yaml"

    yaml_get_array "$persona_file" ".persona.constraints"
}

# Get messages this persona listens to
# Usage: get_persona_listens_to <persona_id>
get_persona_listens_to() {
    local persona_id="$1"
    local persona_file="${PERSONAS_DIR}/${persona_id}.yaml"

    yaml_get_array "$persona_file" ".persona.communication.listens_to"
}

# Get messages this persona publishes
# Usage: get_persona_publishes <persona_id>
get_persona_publishes() {
    local persona_id="$1"
    local persona_file="${PERSONAS_DIR}/${persona_id}.yaml"

    yaml_get_array "$persona_file" ".persona.communication.publishes"
}

# Get allowed tools for this persona
# Usage: get_persona_allowed_tools <persona_id>
get_persona_allowed_tools() {
    local persona_id="$1"
    local persona_file="${PERSONAS_DIR}/${persona_id}.yaml"

    yaml_get_array "$persona_file" ".persona.tools.allowed"
}

# Get denied tools for this persona
# Usage: get_persona_denied_tools <persona_id>
get_persona_denied_tools() {
    local persona_id="$1"
    local persona_file="${PERSONAS_DIR}/${persona_id}.yaml"

    yaml_get_array "$persona_file" ".persona.tools.denied"
}

# =============================================================================
# Persona Validation
# =============================================================================

# Validate a persona file
# Usage: validate_persona <persona_id>
validate_persona() {
    local persona_id="$1"
    local persona_file="${PERSONAS_DIR}/${persona_id}.yaml"
    local errors=()

    if [[ ! -f "$persona_file" ]]; then
        echo "Error: Persona file not found: ${persona_file}" >&2
        return 1
    fi

    # Check required fields
    local id name emoji role

    if has_yq; then
        id=$(yq eval '.persona.id' "$persona_file")
        name=$(yq eval '.persona.name' "$persona_file")
        emoji=$(yq eval '.persona.emoji' "$persona_file")
        role=$(yq eval '.persona.role' "$persona_file")
    else
        id=$(grep -E "^\s*id:" "$persona_file" | head -1 | sed 's/.*:\s*//')
        name=$(grep -E "^\s*name:" "$persona_file" | head -1 | sed 's/.*:\s*//')
        emoji=$(grep -E "^\s*emoji:" "$persona_file" | head -1 | sed 's/.*:\s*//')
        role=$(grep -E "^\s*role:" "$persona_file" | head -1)
    fi

    if [[ -z "$id" || "$id" == "null" ]]; then
        errors+=("Missing required field: persona.id")
    fi
    if [[ -z "$name" || "$name" == "null" ]]; then
        errors+=("Missing required field: persona.name")
    fi
    if [[ -z "$emoji" || "$emoji" == "null" ]]; then
        errors+=("Missing required field: persona.emoji")
    fi
    if [[ -z "$role" ]]; then
        errors+=("Missing required field: persona.role")
    fi

    # Report errors
    if [[ ${#errors[@]} -gt 0 ]]; then
        echo "Validation errors for ${persona_id}:" >&2
        for err in "${errors[@]}"; do
            echo "  - ${err}" >&2
        done
        return 1
    fi

    echo "Persona ${persona_id} is valid"
    return 0
}

# Validate all personas
# Usage: validate_all_personas
validate_all_personas() {
    local all_valid=0

    for persona_file in "${PERSONAS_DIR}"/*.yaml; do
        [[ -f "$persona_file" ]] || continue

        local persona_id
        persona_id=$(basename "$persona_file" .yaml)

        if ! validate_persona "$persona_id"; then
            all_valid=1
        fi
    done

    return $all_valid
}

# =============================================================================
# Prompt Generation
# =============================================================================

# Generate a system prompt for a persona
# Usage: generate_persona_prompt <persona_id>
generate_persona_prompt() {
    local persona_id="$1"
    local persona
    persona=$(load_persona "$persona_id")

    if [[ -z "$persona" ]]; then
        echo "Error: Could not load persona: ${persona_id}" >&2
        return 1
    fi

    local name emoji role
    name=$(get_persona_name "$persona")
    emoji=$(get_persona_emoji "$persona")
    role=$(get_persona_role "$persona")

    local responsibilities constraints listens_to publishes
    responsibilities=$(get_persona_responsibilities "$persona_id")
    constraints=$(get_persona_constraints "$persona_id")
    listens_to=$(get_persona_listens_to "$persona_id")
    publishes=$(get_persona_publishes "$persona_id")

    # Build the prompt
    cat << EOF
## AGENT PERSONA: ${emoji} ${name}

### Role
${role}

### Responsibilities
$(echo "$responsibilities" | jq -r '.[] | "- " + .')

### Constraints
$(echo "$constraints" | jq -r '.[] | "- " + .')

### Communication
You listen for these message types:
$(echo "$listens_to" | jq -r '.[] | "- " + .')

You can publish these message types:
$(echo "$publishes" | jq -r '.[] | "- " + .')

### Behavior Guidelines
1. Stay in character as the ${name}
2. Focus only on your assigned responsibilities
3. Communicate clearly with other agents through the messaging system
4. Report completion or blockers using the appropriate signals
5. Do not perform actions outside your allowed tools
EOF
}

# Generate a short status line for a persona
# Usage: generate_persona_status <persona_id> [status]
generate_persona_status() {
    local persona_id="$1"
    local status="${2:-idle}"
    local persona
    persona=$(load_persona "$persona_id")

    local emoji name
    emoji=$(get_persona_emoji "$persona")
    name=$(get_persona_name "$persona")

    echo "${emoji} ${name} [${status}]"
}

# =============================================================================
# Utility Functions
# =============================================================================

# Print persona summary
# Usage: print_persona_summary <persona_id>
print_persona_summary() {
    local persona_id="$1"
    local persona
    persona=$(load_persona "$persona_id")

    if [[ -z "$persona" ]]; then
        echo "Error: Could not load persona: ${persona_id}" >&2
        return 1
    fi

    local emoji name role
    emoji=$(get_persona_emoji "$persona")
    name=$(get_persona_name "$persona")
    role=$(get_persona_role "$persona")

    echo "╭─────────────────────────────────────────╮"
    echo "│ ${emoji} ${name}"
    echo "├─────────────────────────────────────────┤"
    echo "│ ${role:0:40}..."
    echo "╰─────────────────────────────────────────╯"
}

# Print all personas as a table
# Usage: print_personas_table
print_personas_table() {
    echo "╭───────────────────────────────────────────────────────────────╮"
    echo "│                    Available Personas                         │"
    echo "├────────┬────────────────────────┬────────────────────────────┤"
    echo "│ Emoji  │ ID                     │ Name                       │"
    echo "├────────┼────────────────────────┼────────────────────────────┤"

    for persona_file in "${PERSONAS_DIR}"/*.yaml; do
        [[ -f "$persona_file" ]] || continue

        local persona_id
        persona_id=$(basename "$persona_file" .yaml)

        local persona
        persona=$(load_persona "$persona_id")

        local emoji name
        emoji=$(get_persona_emoji "$persona")
        name=$(get_persona_name "$persona")

        printf "│ %-6s │ %-22s │ %-26s │\n" "$emoji" "$persona_id" "$name"
    done

    echo "╰────────┴────────────────────────┴────────────────────────────╯"
}

# Clear persona cache
# Usage: clear_persona_cache
clear_persona_cache() {
    rm -rf "${PERSONA_CACHE_DIR}"/*.json 2>/dev/null || true
    echo "Persona cache cleared"
}

# =============================================================================
# CLI Interface
# =============================================================================

# Main CLI handler
personas_cli() {
    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        list)
            print_personas_table
            ;;
        load)
            load_persona "${1:-}"
            ;;
        validate)
            if [[ -n "${1:-}" ]]; then
                validate_persona "$1"
            else
                validate_all_personas
            fi
            ;;
        prompt)
            generate_persona_prompt "${1:-}"
            ;;
        summary)
            print_persona_summary "${1:-}"
            ;;
        help|*)
            echo "Usage: personas.sh <command> [args]"
            echo ""
            echo "Commands:"
            echo "  list                     List all available personas"
            echo "  load <persona_id>        Load and display persona JSON"
            echo "  validate [persona_id]    Validate persona(s)"
            echo "  prompt <persona_id>      Generate system prompt for persona"
            echo "  summary <persona_id>     Print persona summary"
            echo "  help                     Show this help message"
            ;;
    esac
}

# Run CLI if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    personas_cli "$@"
fi
