#!/bin/bash
# ENV-068: envoy-browse w/W export keybindings — exercise export helpers
# without a live TTY by sourcing envoy-browse under MDX_TESTING=1.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

BROWSE="$(cd "$SCRIPT_DIR/.." && pwd)/envoy-browse"

_run_in_sourced_env () {
    # Run the body in a subshell that sources envoy-browse with MDX_TESTING=1,
    # populates a tiny fixture, and invokes the requested callback.
    # We pass the test body via an env var because envoy-browse's arg-parse
    # loop consumes positional parameters on source.
    local body="$1"
    ENV068_TEST_BODY="$body" BROWSE="$BROWSE" MDX_TESTING=1 \
        bash -c '
            set +e
            source "$BROWSE"
            trap - ERR
            set +e

            SELECTABLE=(0 1)
            ITEM_TAG=(); ITEM_TAG[0]="GOOD"; ITEM_TAG[1]="ADVANCED"
            ITEM_TITLE=(); ITEM_TITLE[0]="Dataset overview"; ITEM_TITLE[1]="Column types"
            ITEM_BODY=(); ITEM_BODY[0]="Rows: 10 Cols: 4"; ITEM_BODY[1]="a: numeric b: categorical"
            VAR_NAMES=()
            VAR_TAG=()
            selected_pos=0
            export_path=""
            export_mode=0
            status_msg=""

            eval "$ENV068_TEST_BODY"
        ' _inner < /dev/null
    return $?
}

test_default_path_current () {
    local out
    out=$(_run_in_sourced_env 'p=$(export_default_path current); printf "%s" "$p"')
    if [[ "$out" != ./envoy-browse-item-* ]]; then
        echo "  ASSERT FAILED: default current path format: $out"
        return 1
    fi
    if [[ "$out" != *.txt ]]; then
        echo "  ASSERT FAILED: default path should end in .txt: $out"
        return 1
    fi
}

test_default_path_all () {
    local out
    out=$(_run_in_sourced_env 'p=$(export_default_path all); printf "%s" "$p"')
    if [[ "$out" != ./envoy-browse-all-* ]]; then
        echo "  ASSERT FAILED: default all-path format: $out"
        return 1
    fi
}

test_export_current_writes_file () {
    local tmp
    tmp=$(mktemp -t env068.XXXXXX)
    rm -f "$tmp"
    _run_in_sourced_env "do_export current '$tmp'; printf '%s' \"\$status_msg\""
    if [[ ! -f "$tmp" ]]; then
        echo "  ASSERT FAILED: export current should create $tmp"
        return 1
    fi
    local content
    content=$(cat "$tmp")
    assert_contains "$content" "Dataset overview" "focused item title present"
    assert_contains "$content" "[GOOD]" "tag present"
    rm -f "$tmp"
}

test_export_all_writes_both_items () {
    local tmp
    tmp=$(mktemp -t env068all.XXXXXX)
    rm -f "$tmp"
    _run_in_sourced_env "do_export all '$tmp'"
    if [[ ! -f "$tmp" ]]; then
        echo "  ASSERT FAILED: export all should create $tmp"
        return 1
    fi
    local content
    content=$(cat "$tmp")
    assert_contains "$content" "Dataset overview" "first item present"
    assert_contains "$content" "Column types" "second item present"
    rm -f "$tmp"
}

test_export_refuses_directory () {
    local d
    d=$(mktemp -d -t env068dir.XXXXXX)
    local out
    out=$(_run_in_sourced_env "do_export current '$d'; printf '%s' \"\$status_msg\"")
    rmdir "$d"
    assert_contains "$out" "is a directory" "directory target rejected"
}

test_export_empty_selection_errors () {
    local out
    out=$(BROWSE="$BROWSE" MDX_TESTING=1 bash -c '
        source "$BROWSE"
        trap - ERR
        set +e
        SELECTABLE=()
        ITEM_TAG=(); ITEM_TITLE=(); ITEM_BODY=()
        VAR_NAMES=(); VAR_TAG=()
        selected_pos=0
        status_msg=""
        do_export current /tmp/env068empty.txt
        printf "%s" "$status_msg"
    ' _inner < /dev/null)
    assert_contains "$out" "Nothing to export" "empty selection handled"
}

test_keybinding_registered () {
    # Confirm the `w` / `W` cases exist in the dispatch
    grep -qE '^[[:space:]]*w\)[[:space:]]*$' "$BROWSE" || { echo "  ASSERT FAILED: w) key not registered"; return 1; }
    grep -qE '^[[:space:]]*W\)[[:space:]]*$' "$BROWSE" || { echo "  ASSERT FAILED: W) key not registered"; return 1; }
}

test_help_overlay_lists_export () {
    grep -q 'Write the focused item' "$BROWSE" || {
        echo "  ASSERT FAILED: help overlay missing Export section"
        return 1
    }
}

run_test "ENV-068 default current path" test_default_path_current
run_test "ENV-068 default all path" test_default_path_all
run_test "ENV-068 export current writes file" test_export_current_writes_file
run_test "ENV-068 export all writes every item" test_export_all_writes_both_items
run_test "ENV-068 export refuses directory target" test_export_refuses_directory
run_test "ENV-068 empty selection errors cleanly" test_export_empty_selection_errors
run_test "ENV-068 w/W keybindings registered" test_keybinding_registered
run_test "ENV-068 help overlay lists export section" test_help_overlay_lists_export

print_summary
