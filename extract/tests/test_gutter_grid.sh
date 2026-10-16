#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Gutter grid: cells of a whitespace-aligned table by character OFFSET
## (lib/_helpers.sh _FR_AWK_GRID / _fr_gutter_grid), and its users —
## aligned-columns, fixed-width, embedded-table — on tables whose cells hold
## spaces, are empty, or sit under banners and above footers. The tables are
## written for these tests (Windows `query user` / `tasklist` /
## Get-Process / Get-PSDrive, `yarn outdated`, `net share`, …), not corpus
## or benchmark inputs.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../lib/_helpers.sh"

echo ""
echo "========================================"
echo "Gutter grid (offset-assigned columns)"
echo "========================================"

AC="$SAMPLES_DIR/aligned-columns"
FW="$SAMPLES_DIR/fixed-width"

_grid () { printf '%s\n' "$@" | _fr_gutter_grid 1 0; }

################################################################################
## The engine itself
################################################################################

# Multi-word cells, a two-word header with one space, and EMPTY cells that
# stay empty — nothing shifts left.
test_grid_multiword_and_empty () {
    local out; out="$(_fr_gutter_grid 1 0 < "$AC/offset-cells.txt")"
    assert_contains "$out" "entry1.LOGON_TIME 10/14/2026 9:02 AM" "a date + time + AM cell is one cell"
    assert_contains "$out" "entry1.IDLE_TIME none" "a one-space two-word header is ONE label"
    assert_contains "$out" "entry3.ID 3" "row with an empty SESSIONNAME keeps its ID"
    assert_not_contains "$out" "entry3.SESSIONNAME" "the empty cell stays empty"
    assert_contains "$out" "entry4.IDLE_TIME 2+03:11" "a value wider than its label lands in its column"
}

# A number split from its unit by a one-space gutter under a one-space
# label (`RAW USE` over `180 GiB`) is one value; a data-empty first word of
# a label (`Used` of `Used (GB)`) joins the rest of it.
test_grid_unit_and_label_words () {
    local out
    out="$(_grid 'ID  SIZE     RAW USE  STATUS' ' 0  1.0 TiB  180 GiB  up' ' 1  1.0 TiB  175 GiB  up')"
    assert_contains "$out" "entry1.RAW_USE 180 GiB" "number + unit is one cell"
    out="$(_grid 'Name   Used (GB)  Provider' 'C         112.45  FileSystem' 'Env               Environment')"
    assert_contains "$out" "entry1.Used_(GB) 112.45" "data-empty label word joins its neighbour"
    assert_not_contains "$out" "entry2.Used" "empty cell under a two-word label"
    assert_contains "$out" "entry2.Provider Environment" "later column unshifted"
}

# Labels that repeat get a numbered twin instead of colliding in the melt.
test_grid_duplicate_names () {
    local out
    out="$(_grid 'NODE      TYPE        ID     TYPE      KIND' \
                 '10.5.0.2  LinkStatus  eth0   ether' \
                 '10.5.0.2  LinkStatus  cni0   ether     bridge')"
    assert_contains "$out" "entry1.TYPE LinkStatus" "first TYPE"
    assert_contains "$out" "entry1.TYPE_2 ether" "second TYPE kept apart"
    assert_contains "$out" "entry2.KIND bridge" "sparse last column"
}

# Row labels under no header label are a column of their own; a lone
# marker (`>`) set off by spaces is a marker column.
test_grid_row_labels_and_markers () {
    local out
    out="$(_grid '              total        used        free' 'Mem:           7982        2341        3120' 'Swap:          2047         128        1919')"
    assert_contains "$out" "entry1.A Mem:" "label-less first column is its own column"
    assert_contains "$out" "entry1.total 7982" "values under their own labels"
    out="$(_grid 'Num     Name                 Tags' '0    >  2026-07-08_01-00-01  O' '1       2026-07-09_01-00-01  D')"
    assert_contains "$out" "entry1.B >" "isolated marker is a column"
    assert_contains "$out" "entry1.Name 2026-07-08_01-00-01" "marker not glued to the name"
}

