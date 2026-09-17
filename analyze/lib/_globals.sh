#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Global Variable Registry for envoy-analyze (ENV-066)
##
## This file documents all global variables used across modules. It is NOT
## sourced — it serves as documentation only. The registry pairs with the
## ## Reads: / ## Writes: headers on each `lib/*.sh` module, and is enforced
## by tests/test_module_contracts.sh.
##
## OWNER: the module responsible for writing this variable.
## TYPE:  string | int | flag (0/1) | array
##
## Evolution: any new cross-module global MUST be added here AND to the
## owning module's ## Writes: list. The static check fails otherwise.
################################################################################

# --- Constants (owner: envoy-analyze) ---
# MAX_CORR_COLS=8              # int: max columns in correlation matrix
# MAX_GROUP_UNIQUE=12          # int: max unique values for grouping
# MAX_GROUPS=5                 # int: max groups displayed
# MAX_GROUP_NUM_COLS=4         # int: max numeric columns for group summary
# SPARK_SAMPLES=24             # int: sparkline sample size

# --- CLI Options (owner: envoy-analyze option parser) ---
# input_file=""                # string: input file path
# analysis_list=""             # string: comma-delimited analysis numbers
# profile_name=""              # string: loaded profile name
# save_name=""                 # string: save profile name
# profile_dir=""               # string: profile directory path
# forced_delim=""              # string: user-forced delimiter
# only_good=0                  # flag: --good flag
# tag_filter=""                # string: --tags filter
# kind_filter=""               # string: --kinds filter
# suggest_only=0               # flag: --suggest flag
# suggest_save_name=""         # string: --suggest-save name
# output_format="plain"        # string: plain|json|csv|tsv
# cleanup_files=()             # array: temp files to clean on EXIT
# compare_files=()             # array: --compare paths (owner: option parser; reader: _compare.sh)
# _STRIP_BOM_RESULT=""         # string: working file path after BOM strip (owner: _csv.sh::strip_bom)

# --- Input Metadata (owner: envoy-analyze) ---
# delim=""                     # string: detected/forced delimiter
# delim_name=""                # string: "comma"|"tab"|"semicolon"
# COL_NAMES=()                 # array: column names from header
# COL_COUNT=0                  # int: number of columns
# ROW_COUNT=0                  # int: number of data rows
# file_size=""                 # string: file size in bytes

# --- Per-Column Statistics (owner: envoy-analyze column stats loop) ---
# COL_TYPE=()                  # array: "numeric" or "categorical"
# COL_NUMERIC=()               # array: count of numeric values per column
# COL_TEXT=()                  # array: count of non-numeric values per column (ENV-132)
# COL_MEAN=()                  # array: mean (numeric only, "" for categorical)
# COL_STD=()                   # array: std dev (numeric only)
# COL_SKEW=()                  # array: skewness (numeric only)
# COL_KURT=()                  # array: excess kurtosis (numeric only)
# COL_MIN=()                   # array: min value (numeric only)
# COL_MAX=()                   # array: max value (numeric only)
# COL_UNIQUE=()                # array: unique value count (categorical)
# COL_MISSING=()               # array: missing value count per column

# --- Column Index Lists (owner: envoy-analyze) ---
# NUM_COL_INDEXES=()           # array: 1-indexed column numbers for numeric columns
# NUM_COL_NAMES=()             # array: names of numeric columns
# CAT_COL_INDEXES=()           # array: 1-indexed column numbers for categorical columns
# CAT_COL_NAMES=()             # array: names of categorical columns

# --- Analysis Item Pipeline (owner: envoy-analyze / add_item()) ---
# ITEM_TITLES=()               # array: analysis title strings
# ITEM_BODIES=()               # array: analysis body text
# ITEM_TAGS=()                 # array: GOOD | NOISY | ADVANCED | DIAGNOSTIC
# ITEM_KINDS=()                # array: overview | col_types | histogram | etc.

# --- Correlation State (owner: lib/_correlation.sh) ---
# CORR_VALUES=()               # array: flattened correlation matrix (row-major)
# corr_cols=()                 # array: numeric column indexes in correlation matrix
# corr_names=()                # array: names of columns in correlation matrix
# _CORR_PAIR_LINES=""          # string: tab-delimited pair data for reuse

# --- Return-Value Globals (owner: lib/_numeric.sh) ---
# _NUM_P05=""                  # string: 5th percentile from anomaly detection
# _NUM_Q1=""                   # string: 25th percentile
# _NUM_P50=""                  # string: median
# _NUM_Q3=""                   # string: 75th percentile
# _NUM_P95=""                  # string: 95th percentile

# --- Quality State (owner: lib/_quality.sh) ---
# dup_count=0                  # int: duplicate row count (shared with noisy items)

# --- Threshold State (owner: lib/_threshold.sh) ---
# threshold_specs=()           # array: user-provided threshold specs
# threshold_exit_code=0        # flag: 1 if any threshold failed

# --- Missing-value awk contract (owner: lib/_helpers.sh, mutated in envoy-analyze) ---
# AWK_ISMISSING=""             # string: awk function definition for ismissing(v)

# --- ENV-063 sampling (owner: envoy-analyze) ---
# head_n=""                    # string: --head N value
# sample_n=""                  # string: --sample N value
# sample_seed=""               # string: --seed S value
# SAMPLE_NOTE=""               # string: banner note for dataset-overview

# --- ENV-065 colour (owner: envoy-analyze) ---
# color_when="auto"            # string: --color WHEN
# COLOR_ENABLED=0              # flag: resolved decision (read by _format.sh)

# --- ENV-067 Benford alpha (owner: envoy-analyze) ---
# BENFORD_ALPHA="0.05"         # string: significance level
# BENFORD_CRIT="15.507"        # string: chi-squared df=8 critical value

# --- ENV-064 JSON envelope (owner: envoy-analyze) ---
# VERSION=""                   # string: tool version, embedded in JSON output

# --- envoy-browse state (owner: envoy-browse) ---
# Not listed here — envoy-browse is a separate entry point and does not share
# module globals with envoy-analyze's lib/*.sh.
