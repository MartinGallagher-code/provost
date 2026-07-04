#!/bin/bash
################################################################################
## Strategy Tests: nginx-conf
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: nginx-conf"
echo "========================================"

test_nginx_conf_basic () {
    local output
    output=$(run_mfe -r -s nginx-conf "$SAMPLES_DIR/nginx-conf/basic.conf")
    assert_contains "$output" "worker_processes auto" "should extract worker_processes"
    assert_contains "$output" "server1.listen 80" "should extract server1 listen"
    assert_contains "$output" "server1.server_name example.com_www.example.com" "should extract server_name"
    assert_contains "$output" "server1.root /var/www/html" "should extract server1 root"
    assert_contains "$output" "server1.location2.proxy_pass http://127.0.0.1:8080" "should extract proxy_pass"
}

test_nginx_conf_multi_server () {
    local output
    output=$(run_mfe -r -s nginx-conf "$SAMPLES_DIR/nginx-conf/basic.conf")
    assert_contains "$output" "server2.listen 443_ssl" "should extract server2 listen"
    assert_contains "$output" "server2.server_name secure.example.com" "should extract server2 server_name"
    assert_contains "$output" "server2.ssl_certificate /etc/ssl/cert.pem" "should extract ssl_certificate"
}

test_nginx_conf_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s nginx-conf "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not apply to JSON"
}

test_nginx_conf_not_hcl () {
    local output
    output=$(run_mfe -d -s nginx-conf "$SAMPLES_DIR/hcl/basic.tf" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to HCL"
}

run_test "nginx-conf: basic extraction" test_nginx_conf_basic
run_test "nginx-conf: multi-server" test_nginx_conf_multi_server
run_test "nginx-conf: not detected for JSON" test_nginx_conf_not_json
run_test "nginx-conf: not detected for HCL" test_nginx_conf_not_hcl

print_summary