# When the first row leaves a column empty that a later row fills, cells go
# out column by column so the melt keeps the header's column order.
test_grid_column_order () {
    local out first
    out="$(_grid 'Name   Used (GB)  Provider' 'Env               Environment' 'C         112.45  FileSystem')"
    first="$(printf '%s\n' "$out" | grep -m1 -E '\.(Used_\(GB\)|Provider) ')"
    assert_contains "$first" "Used_(GB)" "Used (GB) is named before Provider"
}

# A group row (nh=2) prefixes the names of the columns it sits over.
test_grid_group_row () {
    local out
    out="$(printf '%s\n' '  %   cumulative   self              self     total' \
        ' time   seconds   seconds    calls  ms/call  ms/call  name' \
        ' 33.34      0.02     0.02     7208     0.00     0.00  open' \
        ' 16.67      0.06     0.01                             mcount' | _fr_gutter_grid 2 0)"
    assert_contains "$out" "entry1.self_seconds 0.02" "group word prefixes its column"
    assert_contains "$out" "entry1.total_ms/call 0.00" "second ms/call is total_"
    assert_contains "$out" "entry2.name mcount" "empty cells stay empty"
    assert_not_contains "$out" "entry2.calls" "no shifted value"
}

# It withdraws (prints nothing) when the offsets cannot be trusted.
test_grid_withdraws () {
    local out
    out="$(_grid 'date time acct host' '03/01/2024 08:12:33 root 10.0.0.5' '03/02/2024 14:22:17 bob tty1')"
    assert_eq "" "$out" "unpadded single-spaced table: tokens already agree"
    out="$(_grid 'Nestopia UE           Nintendo - NES' 'Snes9x                Nintendo - SNES' 'mGBA                  Nintendo - Game Boy Advance')"
    assert_eq "" "$out" "a header repeated as cells is the first record"
    out="$(printf '%s\n' $'Linux 6.5.0 (host) \t07/11/2026 \t_x86_64_' '10:00  CPU  %usr' '10:01  all  4.2' | _fr_gutter_grid 1 0)"
    assert_eq "" "$out" "a TAB header over space-aligned data"
    out="$(_grid '      eth0                wlan0' ' KB/s in  KB/s out   KB/s in  KB/s out' '   12.45     3.21       0.98      0.12' '   88.30    15.67       1.20      0.34')"
    assert_eq "" "$out" "a second header line is no data row"
    out="$(printf '%s\n' 'a  b' $'x\001y  z' 'p  q' | _fr_gutter_grid 1 0)"
    assert_eq "" "$out" "a placeholder byte in the input"
}

# mawk and the default awk give the same bytes (CI runs mawk and gawk).
test_grid_mawk_same_bytes () {
    command -v mawk >/dev/null 2>&1 || return 0
    local a b
    a="$(LC_ALL=C mawk -v nh=1 -v rl=1 -v pfx=row "$_FR_AWK_GRID" < "$FW/right-aligned.txt")"
    b="$(_fr_gutter_grid 1 1 row < "$FW/right-aligned.txt")"
    assert_eq "$a" "$b" "mawk output identical"
    a="$(LC_ALL=C mawk -v nh=1 -v rl=0 -v pfx=entry "$_FR_AWK_GRID" < "$AC/offset-cells.txt")"
    b="$(_fr_gutter_grid 1 0 < "$AC/offset-cells.txt")"
    assert_eq "$a" "$b" "mawk output identical (no rule)"
}

################################################################################
## Through the strategies (auto-detection, as provost calls the engine)
################################################################################

