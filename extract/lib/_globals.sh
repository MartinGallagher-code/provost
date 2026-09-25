#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Global Variable Registry for envoy-extract
##
## DOCUMENTATION ONLY — this file is NOT sourced by envoy-extract or any module.
##
## This file documents every cross-module global used by the envoy-extract engine.
## It does NOT set variables — that is done by the owning module.
## It is a reference file for developers; it has no runtime effect.
## It exists as a single authoritative reference for:
##   - What each global means
##   - Which module owns / writes it
##   - Which modules read it
##   - Its type and default value
##
## Conventions:
##   _OPT_*         CLI option flags (envoy-extract → all modules)
##   _META_*        Strategy metadata (lib/_discovery.sh)
##   _TECH_*        Technique function return values (lib/_techniques.sh)
##   _STATE_*       Per-run input metadata (envoy-extract)
##   UPPER_CASE     Script-level constants (envoy-extract, set once at startup)
##   lower_case     Run-time accumulators (lib/_discovery.sh)
################################################################################

################################################################################
## SECTION 1: Script-level constants
## Owner: envoy-extract (set once at startup, never modified)
################################################################################

# SCRIPT_DIR
#   Type:    string (absolute path)
#   Default: computed from BASH_SOURCE[0]
#   Owner:   envoy-extract
#   Readers: _discovery.sh, _validate.sh
#   Purpose: Absolute path to the directory containing envoy-extract.
#            Used to resolve lib/ and strategies/ paths.

# STRATEGIES_DIR
#   Type:    string (absolute path)
#   Default: "$SCRIPT_DIR/strategies"
#   Owner:   envoy-extract
#   Readers: _discovery.sh, _validate.sh
#   Purpose: Path to the built-in strategy directory.

################################################################################
## SECTION 2: CLI option flags (_OPT_*)
## Owner: envoy-extract option-parsing block (lines ~142-174)
## Readers: all lib modules
################################################################################

# _OPT_help              bool (0/1)  default 0  -- show usage and exit
# _OPT_version           bool (0/1)  default 0  -- print version and exit
# _OPT_list              bool (0/1)  default 0  -- list strategies and exit
# _OPT_strategy          string      default ""  -- run only this named strategy
# _OPT_format            string      default "json"  -- output format: json|csv|tsv|plain|yaml|xml
# _OPT_format_explicit   bool (0/1)  default 0  -- set to 1 if -f was given explicitly
# _OPT_raw               bool (0/1)  default 0  -- emit raw output without formatting
# _OPT_debug             bool (0/1)  default 0  -- enable [debug] log messages
# _OPT_verbose           bool (0/1)  default 0  -- enable [info] summaries
# _OPT_quiet             bool (0/1)  default 0  -- suppress output; exit 0/1 for found/not-found
# _OPT_cmdline           bool (0/1)  default 0  -- print replay command line and exit
# _OPT_replay            string      default ""  -- "name@ver,..." replay spec
# _OPT_count             bool (0/1)  default 0  -- output field count only
# _OPT_names             bool (0/1)  default 0  -- output field names only
# _OPT_sort              bool (0/1)  default 0  -- sort output fields alphabetically
# _OPT_min_confidence    integer     default 0   -- skip strategies below this confidence
# _OPT_first_match       bool (0/1)  default 0  -- stop after first strategy produces output
# _OPT_max_strategies    integer     default 0   -- limit strategies that produce output (0=no limit)
# _OPT_rank              string      default "confidence" (env MFE_RANK) -- candidate order:
#                                    confidence = run every detector, try best confidence first;
#                                    priority   = first detecting strategy in priority order
# _OPT_delimiter         string      default ""  -- custom delimiter (e.g. "=>", "::")
# _OPT_rename            string      default ""  -- "old=new,..." field rename spec
# _OPT_aggregate         bool (0/1)  default 0  -- compute count/min/max/sum/avg for numerics
# _OPT_stream            bool (0/1)  default 0  -- stream stdin line-by-line as JSON Lines
# _OPT_chain             string      default ""  -- "A|B" chain spec; pipe A output into B
# _OPT_plugin_dir        string      default ""  -- additional strategy directory
# _OPT_no_dedup          bool (0/1)  default 0  -- skip deduplication across strategies
# _OPT_output            string      default ""  -- redirect stdout to this file path
# _OPT_profile           bool (0/1)  default 0  -- print per-strategy timing to stderr
# _OPT_auto_tune         bool (0/1)  default 0  -- auto-adjust confidence; rank best strategy
# _OPT_interactive       bool (0/1)  default 0  -- TUI field picker before output
# _OPT_max_input_size    integer     default 52428800 (50 MB)  -- max input bytes
# _OPT_validate_strategy string      default ""  -- path to strategy file to validate, then exit
# _OPT_validate_all      bool (0/1)  default 0  -- validate all strategies and exit
# _OPT_generic           bool (0/1)  default 0  -- only strategies/delimited/ + structured/
# _OPT_batch             bool (0/1)  default 0  -- batch mode: read file paths from stdin, emit JSON Lines

