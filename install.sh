#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - can be overridden with environment variables
REPO_OWNER="${REPO_OWNER:-primadonna-gpters}"
REPO_NAME="${REPO_NAME:-continuous-claude}"
REPO_BRANCH="${REPO_BRANCH:-main}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
LIB_INSTALL_DIR="${LIB_INSTALL_DIR:-$HOME/.local/share/continuous-claude}"
BINARY_NAME="continuous-claude"

REPO_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}"
GITHUB_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}"

echo "🔂 Installing Continuous Claude v2.0..."
echo "   Repository: ${GITHUB_URL}"
echo ""

# Create install directories
mkdir -p "$INSTALL_DIR"
mkdir -p "$LIB_INSTALL_DIR"

# Download the main script
echo "📥 Downloading $BINARY_NAME..."
if ! curl -fsSL "$REPO_URL/continuous_claude.sh" -o "$INSTALL_DIR/$BINARY_NAME"; then
    echo -e "${RED}❌ Failed to download $BINARY_NAME${NC}" >&2
    exit 1
fi

# Make it executable
chmod +x "$INSTALL_DIR/$BINARY_NAME"
echo -e "${GREEN}✅ Main script installed${NC}"

# Download lib modules for Multi-Agent System v2.0
echo ""
echo "📥 Downloading Multi-Agent System modules..."

LIB_FILES=(
    "messaging.sh"
    "personas.sh"
    "worktrees.sh"
    "orchestrator.sh"
    "conflicts.sh"
    "coordination.sh"
    "learning.sh"
    "review.sh"
    "dashboard.sh"
)

mkdir -p "$LIB_INSTALL_DIR/lib"

for lib_file in "${LIB_FILES[@]}"; do
    echo "   Downloading lib/$lib_file..."
    if ! curl -fsSL "$REPO_URL/lib/$lib_file" -o "$LIB_INSTALL_DIR/lib/$lib_file" 2>/dev/null; then
        echo -e "${YELLOW}   ⚠️  Could not download lib/$lib_file (may not exist yet)${NC}"
    else
        chmod +x "$LIB_INSTALL_DIR/lib/$lib_file"
    fi
done

echo -e "${GREEN}✅ Library modules installed to $LIB_INSTALL_DIR/lib/${NC}"

# Download personas
echo ""
echo "📥 Downloading persona definitions..."

PERSONA_FILES=(
    "developer.yaml"
    "tester.yaml"
    "reviewer.yaml"
    "documenter.yaml"
    "security.yaml"
)

mkdir -p "$LIB_INSTALL_DIR/personas"

for persona_file in "${PERSONA_FILES[@]}"; do
    echo "   Downloading personas/$persona_file..."
    if ! curl -fsSL "$REPO_URL/personas/$persona_file" -o "$LIB_INSTALL_DIR/personas/$persona_file" 2>/dev/null; then
        echo -e "${YELLOW}   ⚠️  Could not download personas/$persona_file${NC}"
    fi
done

echo -e "${GREEN}✅ Personas installed to $LIB_INSTALL_DIR/personas/${NC}"

# Update the script to point to the correct lib directory
# Create a wrapper that sets LIB_DIR
WRAPPER_CONTENT="#!/bin/bash
# Continuous Claude wrapper - sets library path
export CONTINUOUS_CLAUDE_LIB_DIR=\"$LIB_INSTALL_DIR/lib\"
export CONTINUOUS_CLAUDE_PERSONAS_DIR=\"$LIB_INSTALL_DIR/personas\"
exec \"$INSTALL_DIR/.continuous-claude-core\" \"\$@\"
"

# Move the core script
mv "$INSTALL_DIR/$BINARY_NAME" "$INSTALL_DIR/.continuous-claude-core"

# Create the wrapper
echo "$WRAPPER_CONTENT" > "$INSTALL_DIR/$BINARY_NAME"
chmod +x "$INSTALL_DIR/$BINARY_NAME"

echo ""
echo -e "${GREEN}✅ $BINARY_NAME installed to $INSTALL_DIR/$BINARY_NAME${NC}"

# Check if install directory is in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo -e "${YELLOW}⚠️  Warning: $INSTALL_DIR is not in your PATH${NC}"
    echo ""
    echo "To add it to your PATH, add this line to your shell profile:"
    echo ""

    # Detect shell
    if [[ "$SHELL" == *"zsh"* ]]; then
        echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
        echo "  source ~/.zshrc"
    elif [[ "$SHELL" == *"bash"* ]]; then
        echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
        echo "  source ~/.bashrc"
    else
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
    echo ""
fi

# Check for dependencies
echo ""
echo "🔍 Checking dependencies..."

missing_deps=()
optional_deps=()

if ! command -v claude &> /dev/null; then
    missing_deps+=("Claude Code CLI")
fi

if ! command -v gh &> /dev/null; then
    missing_deps+=("GitHub CLI")
fi

if ! command -v jq &> /dev/null; then
    missing_deps+=("jq")
fi

if ! command -v python3 &> /dev/null; then
    optional_deps+=("Python 3.11+ (for dashboard)")
fi

if [ ${#missing_deps[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ All required dependencies installed${NC}"
else
    echo -e "${YELLOW}⚠️  Missing required dependencies:${NC}"
    for dep in "${missing_deps[@]}"; do
        echo "   - $dep"
    done
    echo ""
    echo "Install them with:"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "  brew install gh jq"
        echo "  # Claude Code: https://code.claude.com"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "  # GitHub CLI: https://github.com/cli/cli#installation"
        echo "  sudo apt-get install jq  # or equivalent for your distro"
        echo "  # Claude Code: https://code.claude.com"
    fi
fi

if [ ${#optional_deps[@]} -gt 0 ]; then
    echo ""
    echo -e "${BLUE}ℹ️  Optional dependencies (for Multi-Agent features):${NC}"
    for dep in "${optional_deps[@]}"; do
        echo "   - $dep"
    done
fi

echo ""
echo -e "${GREEN}🎉 Installation complete!${NC}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Get started:"
echo ""
echo "  # Single-agent continuous loop"
echo "  $BINARY_NAME -p \"your task\" -m 5"
echo ""
echo "  # Multi-agent swarm (v2.0)"
echo "  $BINARY_NAME swarm -p \"build feature\" -m pipeline"
echo ""
echo "  # Start dashboard"
echo "  $BINARY_NAME dashboard start"
echo ""
echo "  # Show all commands"
echo "  $BINARY_NAME --help"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Documentation: ${GITHUB_URL}"
echo ""