test_ac_banner_lines_and_footer () {
    local out; out="$(run_extract -r -f plain --max-strategies 1 "$AC/banner-lines.txt" 2>/dev/null)"
    assert_contains "$out" "entry1.Package eslint" "banner lines above the header are not rows"
    assert_contains "$out" "entry1.Package_Type devDependencies" "one-space two-word header"
    assert_contains "$out" "entry3.URL https://www.typescriptlang.org/" "last row intact"
    assert_not_contains "$out" "Done in" "yarn's footer is no row"
    assert_not_contains "$out" "legend" "legend lines are banner"
}

test_ac_title_over_indented_rows () {
    local out; out="$(run_extract -r -f plain --max-strategies 1 "$AC/title-indented.txt" 2>/dev/null)"
    assert_contains "$out" "entry1.A curl" "first row is data"
    assert_not_contains "$out" "following" "the prose title is no header"
}

test_ac_w3c_fields_directive () {
    local out; out="$(run_extract -r -f plain --max-strategies 1 "$AC/w3c-fields.txt" 2>/dev/null)"
    assert_contains "$out" "entry1.date 2026-10-14" "#Fields: names the columns"
    assert_contains "$out" "entry1.path SEND" "every field under its own name"
    assert_not_contains "$out" "Fields:" "the directive word is no column"
}

test_ac_net_share () {
    local out; out="$(run_extract -r -f plain --max-strategies 1 "$AC/footer-empty-cells.txt" 2>/dev/null)"
    assert_contains "$out" "entry2.Share_name IPC\$" "all-text table with a two-word header"
    assert_contains "$out" "entry2.Remark Remote IPC" "empty Resource does not shift Remark"
    assert_not_contains "$out" "entry2.Resource" "empty cell stays empty"
    assert_not_contains "$out" "completed successfully" "footer dropped"
}

test_ac_indented_table_under_title () {
    local out; out="$(run_extract -r -f plain --max-strategies 1 "$AC/indented-banner.txt" 2>/dev/null)"
    assert_contains "$out" "entry5.Local_Address 0.0.0.0:5353" "table under a title, not a hierarchy"
    assert_contains "$out" "entry5.PID 2512" "UDP row: PID in PID"
    assert_not_contains "$out" "entry5.State" "UDP row: State empty"
}

test_ac_tab_banner () {
    local out; out="$(run_extract -r -s aligned-columns "$AC/tab-banner.txt" 2>/dev/null)"
    assert_contains "$out" "pgpgin/s 4.12" "the field row is the header"
    assert_not_contains "$out" "Linux" "the sysstat banner is no header"
}

test_ac_space_in_first_column () {
    local out; out="$(run_extract -r -f plain --max-strategies 1 "$AC/space-in-cell.txt" 2>/dev/null)"
    assert_contains "$out" "entry5.Filesystem map auto_home" "a first cell holding a space"
    assert_contains "$out" "entry5.Size 0Bi" "the rest of that row unshifted"
    assert_contains "$out" "entry4.Mounted_on /Volumes/Backup Drive" "mount point with a space"
}

# A `Label: value` line cut from above the table is kept as a field (a
# constant column after the melt).
test_ac_preamble_fields () {
    local tmp out; tmp="$(mktemp)"
    printf '  pool: tank\n state: DEGRADED\n  scan: resilver in progress\n        NAME        STATE     READ WRITE\n        raidz2-0    DEGRADED     0     0\n        sda         ONLINE       0     0\n        sdb         RESILVER     0     0\n' > "$tmp"
    out="$(run_extract -r -f plain --max-strategies 1 "$tmp" 2>/dev/null)"; rm -f "$tmp"
    assert_contains "$out" "entry2.NAME sda" "the table"
    assert_contains "$out" "state DEGRADED" "preamble field kept"
    assert_contains "$out" "scan resilver in progress" "preamble value keeps its spaces"
}

