#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy Scaffolding Tool for provost-extract
##
## Auto-generates a strategy stub from a sample file, with proper headers
## and function stubs for strategy_detect() and strategy_extract().
##
## Usage: new_strategy.sh --name NAME --category CATEGORY --sample FILE
##        new_strategy.sh --help
##
## Part of provost. Copyright (C) 2026 Martin J. Gallagher. GPL-3.0-or-later.
################################################################################

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STRATEGIES_DIR="$EXTRACT_DIR/strategies"
SAMPLES_DIR="$EXTRACT_DIR/samples"

usage () {
    cat <<'EOF'
Strategy Scaffolding Tool (new_strategy.sh)

Usage: new_strategy.sh --name NAME --category CATEGORY --sample FILE [OPTIONS]

Generates a new provost-extract strategy file with proper headers and function
stubs, plus a corresponding sample directory.

Required:
  --name NAME           Strategy name (lowercase, hyphenated, e.g. "my-format")
  --category CATEGORY   Strategy category subdirectory (e.g. "benchmark", "config",
                        "structured", "delimited", "system", "network", "logging",
                        "container", "security", "build", "misc")
  --sample FILE         Path to a sample input file for this strategy

Options:
  --description TEXT    Short description of the strategy (default: auto-generated)
  --priority N          Priority value 1-99 (default: 50)
  --version VER         Initial version (default: 1.0)
  --force               Overwrite existing strategy file
  -h, --help            Show this help

Output:
  Creates:
    strategies/<category>/<name>.sh    Strategy file with detect/extract stubs
    samples/<name>/                    Sample directory
    samples/<name>/sample1.txt         Copy of the provided sample file

Examples:
  new_strategy.sh --name my-logs --category logging --sample /tmp/app.log
  new_strategy.sh --name custom-csv --category structured --sample data.csv --priority 20
EOF
}

