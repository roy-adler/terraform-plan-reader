#!/bin/bash

# Terraform Plan Reader
# Makes terraform plan output more human-readable

# Default values
INPUT_FILE="terraform_plan.txt"
LIMIT=0  # 0 means no limit (show all)

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--limit)
            LIMIT="$2"
            if ! [[ "$LIMIT" =~ ^[0-9]+$ ]]; then
                echo "Error: Limit must be a positive number" >&2
                exit 1
            fi
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS] [FILE]"
            echo ""
            echo "Options:"
            echo "  -l, --limit N    Limit output to N items per section (default: show all)"
            echo "  -h, --help       Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 terraform_plan.txt"
            echo "  $0 --limit 20 terraform_plan.txt"
            echo "  $0 -l 50"
            exit 0
            ;;
        -*)
            echo "Error: Unknown option $1" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
        *)
            INPUT_FILE="$1"
            shift
            ;;
    esac
done

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

# Count moves and extract moved resources
MOVED_RESOURCES=""
MOVE_COUNT=$(grep -c "has moved to" "$INPUT_FILE" 2>/dev/null || echo "0")
if [ "$MOVE_COUNT" -gt 0 ]; then
    MOVED_RESOURCES=$(grep "has moved to" "$INPUT_FILE" | \
        clean_line | \
        sed -E 's/^[[:space:]]*#[[:space:]]*//' | \
        sed -E 's/[[:space:]]*has moved to.*$//' | \
        sort -u)
fi

echo -e "${GREEN}Resources to add:${NC}    $ADD_COUNT"
echo -e "${YELLOW}Resources to change:${NC}  $CHANGE_COUNT"
echo -e "${RED}Resources to destroy:${NC} $DESTROY_COUNT"
if [ "$MOVE_COUNT" -gt 0 ]; then
    echo -e "${BLUE}Resources to move:${NC}    $MOVE_COUNT"
fi
echo ""
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Helper function to apply limit if set
apply_limit() {
    if [ "$LIMIT" -gt 0 ]; then
        head -n "$LIMIT"
    else
        cat
    fi
}

# Extract resource names - look for lines with "# resource_name" will be created/destroyed/modified
echo -e "${BOLD}${GREEN}RESOURCES TO BE CREATED:${NC}"
echo ""
CREATED_RESOURCES=$(grep "will be created" "$INPUT_FILE" | \
    clean_line | \
    sed -E 's/^[[:space:]]*#[[:space:]]*//' | \
    sed -E 's/[[:space:]]*will be created.*$//' | \
    sort -u)
if [ -n "$CREATED_RESOURCES" ]; then
    CREATED_COUNT=$(echo "$CREATED_RESOURCES" | grep -v '^$' | wc -l | tr -d ' ')
    DISPLAYED=$(echo "$CREATED_RESOURCES" | apply_limit | sed 's/^/  /')
    echo "$DISPLAYED"
    if [ "$LIMIT" -gt 0 ] && [ "$CREATED_COUNT" -gt "$LIMIT" ]; then
        REMAINING=$((CREATED_COUNT - LIMIT))
        echo -e "${CYAN}  ... and $REMAINING more${NC}"
    fi
else
    echo "  (none)"
fi

echo ""
echo -e "${BOLD}${YELLOW}RESOURCES TO BE MODIFIED/CHANGED:${NC}"
echo ""
CHANGED_RESOURCES=$(grep -E "will be updated|must be replaced|will be replaced" "$INPUT_FILE" | \
    clean_line | \
    sed -E 's/^[[:space:]]*#[[:space:]]*//' | \
    sed -E 's/[[:space:]]*(will be|must be).*$//' | \
    sort -u)
if [ -n "$CHANGED_RESOURCES" ]; then
    CHANGED_COUNT=$(echo "$CHANGED_RESOURCES" | grep -v '^$' | wc -l | tr -d ' ')
    DISPLAYED=$(echo "$CHANGED_RESOURCES" | apply_limit | sed 's/^/  /')
    echo "$DISPLAYED"
    if [ "$LIMIT" -gt 0 ] && [ "$CHANGED_COUNT" -gt "$LIMIT" ]; then
        REMAINING=$((CHANGED_COUNT - LIMIT))
        echo -e "${CYAN}  ... and $REMAINING more${NC}"
    fi
else
    echo "  (none)"
fi

echo ""
echo -e "${BOLD}${RED}RESOURCES TO BE DESTROYED:${NC}"
echo ""
DESTROYED_RESOURCES=$(grep -E "will be.*destroyed|\[31mdestroyed" "$INPUT_FILE" | \
    clean_line | \
    sed -E 's/^[[:space:]]*#[[:space:]]*//' | \
    sed -E 's/[[:space:]]*will be.*destroyed.*$//' | \
    sed -E 's/[[:space:]]*\(because.*$//' | \
    sort -u)
if [ -n "$DESTROYED_RESOURCES" ]; then
    DESTROYED_COUNT=$(echo "$DESTROYED_RESOURCES" | grep -v '^$' | wc -l | tr -d ' ')
    DISPLAYED=$(echo "$DESTROYED_RESOURCES" | apply_limit | sed 's/^/  /')
    echo "$DISPLAYED"
    if [ "$LIMIT" -gt 0 ] && [ "$DESTROYED_COUNT" -gt "$LIMIT" ]; then
        REMAINING=$((DESTROYED_COUNT - LIMIT))
        echo -e "${CYAN}  ... and $REMAINING more${NC}"
    fi
else
    echo "  (none)"
fi

if [ "$MOVE_COUNT" -gt 0 ]; then
    echo ""
    echo -e "${BOLD}${BLUE}RESOURCES TO BE MOVED:${NC}"
    echo ""
    if [ -n "$MOVED_RESOURCES" ]; then
        MOVED_DISPLAY_COUNT=$(echo "$MOVED_RESOURCES" | grep -v '^$' | wc -l | tr -d ' ')
        DISPLAYED=$(echo "$MOVED_RESOURCES" | apply_limit | sed 's/^/  /')
        echo "$DISPLAYED"
        if [ "$LIMIT" -gt 0 ] && [ "$MOVED_DISPLAY_COUNT" -gt "$LIMIT" ]; then
            REMAINING=$((MOVED_DISPLAY_COUNT - LIMIT))
            echo -e "${CYAN}  ... and $REMAINING more${NC}"
        fi
    else
        echo "  (none)"
    fi
fi

# Combine all resources and sort alphabetically
echo ""
echo -e "${BOLD}${CYAN}ALL RESOURCES (ALPHABETICALLY SORTED):${NC}"
echo ""
ALL_RESOURCES=$(printf "%s\n%s\n%s\n%s\n" \
    "$CREATED_RESOURCES" \
    "$CHANGED_RESOURCES" \
    "$DESTROYED_RESOURCES" \
    "$MOVED_RESOURCES" | \
    grep -v '^$' | \
    sort -u)
if [ -n "$ALL_RESOURCES" ]; then
    ALL_COUNT=$(echo "$ALL_RESOURCES" | grep -v '^$' | wc -l | tr -d ' ')
    DISPLAYED=$(echo "$ALL_RESOURCES" | apply_limit | sed 's/^/  /')
    echo "$DISPLAYED"
    if [ "$LIMIT" -gt 0 ] && [ "$ALL_COUNT" -gt "$LIMIT" ]; then
        REMAINING=$((ALL_COUNT - LIMIT))
        echo -e "${CYAN}  ... and $REMAINING more${NC}"
    fi
else
    echo "  (none)"
fi

echo ""
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