# A later line is no header when the lines above it already have the
# table's shape: a command list whose first descriptions carry function
# words (`Compile the current workspace`) must not lose its first rows to a
# `clean  Remove generated artifacts` "header".
test_ac_no_header_inside_command_list () {
    local out; out="$(run_extract -r -f plain -s aligned-columns "$AC/command-list.txt" 2>/dev/null)"
    assert_not_contains "$out" "Remove_generated_artifacts" "a row is not taken as the header"
    out="$(run_extract -r -f plain --max-strategies 1 "$AC/command-list.txt" 2>/dev/null)"
    assert_contains "$out" "build" "first command kept in the default run"
}

# ...nor when its words have the rows' shape: a +/- feature grid under
# version lines is no table with `+archive` as a column name.
test_ac_no_header_from_feature_grid () {
    local out; out="$(run_extract -r -f plain -s aligned-columns "$AC/feature-grid.txt" 2>/dev/null)"
    assert_not_contains "$out" "+archive " "a feature word is not a column name"
    out="$(run_extract -r -f plain --max-strategies 1 "$AC/feature-grid.txt" 2>/dev/null)"
    assert_contains "$out" "Frob 3.2.1" "version line kept"
    assert_contains "$out" "Packaged by" "banner lines kept"
}

# A number + one short word is one value only when 2+ rows show the word
# constant: in a ONE-row table `14  main` / `5433 down` are two columns.
test_grid_unit_join_needs_two_rows () {
    local out; out="$(_fr_gutter_grid 1 0 < "$AC/one-row-units.txt")"
    assert_contains "$out" "entry1.Ver 14" "number column kept apart"
    assert_contains "$out" "entry1.Cluster main" "word column kept apart"
    assert_contains "$out" "entry1.Status down" "second pair kept apart"
    out="$(_grid 'Rev Region  Size Health Owner   Mount point' '3   west    250  ok     deploy  /data/vol3')"
    assert_contains "$out" "entry1.Size 250" "one-row number"
    assert_contains "$out" "entry1.Health ok" "one-row short word"
    out="$(_grid 'ID  SIZE     RAW USE  STATUS' ' 0  1.0 TiB  180 GiB  up')"
    assert_contains "$out" "entry1.RAW_USE 180 GiB" "a real unit word still joins in one row"
    out="$(_grid 'ID  NAME    SIZE SOL  STATE  Mount point' ' 1  alpha   412 SOL  ok     /data/a' ' 2  beta    977 SOL  ok     /data/b')"
    assert_contains "$out" "entry2.SIZE_SOL 977 SOL" "a constant word over 2+ rows still joins"
}

test_fw_equals_rule () {
    local out; out="$(run_extract -r -f plain --max-strategies 1 "$FW/equals-rule.txt" 2>/dev/null)"
    assert_contains "$out" "row1.Image_Name System Idle Process" "multi-word cell under an == run"
    assert_contains "$out" "row1.Mem_Usage 8 K" "right-aligned value with a unit"
    assert_contains "$out" "row5.Session_Name Console" "two-word label"
}

test_fw_right_aligned_wider_than_rule () {
    local out; out="$(run_extract -r -s fixed-width "$FW/right-aligned.txt" 2>/dev/null)"
    assert_contains "$out" "row5.PM(K) 102400" "a value wider than its dash run is not cut"
    assert_contains "$out" "row4.Id 5512" "empty CPU(s) does not shift Id"
    assert_not_contains "$out" "row4.CPU(s)" "the empty cell stays empty"
}

test_fw_dates_and_empty_length () {
    local out; out="$(run_extract -r -s fixed-width "$FW/dates-empties.txt" 2>/dev/null)"
    assert_contains "$out" "row1.LastWriteTime 10/14/2026 9:03 AM" "a date that starts left of its label"
    assert_contains "$out" "row1.Mode d-----" "Mode alone"
    assert_not_contains "$out" "row1.Length" "a directory has no Length"
    assert_contains "$out" "row4.Name Project Plan.docx" "name with a space"
}

