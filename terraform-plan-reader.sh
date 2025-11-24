#!/bin/bash

# Terraform Plan Reader
# Makes terraform plan output more human-readable

INPUT_FILE="${1:-terraform_plan.txt}"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: File '$INPUT_FILE' not found" >&2
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function to strip ANSI codes and timestamps
clean_line() {
    sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+Z //' | \
    sed -E 's/\x1b\[[0-9;]*m//g'
}

# Extract and display summary
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}  TERRAFORM PLAN SUMMARY${NC}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Extract summary line and parse counts
SUMMARY=$(grep -i "Plan:" "$INPUT_FILE" | clean_line | head -1)
if [ -n "$SUMMARY" ]; then
    echo -e "${BOLD}$SUMMARY${NC}"
    echo ""
    
    # Extract counts from summary
    ADD_COUNT=$(echo "$SUMMARY" | grep -oE '[0-9]+ to add' | grep -oE '[0-9]+' || echo "0")
    CHANGE_COUNT=$(echo "$SUMMARY" | grep -oE '[0-9]+ to change' | grep -oE '[0-9]+' || echo "0")
    DESTROY_COUNT=$(echo "$SUMMARY" | grep -oE '[0-9]+ to destroy' | grep -oE '[0-9]+' || echo "0")
else
    ADD_COUNT=0
    CHANGE_COUNT=0
    DESTROY_COUNT=0
fi

# Count moves
MOVE_COUNT=$(grep -c "has moved to" "$INPUT_FILE" 2>/dev/null || echo "0")

echo -e "${GREEN}Resources to add:${NC}    $ADD_COUNT"
echo -e "${YELLOW}Resources to change:${NC}  $CHANGE_COUNT"
echo -e "${RED}Resources to destroy:${NC} $DESTROY_COUNT"
if [ "$MOVE_COUNT" -gt 0 ]; then
    echo -e "${BLUE}Resources to move:${NC}    $MOVE_COUNT"
fi
echo ""
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Extract resource names - look for lines with "# resource_name" will be created/destroyed/modified
echo -e "${BOLD}${GREEN}RESOURCES TO BE CREATED:${NC}"
echo ""
grep "will be created" "$INPUT_FILE" | \
    clean_line | \
    sed -E 's/^[[:space:]]*#[[:space:]]*//' | \
    sed -E 's/[[:space:]]*will be created.*$//' | \
    sort -u | \
    head -30 | \
    sed 's/^/  /'

if [ "$ADD_COUNT" -gt 30 ]; then
    echo -e "${CYAN}  ... and $((ADD_COUNT - 30)) more${NC}"
fi

echo ""
echo -e "${BOLD}${YELLOW}RESOURCES TO BE MODIFIED/CHANGED:${NC}"
echo ""
(grep -E "will be updated|must be replaced|will be replaced" "$INPUT_FILE" | \
    clean_line | \
    sed -E 's/^[[:space:]]*#[[:space:]]*//' | \
    sed -E 's/[[:space:]]*(will be|must be).*$//' | \
    sort -u | \
    head -30 | \
    sed 's/^/  /') || echo "  (none)"

if [ "$CHANGE_COUNT" -gt 30 ]; then
    echo -e "${CYAN}  ... and $((CHANGE_COUNT - 30)) more${NC}"
fi

echo ""
echo -e "${BOLD}${RED}RESOURCES TO BE DESTROYED:${NC}"
echo ""
grep -E "will be.*destroyed|\[31mdestroyed" "$INPUT_FILE" | \
    clean_line | \
    sed -E 's/^[[:space:]]*#[[:space:]]*//' | \
    sed -E 's/[[:space:]]*will be.*destroyed.*$//' | \
    sed -E 's/[[:space:]]*\(because.*$//' | \
    sort -u | \
    head -30 | \
    sed 's/^/  /'

if [ "$DESTROY_COUNT" -gt 30 ]; then
    echo -e "${CYAN}  ... and $((DESTROY_COUNT - 30)) more${NC}"
fi

if [ "$MOVE_COUNT" -gt 0 ]; then
    echo ""
    echo -e "${BOLD}${BLUE}RESOURCES TO BE MOVED:${NC}"
    echo ""
    grep "has moved to" "$INPUT_FILE" | \
        clean_line | \
        sed -E 's/^[[:space:]]*#[[:space:]]*//' | \
        sed -E 's/[[:space:]]*has moved to.*$//' | \
        sort -u | \
        head -20 | \
        sed 's/^/  /'
    
    if [ "$MOVE_COUNT" -gt 20 ]; then
        echo -e "${CYAN}  ... and $((MOVE_COUNT - 20)) more${NC}"
    fi
fi

echo ""
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BOLD}Note:${NC} This is a summary view. For full details, review the original plan file."
echo ""

