# Terraform Plan Reader

A bash script that makes Terraform plan output more human-readable by organizing resources by action type, providing color-coded output, and offering multiple viewing modes.

## Features

- 📊 **Summary Statistics**: Quick overview of resources to be added, changed, replaced, destroyed, and moved
- 🎨 **Color-Coded Output**: Visual distinction between different action types
  - 🟢 Green: Resources to be created
  - 🟡 Yellow: Resources to be modified/changed
  - 💗 Pink: Resources to be replaced
  - 🔴 Red: Resources to be destroyed
  - 🔵 Blue: Resources to be moved
- 📋 **Multiple View Modes**:
  - Resources grouped by action type (created, modified, replaced, destroyed, moved)
  - Alphabetically sorted list with color coding
  - Module-based grouping with action summaries
  - Group modules with identical changes together
- ⚙️ **Flexible Options**: Limit output, group by module, show detailed changes, and more
- ✅ **CI/CD Ready**: GitHub Actions workflow for validation and automated releases

## Requirements

- Bash (tested on macOS and Linux)
- Standard Unix utilities (grep, sed, sort, etc.)

## Installation

1. Clone or download this repository
2. Make the script executable:
   ```bash
   chmod +x terraform-plan-reader.sh
   ```

## Usage

### Basic Usage

```bash
./terraform-plan-reader.sh terraform_plan.txt
```

If no file is specified, it defaults to `terraform_plan.txt`:

```bash
./terraform-plan-reader.sh
```

### Options

- `-l, --limit N`: Show categorized lists with N items per section (0 or omit N = show all). Without this flag, only the summary is shown.
- `-g, --group-by-module`: Group modules with identical action patterns together and show detailed changes
- `-d, --detail`: Show detailed parameter changes for resources
- `-a, --alphabetical`: Show alphabetically sorted list of all resources
- `-h, --help`: Display help message

### Examples

```bash
# Show all resources
./terraform-plan-reader.sh terraform_plan.txt

# Limit output to 20 items per section
./terraform-plan-reader.sh --limit 20 terraform_plan.txt

# Group resources by module (modules with identical changes are grouped together)
./terraform-plan-reader.sh --group-by-module terraform_plan.txt

# Group modules and show detailed changes
./terraform-plan-reader.sh -g -d terraform_plan.txt

# Show alphabetically sorted list
./terraform-plan-reader.sh -a terraform_plan.txt

# Combine options
./terraform-plan-reader.sh -l 50 -g terraform_plan.txt
```

## Output Sections

The script provides several organized views of your Terraform plan:

### 1. Summary
High-level statistics showing:
- Total resources to add
- Total resources to change
- Total resources to replace
- Total resources to destroy
- Total resources to move

### 2. Resources by Action Type
Five separate lists showing:
- **RESOURCES TO BE CREATED**: All resources that will be created
- **RESOURCES TO BE MODIFIED/CHANGED**: All resources that will be updated
- **RESOURCES TO BE REPLACED**: All resources that must be replaced (destroyed and recreated)
- **RESOURCES TO BE DESTROYED**: All resources that will be destroyed
- **RESOURCES TO BE MOVED**: All resources that will be moved

### 3. Alphabetically Sorted List
A combined list of all resources sorted alphabetically, with color coding indicating the action type for each resource.

### 4. Module Grouping (with `-g` flag)
When using the `--group-by-module` option:
- Shows total number of modules touched
- Groups modules with identical action patterns together
- Lists each module or group with a summary of actions:
  - Number of resources added (green)
  - Number of resources changed (yellow)
  - Number of resources replaced (pink)
  - Number of resources destroyed (red)
  - Number of resources moved (blue)

### 5. Detailed Module Changes (with `-g -d` flags)
When using both `--group-by-module` and `--detail` options:
- For grouped modules: Shows resource structure once with `{module}` placeholder
- For individual modules: Shows all detailed changes
- Makes it easy to see what changes apply to which modules

## Example Output

```
═══════════════════════════════════════════════════════════════
  TERRAFORM PLAN SUMMARY
═══════════════════════════════════════════════════════════════

Plan: 100 to add, 3 to change, 40 to destroy.

Resources to add:    100
Resources to change:  3
Resources to replace: 5
Resources to destroy: 40
Resources to move:    120

═══════════════════════════════════════════════════════════════

RESOURCES TO BE CREATED:
  module.example[0].azurerm_resource_group.example
  ...

RESOURCES TO BE MODIFIED/CHANGED:
  ...

RESOURCES TO BE DESTROYED:
  ...

ALL RESOURCES (ALPHABETICALLY SORTED):
  [color-coded list of all resources]

RESOURCES GROUPED BY MODULE:
Total modules touched: 21

  Group 1 (3 modules): 10 added, 5 replaced, 2 destroyed
    - module.example[0]
    - module.example[1]
    - module.example[2]
      {module}.resource.name (applies to all 3 modules)
  
  module.other[0]: 5 added, 2 destroyed, 6 moved
  ...
```

## Input Format

The script expects Terraform plan output in text format, typically from:
- `terraform plan > terraform_plan.txt`
- Azure DevOps pipeline logs
- Any Terraform plan output saved to a text file

The script automatically:
- Removes timestamps (ISO format)
- Strips ANSI color codes from the input
- Parses resource names and actions

## CI/CD

This repository includes GitHub Actions workflows for automated validation and releases:

### Continuous Integration
- **Syntax Check**: Validates bash syntax on every push/PR
- **ShellCheck**: Runs static analysis to catch potential bugs and style issues
- Runs automatically on pushes to `main`/`master` and pull requests

### Automated Releases
- **Release Workflow**: Automatically creates GitHub releases when tags are pushed
- **Tag Format**: Use semantic versioning (e.g., `v1.0.0`)
- **Release Assets**: Includes the validated script as a downloadable asset

To create a release:
```bash
git tag v1.0.0
git push origin v1.0.0
```

## Notes

- The script handles large plan files efficiently
- Color output works best in terminals that support ANSI colors
- The `--limit` option is useful for quick overviews of large plans
- Module grouping is particularly helpful for understanding impact across different modules
- The `-g -d` combination is powerful for reviewing changes across many similar modules

## License

This project is open source and available for use.

## Contributing

Contributions, issues, and feature requests are welcome!