test_fw_sql_footer () {
    local out; out="$(run_extract -r -s fixed-width "$FW/sql-footer.txt" 2>/dev/null)"
    assert_contains "$out" "row3.LOC SAN FRANCISCO" "multi-word middle cell"
    assert_not_contains "$out" "row4.BUDGET" "NULL cell stays empty"
    assert_not_contains "$out" "selected" "footer is no row"
}

# An indented `=` underline over a multi-section report is not one table.
test_fw_declines_multi_section () {
    local tmp out; tmp="$(mktemp)"
    printf '# Instances ###\n  Port  Data Directory    Nice\n  ===== ================ ====\n   3306 /var/lib/mysql   0\n# Processlist ###\n  Command   COUNT(*)\n  --------- --------\n  Query            6\n' > "$tmp"
    out="$(run_extract -d -s fixed-width "$tmp" 2>&1)"; rm -f "$tmp"
    assert_contains "$out" "not applicable" "two underlined tables: fixed-width declines"
}

# A bare pipe table drawn with `---|---` rules (istanbul/nyc/c8 text
# report): the default run parses it, as --multi always did.
test_pipe_table_dash_rules_default_path () {
    local out; out="$(run_extract -r -f plain --max-strategies 1 "$SAMPLES_DIR/pipe-table/dash-rules.txt" 2>/dev/null)"
    assert_contains "$out" "entry3.File parser.js" "rows parsed in the default run"
    assert_contains "$out" "entry3.Uncovered_Line_#s 14-17" "last column named"
    assert_not_contains "$out" "-----" "rules are no rows"
}

test_tsv_headerless_repeats () {
    local out; out="$(run_extract -r -s tsv "$SAMPLES_DIR/tsv/headerless-repeats.tsv" 2>/dev/null)"
    assert_contains "$out" "entry1.B off" "row 1 is data (its value recurs below)"
    assert_contains "$out" "entry1.A autocd" "autocd is a value"
    assert_not_contains "$out" ".autocd" "autocd is not a column name"
}

test_embedded_table_group_row () {
    local out; out="$(run_extract -r -s embedded-table "$SAMPLES_DIR/embedded-table/group-row.txt" 2>/dev/null)"
    assert_contains "$out" "entry1.cumulative_seconds 0.02" "group row prefixes"
    assert_contains "$out" "entry1.self_ms/call 0.00" "first ms/call"
    assert_contains "$out" "entry1.total_ms/call 0.00" "second ms/call kept apart"
    assert_contains "$out" "entry5.name mcount" "row with empty cells"
}

################################################################################
## 2026-10-16: UTF-8 offsets, soft and data gutters, footers, banners
################################################################################

# Offsets count characters: an accented or CJK cell no longer withdraws the
# grid. Wide characters count two columns first (what a terminal shows:
# lsblk / column), then one (tools that pad by character count: Go
# tabwriter, Python ljust).
test_grid_utf8_widths () {
    local out
    out="$(_fr_gutter_grid 1 0 < "$AC/utf8-widths.txt")"
    assert_contains "$out" "entry3.LABEL データ" "a CJK cell in its column (display width)"
    assert_contains "$out" "entry3.SIZE 900G" "the next column unshifted"
    assert_contains "$out" "entry1.SIZE 931.5G" "an empty LABEL stays empty"
    assert_not_contains "$out" "entry1.LABEL" "no value shifted into LABEL"
    out="$(_fr_gutter_grid 1 0 < "$AC/utf8-runes.txt")"
    assert_contains "$out" "entry2.APP 订单服务" "a CJK cell (character count)"
    assert_contains "$out" "entry2.RESTARTS 2 (4h ago)" "a multi-word cell after it"
    out="$(_grid 'UID USER    GECOS          SHELL' '  0 root    root           /bin/bash' '1000 josé    José Álvarez   /bin/zsh' '1001 chloé   Chloé Lefèvre  /bin/sh')"
    assert_contains "$out" "entry2.GECOS José Álvarez" "accented multi-word cell"
    assert_contains "$out" "entry3.SHELL /bin/sh" "columns after accents unshifted"
    out="$(_grid 'NAME   STATUS     NOTE' 'build  ✓ passed   cached' 'test   ✗ failed   …' 'lint   ✓ passed   -')"
    assert_contains "$out" "entry2.STATUS ✗ failed" "check marks are narrow"
    assert_contains "$out" "entry2.NOTE …" "an ellipsis cell"
    local a b
    command -v mawk >/dev/null 2>&1 || return 0
    a="$(LC_ALL=C mawk -v nh=1 -v rl=0 -v pfx=entry "$_FR_AWK_GRID" < "$AC/utf8-runes.txt")"
    b="$(_fr_gutter_grid 1 0 < "$AC/utf8-runes.txt")"
    assert_eq "$a" "$b" "mawk output identical (UTF-8)"
}

