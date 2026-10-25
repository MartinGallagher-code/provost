"""Apache Traffic Server `traffic_ctl metric match REGEX` (and `metric get`):
one `name value` pair per line, no header."""
from lib import Doc, fake

TOOL = "traffic_ctl-metric"

GROUPS = {
    "proxy.process.http.": ["completed_requests", "incoming_requests", "outgoing_requests", "incoming_responses",
                            "invalid_client_requests", "missing_host_hdr", "get_requests", "head_requests", "post_requests",
                            "put_requests", "delete_requests", "purge_requests", "options_requests", "push_requests",
                            "total_client_connections", "total_client_connections_ipv4", "total_client_connections_ipv6",
                            "total_server_connections", "current_client_connections", "current_active_client_connections",
                            "current_server_connections", "current_server_transactions", "200_responses", "304_responses",
                            "404_responses", "500_responses", "502_responses", "503_responses", "1xx_responses",
                            "2xx_responses", "3xx_responses", "4xx_responses", "5xx_responses", "user_agent_response_header_total_size",
                            "origin_server_response_document_total_size", "transaction_counts.hit_fresh",
                            "transaction_counts.miss_cold", "transaction_totaltime.hit_fresh", "transaction_totaltime.miss_cold",
                            "avg_transactions_per_client_connection", "background_fill_bytes_aborted"],
    "proxy.process.cache.": ["bytes_used", "bytes_total", "ram_cache.total_bytes", "ram_cache.bytes_used", "ram_cache.hits",
                             "ram_cache.misses", "lookup.active", "lookup.success", "lookup.failure", "read.active",
                             "read.success", "read.failure", "write.active", "write.success", "write.failure",
                             "direntries.total", "direntries.used", "percent_full", "volume_0.bytes_used",
                             "volume_1.bytes_used", "evacuate.success"],
    "proxy.process.ssl.": ["total_handshake_time", "total_success_handshake_count_in", "total_success_handshake_count_out",
                           "user_agent_session_hit", "user_agent_session_miss", "ssl_error_ssl", "ssl_error_syscall",
                           "ssl_sni_name_set_failure", "default_record_size_count", "total_tickets_created",
                           "ssl_session_cache_hit", "ssl_session_cache_miss", "early_data_received"],
    "proxy.process.net.": ["accepts_currently_open", "connections_currently_open", "default_inactivity_timeout_applied",
                           "read_bytes", "write_bytes", "calls_to_read", "calls_to_write", "max.active.connections_throttled_in"],
    "proxy.node.": ["cache_hit_ratio", "cache_hit_mem_ratio", "bandwidth_hit_ratio", "proxy_running", "restarts.proxy.start_time",
                    "user_agent_xacts_per_second", "client_throughput_out", "hostname", "version.manager.short"],
}


def _val(rng, name):
    if name.endswith("ratio") or "percent" in name:
        return f"{rng.uniform(0, 1):.6f}" if "ratio" in name else str(rng.randint(0, 100))
    if name.endswith("hostname"):
        return fake.host(rng)
    if name.endswith("short"):
        return rng.choice(["9.2.3", "9.2.5", "10.0.1"])
    if name.endswith("proxy_running"):
        return "1"
    if "per_second" in name or "throughput" in name or "avg_" in name:
        return f"{rng.uniform(0, 5000):.6f}"
    if "current" in name or "active" in name:
        return str(rng.randint(0, 900))
    return str(rng.choice([0, rng.randint(0, 9999), rng.randint(10_000, 9_999_999_999)]))


def generate(rng):
    d = Doc()
    prefixes = rng.sample(list(GROUPS), rng.randint(1, 2))
    names = []
    for p in prefixes:
        pool = GROUPS[p]
        picked = rng.sample(pool, rng.randint(min(3, len(pool)), min(len(pool), 25)))
        names += [p + n for n in (sorted(picked) if rng.random() < .6 else picked)]
    style = rng.random()
    for n in names:
        v = _val(rng, n)
        if style < .85:
            d.line(f"{n} {v}", "row", [n, v])
        else:
            d.line(f"{n.ljust(max(len(x) for x in names))}  {v}", "row", [n, v])
    if rng.random() < .1:
        d.skip("traffic_ctl: error: Error during ATS JSONRPC call: rpc error: missing metric")
    return d
