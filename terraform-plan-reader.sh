#!/bin/bash

# Terraform Plan Reader
# Makes terraform plan output more human-readable

# Default values
INPUT_FILE="terraform_plan.txt"
LIMIT=0  # 0 means no limit (show all)
GROUP_BY_MODULE=false
GROUP_BY_ACTION_PATTERN=false

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
        -g|--group-by-module)
            GROUP_BY_MODULE=true
            shift
            ;;
        -d|--detail)
            GROUP_BY_ACTION_PATTERN=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS] [FILE]"
            echo ""
            echo "Options:"
            echo "  -l, --limit N         Limit output to N items per section (default: show all)"
            echo "  -g, --group-by-module Group modules with identical action patterns"
            echo "  -d, --detail          Show detailed changes for each module (use with -g)"
            echo "  -h, --help            Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 terraform_plan.txt"
            echo "  $0 --limit 20 terraform_plan.txt"
            echo "  $0 --group-by-module terraform_plan.txt  # Group modules with same actions"
            echo "  $0 -g -d terraform_plan.txt  # Group and show detailed changes"
            echo "  $0 -l 50 -g"
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
PINK='\033[1;35m'  # Bright magenta/pink for replaced resources
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
# Count replaced resources for summary
REPLACED_COUNT_SUMMARY=$(grep -cE "must be.*replaced|will be.*replaced" "$INPUT_FILE" 2>/dev/null || echo "0")
if [ "$REPLACED_COUNT_SUMMARY" -gt 0 ]; then
    echo -e "${PINK}Resources to replace:${NC} $REPLACED_COUNT_SUMMARY"