# One over-long cell crossing a gutter in a small table (`Full Repair
# Needed` one character past its label) no longer withdraws the grid.
test_grid_one_crossing_row () {
    local out
    out="$(_grid 'Drive Status                 Free      Size' 'C     OK                   120 GB    476 GB' 'D     OK                   841 GB    931 GB' 'E     Unknown                 0 B       0 B' 'F     Full Repair Needed    58 GB     60 GB' 'G     OK                     1 GB      2 GB')"
    assert_contains "$out" "entry4.Status Full Repair Needed" "the crossing cell stays whole"
    assert_contains "$out" "entry4.Free 58 GB" "the value after it in its column"
    assert_contains "$out" "entry1.Size 476 GB" "right-aligned last column"
}

# A header printed in a format of its own (`method  crc     date  time`
# over `defla 1c2b3a4d Oct  1 08:01`): the data's own gutters cut the
# columns, each going to the label it overlaps.
test_grid_data_gutters () {
    local out; out="$(_fr_gutter_grid 1 0 < "$AC/data-gutters.txt")"
    assert_contains "$out" "entry2.date Oct 1" "a date with a padded day is one cell"
    assert_contains "$out" "entry2.time 08:01" "time after it"
    assert_contains "$out" "entry2.compressed 8120" "numbers unshifted"
    assert_contains "$out" "entry4.compressed 19310" "totals row: empty leading cells"
}

# The last single-spaced label group may take a run-on totals row.
test_grid_last_group_run_on () {
    local out
    out="$(_grid 'method      compressed  uncompr. ratio uncompressed_name' 'LZO1X-1          4021      12813  31.4% services' 'LZO1X-1          1102       3144  35.1% protocols' '                 5123      15957  32.1% [total of 2 files]')"
    assert_contains "$out" "entry1.ratio 31.4%" "ratio apart from the name"
    assert_contains "$out" "entry3.uncompressed_name [total of 2 files]" "run-on cell in the last column"
}

# Headerless: a soft gutter (a TAB-pushed over-long option) and empty
# trailing / sparse leading cells.
test_ac_option_states_headerless () {
    local out; out="$(run_extract -r -f plain --max-strategies 1 "$AC/option-states.txt" 2>/dev/null)"
    assert_contains "$out" "entry1.A -faggressive-loop-optimizations" "the first option is a row"
    assert_contains "$out" "entry1.B [enabled]" "its state"
    assert_contains "$out" "entry11.B dynamic" "a row after the overflow"
    assert_not_contains "$out" "entry8.B" "an option with no state: empty last cell"
    assert_not_contains "$out" "following" "the title is no row"
    out="$(printf '%s\n' '  1           0 RESUME   0' '  2           2 LOAD     0 (x)' '              4 STORE    1 (y)' '              6 RETURN' '  3           8 LOAD     2 (z)' '             10 RETURN' | _fr_gutter_grid 0 0)"
    assert_contains "$out" "entry3.B 4" "sparse leading column: the row keeps its cells"
    assert_not_contains "$out" "entry3.A" "the empty leading cell stays empty"
    assert_contains "$out" "entry4.C RETURN" "an empty trailing cell"
}