################################################################################
## SECTION 3: Input metadata (_STATE_*)
## Owner: envoy-extract input-reading block
## Readers: _discovery.sh (passed to strategy_detect / strategy_extract)
################################################################################

# _STATE_filename
#   Type:    string
#   Default: "$file" (or "" for stdin)
#   Owner:   envoy-extract
#   Readers: _discovery.sh (_detect_strategy, _extract_and_store)
#   Purpose: Original file path; passed as $2 to strategy_detect/extract
#            so strategies can use the filename as a detection hint.

# _STATE_encoding_hint
#   Type:    string (e.g. "utf-8" or "")
#   Default: "" (or "utf-8" for known text extensions)
#   Owner:   envoy-extract
#   Readers: _discovery.sh
#   Purpose: Encoding hint derived from file extension; passed as $3 to
#            strategy_detect/extract for advisory use.

################################################################################
## SECTION 4: Input content cache
## Owner: envoy-extract input-reading block; _CLEAN_TEXT_* also written by _helpers.sh
################################################################################

# text
#   Type:    string
#   Default: set by envoy-extract input reading block
#   Owner:   envoy-extract
#   Readers: _discovery.sh (run_auto_strategies, _run_custom_delimiter),
#            _dispatch.sh (run_stream_mode, run_output_mode hints)
#   Purpose: Full content of the input file or stdin.

# file
#   Type:    string (path or "")
#   Default: "" (stdin mode)
#   Owner:   envoy-extract positional-argument parsing
#   Readers: envoy-extract, _dispatch.sh (run_output_mode -c, run_stream_mode check)
#   Purpose: Input file path provided on the command line; "" means stdin.

# fields
#   Type:    string (comma-separated field numbers or names)
#   Default: "" (no filter; all fields)
#   Owner:   envoy-extract positional-argument parsing; overwritten by _interactive.sh
#   Readers: _dispatch.sh (run_output_mode)
#   Purpose: Field filter specification. Updated by interactive mode.

# _CLEAN_TEXT_CACHE
#   Type:    string
#   Default: ""
#   Owner:   _helpers.sh (clean_text)
#   Readers: _helpers.sh (clean_text cache hit)
#   Purpose: Cached result of clean_text() to avoid repeated normalisation.

# _CLEAN_TEXT_DONE
#   Type:    bool (0/1)
#   Default: 0 (set in envoy-extract before strategy execution)
#   Owner:   _helpers.sh (clean_text sets to 1 on first call)
#   Readers: _helpers.sh (clean_text)
#   Purpose: Guards the clean_text cache; reset to 0 by envoy-extract each run.

################################################################################
## SECTION 5: Strategy execution accumulators
## Owner: _discovery.sh (run_auto_strategies, _extract_and_store, etc.)
## Readers: _dispatch.sh, _autotune.sh
################################################################################

# output
#   Type:    string (newline-delimited tagged lines)
#   Default: "" (reset at start of run_auto_strategies / run_chain_strategies)
#   Owner:   _postprocess.sh (store), _discovery.sh, _autotune.sh
#   Readers: _dispatch.sh, _postprocess.sh
#   Format:  "STRAT-<name>:<lineno>\t<field> <value>\n"
#   Purpose: Accumulates all extracted fields tagged with their source strategy.

# matched_strategies
#   Type:    string (comma-separated "name@version")
#   Default: ""
#   Owner:   _discovery.sh (_extract_and_store, run_chain_strategies)
#   Readers: _dispatch.sh (run_output_mode -c), _autotune.sh
#   Purpose: Records which strategies produced output, used for --replay export
#            and auto-tune best-match ranking.

# near_miss_strategies
#   Type:    string (comma-separated "name(reason)")
#   Default: ""
#   Owner:   _discovery.sh (_detect_strategy, _extract_and_store)
#   Readers: _dispatch.sh (run_output_mode no-fields hint)
#   Purpose: Strategies that detected but produced no output, or were below the
#            confidence threshold; surfaced to the user as suggestions.

# strategies_tried
#   Type:    integer
#   Default: 0
#   Owner:   _discovery.sh (run_auto_strategies)
#   Readers: _dispatch.sh (verbose summary via _postprocess.sh)
#   Purpose: Count of all strategies attempted (detect + extract phases).

# strategies_matched
#   Type:    integer
#   Default: 0
#   Owner:   _discovery.sh (_extract_and_store, _run_custom_delimiter)
#   Readers: _dispatch.sh, _autotune.sh
#   Purpose: Count of strategies that produced at least one field.