fi
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
CHANGED_RESOURCES=$(grep -E "will be updated" "$INPUT_FILE" | \
    clean_line | \
    sed -E 's/^[[:space:]]*#[[:space:]]*//' | \
    sed -E 's/[[:space:]]*will be updated.*$//' | \
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
echo -e "${BOLD}${PINK}RESOURCES TO BE REPLACED:${NC}"
echo ""
REPLACED_RESOURCES=$(grep -E "must be.*replaced|will be.*replaced" "$INPUT_FILE" | \
    clean_line | \
    sed -E 's/^[[:space:]]*#[[:space:]]*//' | \
    sed -E 's/[[:space:]]*must be.*replaced.*$//' | \
    sed -E 's/[[:space:]]*will be.*replaced.*$//' | \
    sort -u)
if [ -n "$REPLACED_RESOURCES" ]; then
    REPLACED_COUNT=$(echo "$REPLACED_RESOURCES" | grep -v '^$' | wc -l | tr -d ' ')
    DISPLAYED=$(echo "$REPLACED_RESOURCES" | apply_limit | sed 's/^/  /')
    echo "$DISPLAYED"
    if [ "$LIMIT" -gt 0 ] && [ "$REPLACED_COUNT" -gt "$LIMIT" ]; then
        REMAINING=$((REPLACED_COUNT - LIMIT))
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

# Combine all resources and sort alphabetically with color coding
echo ""
echo -e "${BOLD}${CYAN}ALL RESOURCES (ALPHABETICALLY SORTED):${NC}"
echo ""
ALL_RESOURCES=$(printf "%s\n%s\n%s\n%s\n%s\n" \
    "$CREATED_RESOURCES" \
    "$CHANGED_RESOURCES" \
    "$REPLACED_RESOURCES" \
    "$DESTROYED_RESOURCES" \
    "$MOVED_RESOURCES" | \
    grep -v '^$' | \
    sort -u)
if [ -n "$ALL_RESOURCES" ]; then
    ALL_COUNT=$(echo "$ALL_RESOURCES" | grep -v '^$' | wc -l | tr -d ' ')
    
    # Color-code each resource based on its category
    echo "$ALL_RESOURCES" | apply_limit | while IFS= read -r resource; do
        if [ -z "$resource" ]; then
            continue
        fi
        
        # Determine color based on which list the resource belongs to
        COLOR="${NC}"  # Default: no color
        if echo "$CREATED_RESOURCES" | grep -Fxq "$resource"; then
            COLOR="${GREEN}"
        elif echo "$REPLACED_RESOURCES" | grep -Fxq "$resource"; then
            COLOR="${PINK}"
        elif echo "$CHANGED_RESOURCES" | grep -Fxq "$resource"; then
            COLOR="${YELLOW}"
        elif echo "$DESTROYED_RESOURCES" | grep -Fxq "$resource"; then
            COLOR="${RED}"
        elif [ -n "$MOVED_RESOURCES" ] && echo "$MOVED_RESOURCES" | grep -Fxq "$resource"; then
            COLOR="${BLUE}"
        fi
        
        echo -e "${COLOR}  ${resource}${NC}"
    done
    if [ "$LIMIT" -gt 0 ] && [ "$ALL_COUNT" -gt "$LIMIT" ]; then
        REMAINING=$((ALL_COUNT - LIMIT))
        echo -e "${CYAN}  ... and $REMAINING more${NC}"
    fi
else
    echo "  (none)"
fi

# Group by module if requested
if [ "$GROUP_BY_MODULE" = true ]; then
    echo ""
    echo -e "${BOLD}${CYAN}RESOURCES GROUPED BY MODULE:${NC}"
    echo ""
    
    # Collect all unique top-level modules only
    # Pattern: module.MODULENAME[0] or module.MODULENAME
    # Extract only the first module in the path (top-level), ignore nested modules
    ALL_MODULES=$(printf "%s\n%s\n%s\n%s\n%s\n" \
        "$CREATED_RESOURCES" \
        "$CHANGED_RESOURCES" \
        "$REPLACED_RESOURCES" \
        "$DESTROYED_RESOURCES" \
        "$MOVED_RESOURCES" | \
        grep -v '^$' | \
        sed -E 's/^(module\.[a-zA-Z0-9_]+)(\[[0-9]+\])?(\..*)?$/\1\2/' | \
        grep -E '^module\.[a-zA-Z0-9_]+(\[[0-9]+\])?$' | \
        sort -u)
    
    MODULE_COUNT=$(echo "$ALL_MODULES" | grep -v '^$' | wc -l | tr -d ' ')
    
    echo -e "${BOLD}Total modules touched:${NC} $MODULE_COUNT"
    echo ""
    
    # Collect module actions first
    # Use temporary file to avoid subshell issues with associative arrays
    TEMP_FILE=$(mktemp)
    trap "rm -f $TEMP_FILE" EXIT
    
    while IFS= read -r module || [ -n "$module" ]; do
        if [ -z "$module" ]; then
            continue
        fi
        
        # Count actions for this module using grep
        # Escape brackets in module name for grep
        module_escaped=$(echo "$module" | sed 's/\[/\\[/g; s/\]/\\]/g')
        created_count=$(echo "$CREATED_RESOURCES" | grep "^${module_escaped}\." 2>/dev/null | wc -l | tr -d ' ')
        changed_count=$(echo "$CHANGED_RESOURCES" | grep "^${module_escaped}\." 2>/dev/null | wc -l | tr -d ' ')
        replaced_count=$(echo "$REPLACED_RESOURCES" | grep "^${module_escaped}\." 2>/dev/null | wc -l | tr -d ' ')
        destroyed_count=$(echo "$DESTROYED_RESOURCES" | grep "^${module_escaped}\." 2>/dev/null | wc -l | tr -d ' ')
        moved_count=0
        if [ -n "$MOVED_RESOURCES" ]; then
            moved_count=$(echo "$MOVED_RESOURCES" | grep "^${module_escaped}\." 2>/dev/null | wc -l | tr -d ' ')
        fi
        
        # Create action pattern key (without colors, for grouping)
        action_pattern="${created_count}:${changed_count}:${replaced_count}:${destroyed_count}:${moved_count}"
        
        # Build action summary string for display
        action_summary=""
        if [ "$created_count" -gt 0 ]; then
            action_summary="${GREEN}${created_count} added${NC}"
        fi
        if [ "$changed_count" -gt 0 ]; then
            if [ -n "$action_summary" ]; then
                action_summary="${action_summary}, ${YELLOW}${changed_count} changed${NC}"
            else
                action_summary="${YELLOW}${changed_count} changed${NC}"
            fi
        fi
        if [ "$replaced_count" -gt 0 ]; then
            if [ -n "$action_summary" ]; then
                action_summary="${action_summary}, ${PINK}${replaced_count} replaced${NC}"
            else
                action_summary="${PINK}${replaced_count} replaced${NC}"
            fi
        fi
        if [ "$destroyed_count" -gt 0 ]; then
            if [ -n "$action_summary" ]; then
                action_summary="${action_summary}, ${RED}${destroyed_count} destroyed${NC}"
            else
                action_summary="${RED}${destroyed_count} destroyed${NC}"
            fi
        fi
        if [ "$moved_count" -gt 0 ]; then
            if [ -n "$action_summary" ]; then
                action_summary="${action_summary}, ${BLUE}${moved_count} moved${NC}"
            else
                action_summary="${BLUE}${moved_count} moved${NC}"
            fi
        fi
        
        # Get actual resources for this module
        module_created_resources=$(echo "$CREATED_RESOURCES" | grep "^${module_escaped}\." 2>/dev/null | tr '\n' ';')
        module_changed_resources=$(echo "$CHANGED_RESOURCES" | grep "^${module_escaped}\." 2>/dev/null | tr '\n' ';')
        module_replaced_resources=$(echo "$REPLACED_RESOURCES" | grep "^${module_escaped}\." 2>/dev/null | tr '\n' ';')
        module_destroyed_resources=$(echo "$DESTROYED_RESOURCES" | grep "^${module_escaped}\." 2>/dev/null | tr '\n' ';')
        module_moved_resources=""
        if [ -n "$MOVED_RESOURCES" ]; then
            module_moved_resources=$(echo "$MOVED_RESOURCES" | grep "^${module_escaped}\." 2>/dev/null | tr '\n' ';')
        fi
        
        # Store in temp file: pattern|module|action_summary|created|changed|replaced|destroyed|moved
        echo "${action_pattern}|${module}|${action_summary}|${module_created_resources}|${module_changed_resources}|${module_replaced_resources}|${module_destroyed_resources}|${module_moved_resources}" >> "$TEMP_FILE"
    done <<< "$ALL_MODULES"
    
    # Always group by action pattern when -g is used
    if [ "$GROUP_BY_MODULE" = true ]; then
        # Group modules by identical action patterns
        # First, create a grouped file
        GROUPED_FILE=$(mktemp)
        trap "rm -f $TEMP_FILE $GROUPED_FILE" EXIT
        
        # Group by pattern using sort
        sort -t'|' -k1,1 "$TEMP_FILE" > "$GROUPED_FILE"
        
        # Process groups in bash
        current_pattern=""
        group_num=1
        declare -a current_modules=()
        declare -a current_created=()
        declare -a current_changed=()
        declare -a current_replaced=()
        declare -a current_destroyed=()
        declare -a current_moved=()
        current_summary=""
        
        while IFS='|' read -r pattern module summary created changed replaced destroyed moved; do
            if [ "$pattern" != "$current_pattern" ]; then
                # Process previous group
                if [ -n "$current_pattern" ]; then
                    module_count=${#current_modules[@]}
                    if [ "$module_count" -gt 1 ]; then
                        echo -e "  ${BOLD}Group ${group_num} (${module_count} modules)${NC}: $current_summary"
                        for mod in "${current_modules[@]}"; do
                            echo -e "    - ${mod}"
                        done
                        # Show details if -d flag is set
                        if [ "$GROUP_BY_ACTION_PATTERN" = true ]; then
                            # Use resources from first module as template, show once with placeholder notation
                            first_created="${current_created[0]}"
                            first_changed="${current_changed[0]}"
                            first_replaced="${current_replaced[0]}"
                            first_destroyed="${current_destroyed[0]}"
                            first_moved="${current_moved[0]}"
                            
                            # Created resources - show once with {module} placeholder
                            if [ -n "$first_created" ]; then
                                echo "$first_created" | tr ';' '\n' | grep -v '^$' | while IFS= read -r resource_template; do
                                    # Extract resource path after module name
                                    resource_suffix=$(echo "$resource_template" | sed "s|^module\.[^.]*\.||")
                                    # Show once with placeholder notation
                                    echo -e "      ${GREEN}{module}.${resource_suffix}${NC}"
                                done
                            fi
                            # Changed resources
                            if [ -n "$first_changed" ]; then
                                echo "$first_changed" | tr ';' '\n' | grep -v '^$' | while IFS= read -r resource_template; do
                                    resource_suffix=$(echo "$resource_template" | sed "s|^module\.[^.]*\.||")
                                    echo -e "      ${YELLOW}{module}.${resource_suffix}${NC}"
                                done
                            fi
                            # Replaced resources
                            if [ -n "$first_replaced" ]; then
                                echo "$first_replaced" | tr ';' '\n' | grep -v '^$' | while IFS= read -r resource_template; do
                                    resource_suffix=$(echo "$resource_template" | sed "s|^module\.[^.]*\.||")
                                    echo -e "      ${PINK}{module}.${resource_suffix}${NC}"
                                done
                            fi
                            # Destroyed resources
                            if [ -n "$first_destroyed" ]; then
                                echo "$first_destroyed" | tr ';' '\n' | grep -v '^$' | while IFS= read -r resource_template; do
                                    resource_suffix=$(echo "$resource_template" | sed "s|^module\.[^.]*\.||")
                                    echo -e "      ${RED}{module}.${resource_suffix}${NC}"
                                done
                            fi
                            # Moved resources
                            if [ -n "$first_moved" ]; then
                                echo "$first_moved" | tr ';' '\n' | grep -v '^$' | while IFS= read -r resource_template; do
                                    resource_suffix=$(echo "$resource_template" | sed "s|^module\.[^.]*\.||")
                                    echo -e "      ${BLUE}{module}.${resource_suffix}${NC}"
                                done
                            fi
                        fi
                    else
                        echo -e "  ${BOLD}${current_modules[0]}${NC}: $current_summary"
                        # Show details for single module if -d flag is set
                        if [ "$GROUP_BY_ACTION_PATTERN" = true ]; then
                            if [ -n "${current_created[0]}" ]; then
                                echo "${current_created[0]}" | tr ';' '\n' | grep -v '^$' | while IFS= read -r resource; do
                                    echo -e "      ${GREEN}${resource}${NC}"
                                done
                            fi
                            if [ -n "${current_changed[0]}" ]; then
                                echo "${current_changed[0]}" | tr ';' '\n' | grep -v '^$' | while IFS= read -r resource; do
                                    echo -e "      ${YELLOW}${resource}${NC}"
                                done
                            fi
                            if [ -n "${current_replaced[0]}" ]; then
                                echo "${current_replaced[0]}" | tr ';' '\n' | grep -v '^$' | while IFS= read -r resource; do
                                    echo -e "      ${PINK}${resource}${NC}"
                                done
                            fi
                            if [ -n "${current_destroyed[0]}" ]; then
                                echo "${current_destroyed[0]}" | tr ';' '\n' | grep -v '^$' | while IFS= read -r resource; do
                                    echo -e "      ${RED}${resource}${NC}"
                                done
                            fi
                            if [ -n "${current_moved[0]}" ]; then
                                echo "${current_moved[0]}" | tr ';' '\n' | grep -v '^$' | while IFS= read -r resource; do
                                    echo -e "      ${BLUE}${resource}${NC}"
                                done
                            fi
                        fi
                    fi
                    group_num=$((group_num + 1))
                fi
                # Start new group
                current_pattern="$pattern"
                current_modules=("$module")
                current_created=("$created")
                current_changed=("$changed")
                current_replaced=("$replaced")
                current_destroyed=("$destroyed")
                current_moved=("$moved")
                current_summary="$summary"
            else
                # Add to current group
                current_modules+=("$module")
                current_created+=("$created")
                current_changed+=("$changed")
                current_replaced+=("$replaced")
                current_destroyed+=("$destroyed")
                current_moved+=("$moved")
            fi
        done < "$GROUPED_FILE"
        
        # Process last group
        if [ -n "$current_pattern" ]; then
            module_count=${#current_modules[@]}
            if [ "$module_count" -gt 1 ]; then
                echo -e "  ${BOLD}Group ${group_num} (${module_count} modules)${NC}: $current_summary"
                for mod in "${current_modules[@]}"; do
                    echo -e "    - ${mod}"
                done
                # Show details if -d flag is set
                if [ "$GROUP_BY_ACTION_PATTERN" = true ]; then
                    first_created="${current_created[0]}"
                    first_changed="${current_changed[0]}"
                    first_replaced="${current_replaced[0]}"
                    first_destroyed="${current_destroyed[0]}"
                    first_moved="${current_moved[0]}"
                    
                    if [ -n "$first_created" ]; then
                        echo "$first_created" | tr ';' '\n' | grep -v '^$' | while IFS= read -r resource_template; do
                            resource_suffix=$(echo "$resource_template" | sed "s|^module\.[^.]*\.||")
                            echo -e "      ${GREEN}{module}.${resource_suffix}${NC}"
                        done
                    fi
                    if [ -n "$first_changed" ]; then
                        echo "$first_changed" | tr ';' '\n' | grep -v '^$' | while IFS= read -r resource_template; do
                            resource_suffix=$(echo "$resource_template" | sed "s|^module\.[^.]*\.||")
                            echo -e "      ${YELLOW}{module}.${resource_suffix}${NC}"
                        done
                    fi
                    if [ -n "$first_replaced" ]; then
                        echo "$first_replaced" | tr ';' '\n' | grep -v '^$' | while IFS= read -r resource_template; do
                            resource_suffix=$(echo "$resource_template" | sed "s|^module\.[^.]*\.||")
                            echo -e "      ${MAGENTA}{module}.${resource_suffix}${NC}"
                        done
                    fi
                    if [ -n "$first_destroyed" ]; then
                        echo "$first_destroyed" | tr ';' '\n' | grep -v '^$' | while IFS= read -r resource_template; do
                            resource_suffix=$(echo "$resource_template" | sed "s|^module\.[^.]*\.||")
                            echo -e "      ${RED}{module}.${resource_suffix}${NC}"
                        done
                    fi
                    if [ -n "$first_moved" ]; then
                        echo "$first_moved" | tr ';' '\n' | grep -v '^$' | while IFS= read -r resource_template; do
                            resource_suffix=$(echo "$resource_template" | sed "s|^module\.[^.]*\.||")
                            echo -e "      ${BLUE}{module}.${resource_suffix}${NC}"
                        done
                    fi
                fi
            else
                echo -e "  ${BOLD}${current_modules[0]}${NC}: $current_summary"
                if [ "$GROUP_BY_ACTION_PATTERN" = true ]; then
                    if [ -n "${current_created[0]}" ]; then
                        echo "${current_created[0]}" | tr ';' '\n' | grep -v '^$' | while IFS= read -r resource; do
                            echo -e "      ${GREEN}${resource}${NC}"
                        done
                    fi
                    if [ -n "${current_changed[0]}" ]; then
                        echo "${current_changed[0]}" | tr ';' '\n' | grep -v '^$' | while IFS= read -r resource; do
                            echo -e "      ${YELLOW}${resource}${NC}"
                        done
                    fi
                    if [ -n "${current_replaced[0]}" ]; then
                        echo "${current_replaced[0]}" | tr ';' '\n' | grep -v '^$' | while IFS= read -r resource; do
                            echo -e "      ${MAGENTA}${resource}${NC}"
                        done
                    fi
                    if [ -n "${current_destroyed[0]}" ]; then
                        echo "${current_destroyed[0]}" | tr ';' '\n' | grep -v '^$' | while IFS= read -r resource; do
                            echo -e "      ${RED}${resource}${NC}"
                        done
                    fi
                    if [ -n "${current_moved[0]}" ]; then
                        echo "${current_moved[0]}" | tr ';' '\n' | grep -v '^$' | while IFS= read -r resource; do
                            echo -e "      ${BLUE}${resource}${NC}"
                        done
                    fi
                fi
            fi
        fi
        
        rm -f "$GROUPED_FILE"
    fi
fi

echo ""
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

