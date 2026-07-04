# Handoff -- EnvoyExtract/lib

## Status: New in v4.0

Sourced modules extracted from the monolithic `envoy-extract` during the v4.0 refactoring.

## Modules

| Module | Purpose | Dependencies |
|--------|---------|-------------|
| `_log.sh` | Unified logging functions | none |
| `_helpers.sh` | Pure-bash utilities (trim, clean, count, parse) | none |
| `_format.sh` | Output formatters (JSON, CSV, TSV, YAML, XML, display) | `_helpers.sh` |
| `_postprocess.sh` | Store, dedup, rename, aggregate, filter | `_helpers.sh` |
| `_discovery.sh` | Strategy find, load, detect, execute | `_log.sh`, `_helpers.sh`, `_postprocess.sh` |
| `_interactive.sh` | TUI field selector with keyboard navigation | `_helpers.sh` |
| `_validate.sh` | Strategy file validation | `_log.sh`, `_discovery.sh` |

## Source Order (in envoy-extract)

```bash
source "$SCRIPT_DIR/lib/_log.sh"
source "$SCRIPT_DIR/lib/_helpers.sh"
source "$SCRIPT_DIR/lib/_format.sh"
source "$SCRIPT_DIR/lib/_postprocess.sh"
source "$SCRIPT_DIR/lib/_discovery.sh"
source "$SCRIPT_DIR/lib/_interactive.sh"
source "$SCRIPT_DIR/lib/_validate.sh"
```

Order matters: each module can use functions from modules sourced before it.

## Conventions

- All functions use `_UPPERCASE` globals for return values (no `$()` subshell overhead)
- Functions prefixed with `_` are internal helpers
- CLI option globals use `_OPT_*` prefix
- Metadata globals use `_META_*` prefix
- Bash 3.2 compatible (macOS default): no associative arrays, no `local -n`

## Global Variables Reference

### CLI Options (`_OPT_*`) — set in `envoy-extract` option parsing

| Variable | Type | Description |
|----------|------|-------------|
| `_OPT_help` | 0/1 | Show help |
| `_OPT_version` | 0/1 | Show version |
| `_OPT_list` | 0/1 | List strategies |
| `_OPT_strategy` | string | Single strategy name |
| `_OPT_format` | string | Output format (json/csv/tsv/plain/yaml/xml) |
| `_OPT_format_explicit` | 0/1 | Format was explicitly set |
| `_OPT_raw` | 0/1 | Raw output mode |
| `_OPT_debug` | 0/1 | Debug logging |
| `_OPT_verbose` | 0/1 | Verbose logging |
| `_OPT_quiet` | 0/1 | Quiet mode |
| `_OPT_cmdline` | 0/1 | Export replay command |
| `_OPT_replay` | string | Replay spec (name@ver,name@ver) |
| `_OPT_count` | 0/1 | Count-only mode |
| `_OPT_names` | 0/1 | Names-only mode |
| `_OPT_sort` | 0/1 | Sort output by name |
| `_OPT_min_confidence` | int | Minimum confidence threshold (0-100) |
| `_OPT_first_match` | 0/1 | Stop after first match |
| `_OPT_max_strategies` | int | Max strategies to match |
| `_OPT_delimiter` | string | Custom delimiter |
| `_OPT_rename` | string | Rename spec (old=new,old=new) |
| `_OPT_aggregate` | 0/1 | Aggregate numeric fields |
| `_OPT_stream` | 0/1 | Streaming mode |
| `_OPT_chain` | string | Chain spec (A\|B) |
| `_OPT_plugin_dir` | string | Additional strategy directory |
| `_OPT_no_dedup` | 0/1 | Skip deduplication |
| `_OPT_output` | string | Output file path |
| `_OPT_profile` | 0/1 | Per-strategy timing |
| `_OPT_auto_tune` | 0/1 | Auto-adjust confidence |
| `_OPT_interactive` | 0/1 | Interactive selection |
| `_OPT_max_input_size` | int | Max input bytes |
| `_OPT_validate_strategy` | string | Strategy file to validate |
| `_OPT_validate_all` | 0/1 | Validate all strategies |

### Strategy Metadata (`_META_*`) — set by `read_strategy_metadata()` in `_discovery.sh`

| Variable | Type | Description |
|----------|------|-------------|
| `_META_NAME` | string | Strategy name from `## Name:` header |
| `_META_DESCRIPTION` | string | Strategy description from `## Description:` header |
| `_META_VERSION` | string | Strategy version from `## Version:` header (default "0") |
| `_META_PRIORITY` | string | Strategy priority from `## Priority:` header (default "99") |

### Function Return Globals — set by helper functions, read by callers

| Variable | Set by | Description |
|----------|--------|-------------|
| `_STRIPPED_LINE` | `strip_strat_prefix()` | Line with STRAT-name:N prefix removed |
| `_TRIMMED` | `_trim()` | Whitespace-trimmed string |
| `_CLEANED` | `_clean_field()` | Trimmed with spaces replaced by underscores |
| `_LINE_COUNT` | `_count_lines()` | Number of non-empty lines |
| `_FIELD_NAME` | `_parse_field_line()` | Parsed field name from "name value" line |
| `_FIELD_VALUE` | `_parse_field_line()` | Parsed field value from "name value" line |
| `_CLEAN_TEXT_RESULT` | `clean_text()` | Normalized text (dates/parens cleaned) |
| `_CLEAN_TEXT_CACHE` | `clean_text()` | Cached result for repeat calls |
| `_CLEAN_TEXT_DONE` | `clean_text()` | 0/1 flag for cache validity |
| `_ESCAPED` | `_json_escape()`, `_xml_escape()` | Escaped string for output |
| `_NTH_RESULT` | `_interactive_get_nth()` | Nth value from newline-delimited list |
| `_SELECTED_FIELDS` | `_interactive_select()` | Comma-separated selected field numbers |
| `_FOUND_STRATEGY_FILE` | `find_strategy_file()` | Path to located strategy file |
| `_SORTED_STRATEGIES` | `_resolve_strategy_list()` | Priority-sorted strategy list |
| `_REPLAY_STRATEGIES` | `_parse_replay_spec()` | Newline-separated replay strategy names |
| `_REPLAY_VERSIONS` | `_parse_replay_spec()` | Newline-separated name=version pairs |

### Strategy Interface Globals — set by strategies in `strategy_detect()`

| Variable | Set by | Description |
|----------|--------|-------------|
| `_STRATEGY_CONFIDENCE` | `strategy_detect()` | Confidence score 0-100 (default 50) |
| `_STRATEGY_CONFIDENCE_REASON` | `strategy_detect()` | Human-readable reason for confidence level |

### Engine State Globals — set/read during strategy execution in `envoy-extract`

| Variable | Description |
|----------|-------------|
| `text` | Full input text being processed |
| `output` | Accumulated extraction results (STRAT-prefixed lines) |
| `matched_strategies` | Comma-separated "name@version" of matched strategies |
| `near_miss_strategies` | Comma-separated near-miss strategy info |
| `strategies_tried` | Count of strategies attempted |
| `strategies_matched` | Count of strategies that produced output |
| `total_fields` | Total fields extracted across all strategies |
| `_STATE_filename` | Input filename (empty for stdin) |
| `_STATE_encoding_hint` | Encoding hint from file extension |
