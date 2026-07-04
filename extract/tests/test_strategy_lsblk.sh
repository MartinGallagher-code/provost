#!/bin/bash
################################################################################
## Strategy Tests: lsblk
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: lsblk"
echo "========================================"

test_detect () {
    local output
    output=$(run_mfe -d -s lsblk "$SAMPLES_DIR/lsblk/basic.txt" 2>&1)
    assert_contains "$output" "detected as applicable" "lsblk should detect lsblk output"
}

# v2.0: emitted as indexed row groups (entry<N>.<field>) so capture's tidy melt
# renders one row per device instead of a single wide dev1_*/dev2_* record.
test_extract () {
    local output
    output=$(run_mfe -r -s lsblk "$SAMPLES_DIR/lsblk/basic.txt")
    assert_contains "$output" "entry1.name sda" "should extract first device name"
    assert_contains "$output" "entry1.type disk" "should extract first device type"
    assert_contains "$output" "entry1.size 238.5G" "should extract first device size"
    assert_contains "$output" "entry2.name sda1" "should extract partition name"
    assert_contains "$output" "entry2.type part" "should extract partition type"
    assert_contains "$output" "entry2.mount /boot/efi" "should extract partition mount"
    assert_contains "$output" "total_entries 4" "four devices"
}

test_field_selection () {
    local output
    output=$(run_mfe -r -s lsblk "$SAMPLES_DIR/lsblk/basic.txt")
    assert_contains "$output" "entry4.name sda3" "should extract swap partition name"
    assert_contains "$output" "entry4.mount [SWAP]" "should extract swap mount"
    assert_not_contains "$output" "MAJ:MIN" "should not contain raw header text"
}

# lsblk with MOUNTPOINTS prints a device's extra mountpoints on their own
# indented continuation lines (sometimes prefixed with the '|' tree bar). Those
# must attach to the current device, not become phantom devices.
test_extra_mountpoints () {
    local tmp
    tmp=$(mktemp)
    printf 'NAME    MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS\n' > "$tmp"
    printf 'loop4     7:4    0   32G  0 loop /var/lib/docker\n' >> "$tmp"
    printf '                                 /home/vscode/.minikube\n' >> "$tmp"
    printf 'sda       8:0    0   30G  0 disk\n' >> "$tmp"
    printf '\xe2\x94\x9c\xe2\x94\x80sda1    8:1    0 29.9G  0 part /workspaces/shared\n' >> "$tmp"
    printf '\xe2\x94\x82                                /vscode\n' >> "$tmp"
    local output
    output=$(run_mfe -r -s lsblk "$tmp")
    rm -f "$tmp"
    # loop4 keeps both of its mountpoints
    assert_contains "$output" "entry1.mount /var/lib/docker,/home/vscode/.minikube" "loop4 keeps both mountpoints"
    # sda1's tree-barred continuation mountpoint attaches to sda1, not a new device
    assert_contains "$output" "entry3.mount /workspaces/shared,/vscode" "tree-barred continuation attaches to sda1"
    # exactly three devices (loop4, sda, sda1) — no phantom 'vscode' device
    assert_contains "$output" "total_entries 3" "no phantom device from continuation lines"
    assert_not_contains "$output" "name vscode" "continuation path must not become a device name"
}

run_test "lsblk: detection" test_detect
run_test "lsblk: extraction" test_extract
run_test "lsblk: field selection" test_field_selection
run_test "lsblk: extra mountpoints attach to device" test_extra_mountpoints

print_summary
