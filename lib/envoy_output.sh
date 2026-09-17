#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Envoy Shared Output Helper — envoy_output.sh  (ENV-152)
##
## Atomic file output with --force / parent-dir-creation / `-` stdout
## semantics, mirroring the conventions of `curl -o`, `wget -O`, and
## `tar -f`.  Sourcing is OPTIONAL — every tool keeps working without
## the helper; callers that want safer file output get it.
##
## Public API
## ----------
##   envoy_output_filter FILE [FORCE]
##       Stdin filter.  Reads stdin and writes it to FILE atomically:
##         - FILE = "-" or "/dev/stdout"  -> writes to stdout (passthrough)
##         - FILE = "/dev/stderr"         -> writes to stderr (no atomic rename)
##         - Otherwise:                     write to FILE.tmp, rename on success
##       FORCE = 1 overwrites an existing FILE; otherwise refuses with
##       a message on stderr and returns 1.
##       Creates the parent directory tree if missing.
##
##       Returns 0 on success, non-zero on overwrite-refused / I/O error.
##
##       Usage:
##           if [[ -n "$_opt_output" ]]; then
##               run_command | envoy_output_filter "$_opt_output" "$_opt_force"
##               rc="${PIPESTATUS[1]}"
##           else
##               run_command
##           fi
##
##   envoy_output_validate FILE [FORCE]
##       Pre-flight check the same conditions without consuming stdin.
##       Returns 0 if a subsequent envoy_output_filter would succeed.
##       Useful for failing fast before running expensive computation.
##
## Conventions
## -----------
##   - Atomic rename via `mv FILE.tmp FILE` after the producer exits 0
##     and stdin is drained.  A SIGKILL on the parent during the pipe
##     leaves only `FILE.tmp` on disk; the on-disk FILE is unchanged.
##     Callers who want to clean up `.tmp` remnants can `rm FILE.tmp`
##     in their own EXIT trap; we don't install a global trap because
##     the tmp filename is local.
##   - Refuses to overwrite without --force, matching `mv -i` / `cp -i`
##     friendliness for interactive use.  Non-interactive scripts pass
##     --force explicitly, mirroring `curl --output --create-dirs`.
##   - Parent-dir creation is unconditional (no flag).  Documented
##     behaviour: `-o subdir/file.json` creates `subdir/` automatically.
##
## Reads (env / globals): none
## Writes (globals):      none (pure aside from filesystem effects)
################################################################################

# Guard against double-sourcing
[[ -n "${_ENVOY_OUTPUT_LOADED:-}" ]] && return 0
_ENVOY_OUTPUT_LOADED=1

################################################################################
## envoy_output_validate FILE [FORCE]
##
## Returns 0 if a subsequent envoy_output_filter would succeed; non-zero
## with a stderr message otherwise.  Exists so callers can fail fast
## before doing expensive computation.
##
## Pseudo-paths "-", "/dev/stdout", "/dev/stderr" always validate.
################################################################################

envoy_output_validate() {
    local file="${1:-}"
    local force="${2:-0}"

    if [[ -z "$file" ]]; then
        printf 'envoy: error: --output requires a path\n' >&2
        return 2
    fi

    case "$file" in
        -|/dev/stdout|/dev/stderr|/dev/null)
            return 0
            ;;
    esac

    if [[ -e "$file" && "$force" != "1" ]]; then
        printf 'envoy: error: refusing to overwrite existing file: %s\n' "$file" >&2
        printf '       pass --force to overwrite\n' >&2
        return 1
    fi

    # Parent-dir writeability.  We create it on demand in the filter,
    # so just check we *could* create it.
    local dir
    dir="$(dirname -- "$file")"
    if [[ -n "$dir" && "$dir" != "." && ! -d "$dir" ]]; then
        # Try a no-op mkdir -p; it'll fail with the same EACCES / EROFS
        # error the filter would, so the user sees the diagnostic now.
        if ! mkdir -p -- "$dir" 2>/dev/null; then
            printf 'envoy: error: cannot create parent directory: %s\n' "$dir" >&2
            return 1
        fi
    fi
    return 0
}

################################################################################
## envoy_output_filter FILE [FORCE]
##
## Stdin -> FILE atomically.
##
## Special-case paths handled by `cat`-equivalent passthrough rather
## than the .tmp + rename dance:
##   - "-"            : stdout
##   - "/dev/stdout"  : stdout (alias for `-`)
##   - "/dev/stderr"  : stderr (uncommon but supported)
##   - "/dev/null"    : discard
##
## Everything else goes through `FILE.tmp` -> `mv FILE.tmp FILE`.
################################################################################

envoy_output_filter() {
    local file="${1:-}"
    local force="${2:-0}"

    envoy_output_validate "$file" "$force" || return $?

    case "$file" in
        -|/dev/stdout)  cat ;;
        /dev/stderr)    cat >&2 ;;
        /dev/null)      cat >/dev/null ;;
        *)
            local dir tmp
            dir="$(dirname -- "$file")"
            # validate already created the parent if missing.

            # Co-locate the tmp file with the final destination so
            # `mv` is a same-filesystem rename (atomic on POSIX).
            tmp="${file}.tmp.$$"
            if ! cat > "$tmp"; then
                printf 'envoy: error: write failed: %s\n' "$tmp" >&2
                rm -f -- "$tmp" 2>/dev/null
                return 1
            fi
            if ! mv -f -- "$tmp" "$file"; then
                printf 'envoy: error: rename failed: %s -> %s\n' "$tmp" "$file" >&2
                rm -f -- "$tmp" 2>/dev/null
                return 1
            fi
            ;;
    esac
    return 0
}