# An all-caps row that opens with a value, as the rows below do, is data.
test_ac_caps_row_with_values_is_data () {
    local tmp out; tmp="$(mktemp)"
    printf '%s\n' '0000 PUSH     1' '0002 PUSH     2' '0004 ADD' '0005 STORE    x' '0007 RETURN' > "$tmp"
    out="$(run_extract -r -s aligned-columns -f plain "$tmp" 2>/dev/null)"; rm -f "$tmp"
    assert_not_contains "$out" ".PUSH " "PUSH is no column name"
    assert_contains "$out" "0000" "the first instruction is a row"
}

# Footers end a fixed-width / pipe table, and the client prompt after one
# goes too.
test_footers_everywhere () {
    local out
    out="$(run_extract -r -f plain --max-strategies 1 "$FW/footer-prompt.txt" 2>/dev/null)"
    assert_contains "$out" "row1.DEPT_NAME Comptabilité" "accented cell"
    assert_contains "$out" "row3.CITY São Paulo" "multi-word accented cell"
    assert_not_contains "$out" "selected" "footer dropped"
    assert_not_contains "$out" "SQL>" "prompt after the footer dropped"
    out="$(run_extract -r -f plain --max-strategies 1 "$SAMPLES_DIR/pipe-table/footer.txt" 2>/dev/null)"
    assert_contains "$out" "entry3.city Rome" "bare pipe table with a footer"
    assert_not_contains "$out" "rows" "footer is no row"
    _FR_FC=('a  b' '1  2' '' '(1 row affected)' '' '1>'); _fr_footer_cut
    assert_eq "2" "$_FR_FC_N" "footer cut keeps the rows"
    _FR_FC=('a  b' '1  2' '3 >'); _fr_footer_cut
    assert_eq "3" "$_FR_FC_N" "no footer: nothing cut"
}

# A PowerShell header wrapped onto two lines.
test_fw_wrapped_header () {
    local out; out="$(run_extract -r -f plain --max-strategies 1 "$FW/wrapped-header.txt" 2>/dev/null)"
    assert_contains "$out" "row1.Partition_Style GPT" "the wrapped label joined"
    assert_contains "$out" "row1.Friendly_Name Samsung SSD 970 EVO Plus 1TB" "first-line labels kept"
    assert_contains "$out" "row2.Total_Size 3.64 TB" "right-aligned value"
}

# Banners: a commented header with a dotted rule (perf report), print-report
# page headers repeated at page breaks, ASA carriage control, and a
# right-aligned table under `Label: value` / prose lines.
test_ac_banners_2026_10_16 () {
    local out
    out="$(run_extract -r -f plain --max-strategies 1 "$AC/comment-header.txt" 2>/dev/null)"
    assert_contains "$out" "entry1.Shared_Object libpython3.12.so" "two-word commented label"
    assert_contains "$out" "entry1.Symbol [.] _PyEval_EvalFrameDefault" "last column whole"
    assert_not_contains "$out" "Samples:" "a Label: comment is no header"
    out="$(run_extract -r -f plain --max-strategies 1 "$AC/page-headers.txt" 2>/dev/null)"
    assert_contains "$out" "entry1.Customer C10045" "page header is no column name"
    assert_contains "$out" "entry5.Name Wide World Importers" "rows of page 2 kept"
    assert_not_contains "$out" "5770SS1" "page header lines dropped"
    assert_not_contains "$out" "L I S T I N G" "end-of-listing line dropped"
    out="$(run_extract -r -f plain --max-strategies 1 "$AC/asa-report.txt" 2>/dev/null)"
    assert_contains "$out" "entry1.ITEM-NO A-10021" "carriage control cut from the header"
    assert_contains "$out" "entry4.DESCRIPTION GASKET SET" "page 2 rows kept"
    assert_not_contains "$out" "RUN DATE" "page header dropped"
    local tmp; tmp="$(mktemp)"
    printf '%s\n' 'Process: dotnet (pid 4412)' 'Duration: 10.02s, 4,812 samples' 'Showing top 3 methods' \
        '   Exclusive  Exclusive%   Inclusive  Method' '     1,201ms      24.96%     3,410ms  MyApp.Parser.ParseRow' \
        '       812ms      16.87%       812ms  System.String.Split' '        97ms       2.02%     4,790ms  MyApp.Program.Main' > "$tmp"
    out="$(run_extract -r -f plain -s aligned-columns "$tmp" 2>/dev/null)"; rm -f "$tmp"
    assert_contains "$out" "entry1.Exclusive 1,201ms" "right-aligned rows under a later header"
    assert_contains "$out" "entry3.Method MyApp.Program.Main" "last row"
}