# Defaults
opt_name=""
opt_category=""
opt_sample=""
opt_description=""
opt_priority=50
opt_version="1.0"
opt_force=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage; exit 0 ;;
        --name)
            [[ $# -lt 2 ]] && echo "error: --name requires an argument" >&2 && exit 1
            opt_name="$2"; shift 2 ;;
        --category)
            [[ $# -lt 2 ]] && echo "error: --category requires an argument" >&2 && exit 1
            opt_category="$2"; shift 2 ;;
        --sample)
            [[ $# -lt 2 ]] && echo "error: --sample requires an argument" >&2 && exit 1
            opt_sample="$2"; shift 2 ;;
        --description)
            [[ $# -lt 2 ]] && echo "error: --description requires an argument" >&2 && exit 1
            opt_description="$2"; shift 2 ;;
        --priority)
            [[ $# -lt 2 ]] && echo "error: --priority requires an argument" >&2 && exit 1
            opt_priority="$2"; shift 2 ;;
        --version)
            [[ $# -lt 2 ]] && echo "error: --version requires an argument" >&2 && exit 1
            opt_version="$2"; shift 2 ;;
        --force)
            opt_force=1; shift ;;
        *)
            echo "error: unknown option: $1" >&2; exit 1 ;;
    esac
done

# Validate required arguments
if [[ -z "$opt_name" ]]; then
    echo "error: --name is required" >&2
    echo "Run 'new_strategy.sh --help' for usage." >&2
    exit 1
fi
if [[ -z "$opt_category" ]]; then
    echo "error: --category is required" >&2
    echo "Run 'new_strategy.sh --help' for usage." >&2
    exit 1
fi
if [[ -z "$opt_sample" ]]; then
    echo "error: --sample is required" >&2
    echo "Run 'new_strategy.sh --help' for usage." >&2
    exit 1
fi

# Validate sample file exists
if [[ ! -f "$opt_sample" ]]; then
    echo "error: sample file not found: $opt_sample" >&2
    exit 1
fi

# Validate name format (lowercase, hyphenated, no spaces)
if [[ ! "$opt_name" =~ ^[a-z][a-z0-9-]*$ ]]; then
    echo "error: strategy name must be lowercase alphanumeric with hyphens (e.g. 'my-format')" >&2
    exit 1
fi

# Validate priority is a number 1-99
if [[ ! "$opt_priority" =~ ^[0-9]+$ ]] || [[ "$opt_priority" -lt 1 || "$opt_priority" -gt 99 ]]; then
    echo "error: priority must be a number between 1 and 99" >&2
    exit 1
fi

# Validate category directory exists (or create it)
category_dir="$STRATEGIES_DIR/$opt_category"
if [[ ! -d "$category_dir" ]]; then
    echo "info: creating category directory: $category_dir"
    mkdir -p "$category_dir"
fi

# Check if strategy already exists
strategy_file="$category_dir/${opt_name}.sh"
if [[ -f "$strategy_file" && $opt_force -eq 0 ]]; then
    echo "error: strategy file already exists: $strategy_file" >&2
    echo "Use --force to overwrite." >&2
    exit 1
fi

# Auto-generate description if not provided
if [[ -z "$opt_description" ]]; then
    opt_description="Extract key/value pairs from ${opt_name} format output"
fi

# Create sample directory and copy sample file
sample_dir="$SAMPLES_DIR/$opt_name"
mkdir -p "$sample_dir"
cp "$opt_sample" "$sample_dir/sample1.txt"
echo "Created sample directory: $sample_dir"
echo "Copied sample file: $sample_dir/sample1.txt"

# Analyze sample file to generate detect hints
sample_head=""
sample_head=$(head -5 "$opt_sample" 2>/dev/null || true)

# Build detect hint comment based on sample content
detect_hints="    # TODO: Implement detection logic based on your sample file."
detect_hints="${detect_hints}"$'\n'"    # First few lines of your sample:"
while IFS= read -r hint_line; do
    detect_hints="${detect_hints}"$'\n'"    #   $hint_line"
done <<< "$sample_head"

# Convert name to function-safe prefix (hyphens to underscores)
func_prefix="${opt_name//-/_}"

# Write strategy file
cat > "$strategy_file" <<STRATEGY_EOF
#!/bin/bash
## Name: ${opt_name}
## Description: ${opt_description}
## Version: ${opt_version}
## Priority: ${opt_priority}
## Sample: samples/${opt_name}/sample1.txt

strategy_detect () {
    local text="\$1"
    local filename="\${2:-}"
    local encoding_hint="\${3:-}"
    _STRATEGY_CONFIDENCE=50
    _STRATEGY_CONFIDENCE_REASON=""

${detect_hints}
    #
    # Set _STRATEGY_CONFIDENCE (0-100) based on match quality.
    # Set _STRATEGY_CONFIDENCE_REASON for explain mode.
    # Return 0 if this strategy should apply, 1 otherwise.

    # Example: check for a distinctive pattern in the input
    # local _nl=\$'\\n'
    # if [[ "\$text" == *"some_pattern"* ]]; then
    #     _STRATEGY_CONFIDENCE=80
    #     _STRATEGY_CONFIDENCE_REASON="found distinctive pattern"
    #     return 0
    # fi

    return 1
}

strategy_extract () {
    local text="\$1"
    local filename="\${2:-}"
    local encoding_hint="\${3:-}"
    local result=""

    # TODO: Implement extraction logic.
    #
    # Use _clean_field for field NAMES and _clean_value for VALUES (a value
    # keeps its inner spaces: the name ends at the first space).
    # Output format: one "fieldname value" pair per line on stdout.
    # Prefix helper functions with _strat_${func_prefix}_ to avoid conflicts.
    #
    # Example:
    # while IFS= read -r line; do
    #     [[ -z "\$line" ]] && continue
    #     if [[ "\$line" == *": "* ]]; then
    #         local key="\${line%%: *}"
    #         local val="\${line#*: }"
    #         _clean_field "\$key"; key="\$_CLEANED"
    #         _clean_value "\$val"; val="\$_CLEANED"
    #         [[ -z "\$key" || -z "\$val" ]] && continue
    #         result+="\${key} \${val}"\$'\\n'
    #     fi
    # done <<< "\$text"

    [[ -n "\$result" ]] && printf '%s' "\$result"
}
STRATEGY_EOF

chmod +x "$strategy_file"
echo "Created strategy file: $strategy_file"

echo ""
echo "Next steps:"
echo "  1. Edit the strategy_detect() function to match your format"
echo "  2. Edit the strategy_extract() function to extract fields"
echo "  3. Validate: provost-extract validate $strategy_file"
echo "  4. Test: provost-extract -d -s ${opt_name} $sample_dir/sample1.txt"
echo "  5. Add tests: tests/test_strategy_${func_prefix}.sh"
