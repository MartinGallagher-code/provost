# A generic wrapper: provost-wrap

`provost-wrap` runs a command, passes its output through as it comes, files
that output with provost, and exits with the command's own status. Any
harness that can run a command can call it, and the harness sees exactly
what it saw before.

```console
$ provost-wrap --name stream test=stream sut=node7 -- ./stream
...the benchmark's output, as it prints...
$ echo $?            # the benchmark's own exit status
0
$ provost show stream
#  capture  test    sut    rc  n  Function  Rate
1  c0001    stream  node7  0   1  Copy      11234.5
```

- `KEY=VALUE` words before the command become columns on every row it files;
  `rc` (the command's exit status) is always added. A value may hold spaces.
- `--name NAME` names the dataset; without it, the command's base name does.
- stdout and stderr are filed as one stream, as `provost run` files them.
- A command that prints nothing files nothing. A command that is not found
  exits 127 and files nothing. If provost is not installed or refuses the
  output, the wrapper says so on stderr and still exits with the command's
  status.
- `PROVOST` names the provost to call (default: `provost` on `PATH`).

Why not `provost run`? It does the same capture, but its exit status is
provost's when the filing fails, and the command never runs if provost is
missing. A harness wants the test's verdict whatever happens to the record.

<!-- file: examples/provost-wrap -->
```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
#
# provost-wrap [--name NAME] [KEY=VALUE ...] [--] CMD [ARGS...]
#
# Run CMD with its output (stdout and stderr, as one stream) passed through,
# then file that output with provost, each KEY=VALUE as a column on every row
# it files, plus rc=<CMD's exit status>. Exits with CMD's own status, whatever
# happens to the filing: a harness sees the test's verdict, never provost's.
# The dataset is NAME, else CMD's base name. PROVOST names the provost to call.
set -u
usage () { echo "usage: provost-wrap [--name NAME] [KEY=VALUE ...] [--] CMD [ARGS...]" >&2; exit 2; }
name="" ctx=()
while (( $# )); do
    case "$1" in
        --name) (( $# >= 2 )) || usage; name="$2"; shift 2 ;;
        --) shift; break ;;
        [A-Za-z_]*=*) ctx+=("$1"); shift ;;
        *) break ;;
    esac
done
(( $# )) || usage
[[ -n "$name" ]] || name="$(basename -- "$1")"
command -v -- "$1" >/dev/null || { "$@"; exit; }   # not found: 127, nothing filed
tmp="$(mktemp -d)" || { "$@"; exit; }              # no scratch space: just run it
trap 'rm -rf -- "$tmp"' EXIT

"$@" 2>&1 | tee -- "$tmp/out"
rc=${PIPESTATUS[0]}
[[ -s "$tmp/out" ]] || exit "$rc"                  # no output: nothing to file

# The '#%' prologue: one KEY=VALUE a line, a value with a blank or a leading
# quote double-quoted (\ and " escaped), which is how provost reads it back.
for kv in ${ctx[@]+"${ctx[@]}"} "rc=$rc"; do
    k="${kv%%=*}" v="${kv#*=}"
    if [[ "$v" == *[[:blank:]]* || "$v" == '"'* ]]; then
        v="${v//\\/\\\\}"; v="\"${v//\"/\\\"}\""
    fi
    printf '#%% %s=%s\n' "$k" "$v"
done > "$tmp/in"
cat -- "$tmp/out" >> "$tmp/in"
"${PROVOST:-provost}" --sync -q --context-columns --name "$name" "$tmp/in" \
    || echo "provost-wrap: could not file the output of $1 (its status, $rc, is kept)" >&2
exit "$rc"
```

## A plain shell harness

Run every script in a directory, file each one's output with its name, the
host and the run as columns, and fail if any test failed:

<!-- file: examples/run-suite.sh -->
```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
#
# A plain shell harness: run every test script in a directory through
# provost-wrap, each one's output filed with its name, the host and the run as
# columns, and exit non-zero if any test failed.
#   run-suite.sh TESTDIR
set -u
here="$(cd "$(dirname -- "$0")" && pwd)"
run="$(date -u +%Y%m%dT%H%M%SZ)"
failed=0
for t in "$1"/*.sh; do
    name="$(basename -- "$t" .sh)"
    "$here/provost-wrap" --name "suite.$name" \
        test="$name" host="$(uname -n)" run.id="$run" -- bash "$t" \
        || { echo "FAIL $name" >&2; failed=$((failed + 1)); }
done
echo "$failed test(s) failed"
(( failed == 0 ))
```

```console
$ ./run-suite.sh tests/
$ provost ls
DATASET          ROWS
suite.bw            4
suite.latency      12
```

Any other harness works the same way: put `provost-wrap KEY=VALUE ... --` in
front of the command it runs.