# total_fields
#   Type:    integer
#   Default: 0
#   Owner:   _discovery.sh (_extract_and_store, _run_custom_delimiter)
#   Readers: _dispatch.sh (verbose summary)
#   Purpose: Total number of field lines extracted across all strategies.

################################################################################
## SECTION 6: Strategy discovery temporaries
## Owner: _discovery.sh
################################################################################

# _FOUND_STRATEGY_FILE
#   Type:    string (absolute path or "")
#   Default: "" (reset at start of find_strategy_file)
#   Owner:   _discovery.sh (find_strategy_file)
#   Readers: _discovery.sh (run_auto_strategies, run_stream_mode)
#   Purpose: Return value from find_strategy_file(); path to located strategy.

# _SORTED_STRATEGIES
#   Type:    string (newline-delimited "priority|version|filepath")
#   Default: ""
#   Owner:   _discovery.sh (_resolve_strategy_list)
#   Readers: _discovery.sh (run_auto_strategies)
#   Purpose: Priority-sorted list of strategy file entries for the current run.

# _REPLAY_STRATEGIES
#   Type:    string (newline-delimited strategy names)
#   Default: ""
#   Owner:   _discovery.sh (_parse_replay_spec)
#   Readers: _discovery.sh (_should_run_strategy)
#   Purpose: Names of strategies to replay from --replay spec.

# _REPLAY_VERSIONS
#   Type:    string (newline-delimited "name=version" pairs)
#   Default: ""
#   Owner:   _discovery.sh (_parse_replay_spec)
#   Readers: _discovery.sh (_check_replay_version)
#   Purpose: Version constraints from --replay spec for mismatch warnings.

################################################################################
## SECTION 7: Strategy metadata (_META_*)
## Owner: _discovery.sh (read_strategy_metadata)
## Readers: _discovery.sh, _validate.sh
################################################################################

# _META_NAME          string  default ""   -- value of ## Name: header
# _META_DESCRIPTION   string  default ""   -- value of ## Description: header
# _META_VERSION       string  default "0"  -- value of ## Version: header
# _META_PRIORITY      string  default "99" -- value of ## Priority: header
# _META_TECHNIQUE     string  default ""   -- value of ## Technique: header ("yes" = generic)

################################################################################
## SECTION 8: Strategy interface globals
## Owner: individual strategy files (strategy_detect writes; strategy_extract reads)
## Readers: _discovery.sh (_detect_strategy)
################################################################################

# _STRATEGY_CONFIDENCE
#   Type:    integer (0-100)
#   Default: 50 (set by _detect_strategy before calling strategy_detect)
#   Owner:   strategy_detect() in each strategy file
#   Readers: _discovery.sh (_detect_strategy)
#   Purpose: Confidence score set by a strategy to indicate how likely the input
#            matches its format. Used with --min-confidence filtering.

# _STRATEGY_CONFIDENCE_REASON
#   Type:    string (optional)
#   Default: "" (reset implicitly; strategies may leave it unset)
#   Owner:   strategy_detect() (optional)
#   Readers: _discovery.sh (_detect_strategy, for debug log)
#   Purpose: Human-readable explanation for the confidence score.

################################################################################
## SECTION 9: Helper function return globals
## Owner: respective functions in lib/
################################################################################

# _STRIPPED_LINE     string  -- _helpers.sh: strip_strat_prefix() result
# _TRIMMED           string  -- _helpers.sh: _trim() result
# _CLEANED           string  -- _helpers.sh: _clean_field() (name) / _clean_value() result
# _RESTORED_TEXT     string  -- _helpers.sh: restore_text_values() result
# _LINE_COUNT        integer -- _helpers.sh: _count_lines() result
# _FIELD_NAME        string  -- _helpers.sh: _parse_field_line() name half
# _FIELD_VALUE       string  -- _helpers.sh: _parse_field_line() value half
# _CLEAN_TEXT_RESULT string  -- _helpers.sh: clean_text() result (also cached)
# _ESCAPED           string  -- _format.sh: _json_escape() / _xml_escape() result
# _YAML_NEEDS_QUOTE  bool    -- _format.sh: _yaml_needs_quote() result (0/1)
# _TECH_STRIPPED     string  -- _techniques.sh: _tech_strip_leading() result
# _TECH_KEY_VALID    bool    -- _techniques.sh: _tech_validate_key() result (0=invalid, 1=valid)
# _TECH_BLOCKS       string  -- _techniques.sh: _tech_split_blocks() SOH-delimited result
# _SELECTED_FIELDS   string  -- _interactive.sh: _interactive_select() comma-sep field numbers
# _NTH_RESULT        string  -- _interactive.sh: _interactive_get_nth() result