run_test "grid: multi-word and empty cells" test_grid_multiword_and_empty
run_test "grid: unit join and label words" test_grid_unit_and_label_words
run_test "grid: duplicate names" test_grid_duplicate_names
run_test "grid: row labels and markers" test_grid_row_labels_and_markers
run_test "grid: column order with empty first row" test_grid_column_order
run_test "grid: group row prefixes" test_grid_group_row
run_test "grid: withdraws on untrustworthy offsets" test_grid_withdraws
run_test "grid: mawk gives the same bytes" test_grid_mawk_same_bytes
run_test "aligned-columns: banner lines + footer" test_ac_banner_lines_and_footer
run_test "aligned-columns: prose title over indented rows" test_ac_title_over_indented_rows
run_test "aligned-columns: #Fields: directive" test_ac_w3c_fields_directive
run_test "aligned-columns: net share (all-text, empty cell, footer)" test_ac_net_share
run_test "aligned-columns: indented table under a title" test_ac_indented_table_under_title
run_test "aligned-columns: TAB banner" test_ac_tab_banner
run_test "aligned-columns: space inside the first column" test_ac_space_in_first_column
run_test "aligned-columns: preamble fields kept" test_ac_preamble_fields
run_test "aligned-columns: no header inside a command list" test_ac_no_header_inside_command_list
run_test "aligned-columns: no header from a +/- feature grid" test_ac_no_header_from_feature_grid
run_test "grid: number + word join needs 2 rows" test_grid_unit_join_needs_two_rows
run_test "fixed-width: == rule" test_fw_equals_rule
run_test "fixed-width: right-aligned values wider than the rule" test_fw_right_aligned_wider_than_rule
run_test "fixed-width: dates and empty cells" test_fw_dates_and_empty_length
run_test "fixed-width: SQL footer" test_fw_sql_footer
run_test "fixed-width: declines a multi-section report" test_fw_declines_multi_section
run_test "pipe-table: ---|--- rules in the default run" test_pipe_table_dash_rules_default_path
run_test "tsv: headerless when row-1 values recur" test_tsv_headerless_repeats
run_test "embedded-table: group row + repeated labels" test_embedded_table_group_row

run_test "grid: UTF-8 widths (display, then characters)" test_grid_utf8_widths
run_test "grid: one crossing row in a small table" test_grid_one_crossing_row
run_test "grid: data gutters under a loose header" test_grid_data_gutters
run_test "grid: run-on totals row in the last group" test_grid_last_group_run_on
run_test "aligned-columns: headerless option listing" test_ac_option_states_headerless
run_test "aligned-columns: all-caps row with values is data" test_ac_caps_row_with_values_is_data
run_test "footers: fixed-width prompt, bare pipe table" test_footers_everywhere
run_test "fixed-width: header wrapped onto two lines" test_fw_wrapped_header
run_test "aligned-columns: banners (comment header, page headers, ASA)" test_ac_banners_2026_10_16

print_summary
