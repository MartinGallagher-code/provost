"""`keydb-cli info [section]`: `# Section` headings, `field:value` lines, and
the Keyspace / Replication / Commandstats lines that pack several k=v pairs."""
from lib import Doc, fake

TOOL = "keydb-cli-info"


def _human(n):
    for u in ("B", "K", "M", "G"):
        if n < 1024:
            return f"{n:.2f}{u}" if u != "B" else f"{int(n)}B"
        n /= 1024
    return f"{n:.2f}T"


def _server(rng):
    up = rng.randint(30, 9000000)
    return [("redis_version", rng.choice(["6.3.4", "6.2.2", "255.255.255"])),
            ("redis_git_sha1", fake.hexid(rng, 8)), ("redis_git_dirty", "0"),
            ("redis_build_id", fake.hexid(rng, 16)), ("redis_mode", rng.choice(["standalone", "cluster"])),
            ("os", f"Linux {rng.choice(['5.15.0-88', '6.1.0-13', '5.10.0-26'])}-generic x86_64"),
            ("arch_bits", "64"), ("multiplexing_api", "epoll"), ("atomicvar_api", "atomic-builtin"),
            ("gcc_version", rng.choice(["9.4.0", "11.4.0", "12.2.0"])), ("process_id", str(rng.randint(1, 99999))),
            ("process_supervised", rng.choice(["no", "systemd"])), ("run_id", fake.hexid(rng, 40)),
            ("tcp_port", rng.choice(["6379", "6380", "7000"])), ("server_time_usec", str(rng.randint(10 ** 15, 2 * 10 ** 15))),
            ("uptime_in_seconds", str(up)), ("uptime_in_days", str(up // 86400)), ("hz", "10"),
            ("configured_hz", "10"), ("lru_clock", str(rng.randint(1, 16777215))),
            ("executable", rng.choice(["/usr/bin/keydb-server", "/opt/keydb/bin/keydb-server"])),
            ("config_file", rng.choice(["/etc/keydb/keydb.conf", ""])),
            ("availability_zone", ""), ("features", "cluster_mget")]


def _clients(rng):
    return [("connected_clients", str(rng.randint(1, 3000))), ("cluster_connections", "0"),
            ("maxclients", "10000"), ("client_recent_max_input_buffer", str(rng.randint(8, 50000))),
            ("client_recent_max_output_buffer", "0"), ("blocked_clients", str(rng.choice([0, 0, rng.randint(1, 20)]))),
            ("tracking_clients", "0"), ("clients_in_timeout_table", "0"),
            ("current_client_thread", str(rng.randint(0, 3))), ("thread_0_clients", str(rng.randint(0, 900))),
            ("thread_1_clients", str(rng.randint(0, 900)))]


def _memory(rng):
    used = rng.randint(800000, 30 * 1024 ** 3)
    peak = int(used * rng.uniform(1, 1.8))
    mx = rng.choice([0, 4 * 1024 ** 3, 16 * 1024 ** 3])
    return [("used_memory", str(used)), ("used_memory_human", _human(used)), ("used_memory_rss", str(int(used * 1.1))),
            ("used_memory_rss_human", _human(used * 1.1)), ("used_memory_peak", str(peak)),
            ("used_memory_peak_human", _human(peak)), ("used_memory_peak_perc", f"{100 * used / peak:.2f}%"),
            ("total_system_memory_human", _human(rng.choice([8, 16, 64, 128]) * 1024 ** 3)),
            ("maxmemory", str(mx)), ("maxmemory_human", _human(mx)),
            ("maxmemory_policy", rng.choice(["noeviction", "allkeys-lru", "volatile-lru", "allkeys-lfu"])),
            ("mem_fragmentation_ratio", f"{rng.uniform(.8, 3):.2f}"), ("mem_allocator", "jemalloc-5.2.1"),
            ("active_defrag_running", "0"), ("lazyfree_pending_objects", "0")]


def _persistence(rng):
    return [("loading", "0"), ("rdb_changes_since_last_save", str(rng.randint(0, 900000))),
            ("rdb_bgsave_in_progress", "0"), ("rdb_last_save_time", str(rng.randint(1690000000, 1790000000))),
            ("rdb_last_bgsave_status", rng.choice(["ok", "ok", "err"])), ("rdb_last_bgsave_time_sec", str(rng.randint(-1, 90))),
            ("aof_enabled", rng.choice(["0", "1"])), ("aof_rewrite_in_progress", "0"),
            ("aof_last_bgrewrite_status", "ok"), ("aof_last_write_status", "ok")]


def _stats(rng):
    return [("total_connections_received", str(rng.randint(1, 10 ** 7))), ("total_commands_processed", str(rng.randint(1, 10 ** 9))),
            ("instantaneous_ops_per_sec", str(rng.randint(0, 90000))), ("total_net_input_bytes", str(rng.randint(1, 10 ** 11))),
            ("instantaneous_input_kbps", f"{rng.uniform(0, 9000):.2f}"), ("rejected_connections", "0"),
            ("expired_keys", str(rng.randint(0, 10 ** 6))), ("evicted_keys", str(rng.choice([0, rng.randint(0, 10 ** 5)]))),
            ("keyspace_hits", str(rng.randint(0, 10 ** 8))), ("keyspace_misses", str(rng.randint(0, 10 ** 7))),
            ("pubsub_channels", str(rng.randint(0, 40))), ("latest_fork_usec", str(rng.randint(0, 90000)))]


def generate(rng):
    d = Doc()
    builders = [("Server", _server), ("Clients", _clients), ("Memory", _memory), ("Persistence", _persistence),
                ("Stats", _stats), ("Replication", None), ("CPU", None), ("Commandstats", None), ("Keyspace", None)]
    if rng.random() < .35:
        builders = rng.sample(builders, 1)
    else:
        builders = [b for b in builders if b[0] != "Commandstats" or rng.random() < .4]
    first = True
    for name, fn in builders:
        if not first:
            d.blank()
        first = False
        d.section(f"# {name}", name)
        if fn:
            pairs = fn(rng)
            if rng.random() < .3:
                pairs = pairs[:rng.randint(3, len(pairs))]
            for k, v in pairs:
                if v:
                    d.kv(k, v, sep=":")
                else:
                    d.line(k + ":", "kv", [k])
        elif name == "Replication":
            master = rng.random() < .6
            d.kv("role", "master" if master else "slave", sep=":")
            if master:
                n = rng.randint(0, 3)
                d.kv("connected_slaves", str(n), sep=":")
                for i in range(n):
                    ip, port, off = fake.ip(rng), rng.choice(["6379", "6380"]), str(rng.randint(10 ** 6, 10 ** 10))
                    st, lag = rng.choice(["online", "online", "wait_bgsave", "send_bulk"]), str(rng.randint(0, 3))
                    d.line(f"slave{i}:ip={ip},port={port},state={st},offset={off},lag={lag}", "row",
                           [f"slave{i}", "ip", ip, "port", port, "state", st, "offset", off, "lag", lag])
            else:
                d.kv("master_host", fake.ip(rng), sep=":")
                d.kv("master_port", "6379", sep=":")
                d.kv("master_link_status", rng.choice(["up", "up", "down"]), sep=":")
                d.kv("master_last_io_seconds_ago", str(rng.randint(0, 10)), sep=":")
                d.kv("master_sync_in_progress", "0", sep=":")
                d.kv("slave_repl_offset", str(rng.randint(10 ** 6, 10 ** 10)), sep=":")
                d.kv("slave_read_only", "1", sep=":")
                d.kv("connected_slaves", "0", sep=":")
            d.kv("master_replid", fake.hexid(rng, 40), sep=":")
            d.kv("master_repl_offset", str(rng.randint(10 ** 6, 10 ** 10)), sep=":")
            d.kv("repl_backlog_active", rng.choice(["0", "1"]), sep=":")
            d.kv("repl_backlog_size", "1048576", sep=":")
        elif name == "CPU":
            for k in ["used_cpu_sys", "used_cpu_user", "used_cpu_sys_children", "used_cpu_user_children",
                      "server_threads", "long_lock_waits"]:
                v = str(rng.choice([2, 4])) if k == "server_threads" else str(rng.randint(0, 40)) if k == "long_lock_waits" \
                    else f"{rng.uniform(0, 90000):.6f}"
                d.kv(k, v, sep=":")
        elif name == "Commandstats":
            for cmd in rng.sample(["get", "set", "del", "info", "ping", "hget", "hset", "expire", "keys", "scan",
                                   "client", "config", "mget", "lpush", "rpop", "publish", "zadd"], rng.randint(2, 9)):
                calls = rng.randint(1, 10 ** 8)
                usec = calls * rng.randint(1, 30)
                vals = [str(calls), str(usec), f"{usec / calls:.2f}", "0", str(rng.choice([0, 0, rng.randint(1, 99)]))]
                keys = ["calls", "usec", "usec_per_call", "rejected_calls", "failed_calls"]
                cells = [f"cmdstat_{cmd}"]
                for k, v in zip(keys, vals):
                    cells += [k, v]
                d.line(f"cmdstat_{cmd}:" + ",".join(f"{k}={v}" for k, v in zip(keys, vals)), "row", cells)
        else:
            for db in sorted(rng.sample(range(16), rng.randint(0 if len(builders) > 1 else 1, 4))):
                keys = str(rng.randint(1, 10 ** 7))
                exp = str(rng.randint(0, int(keys)))
                ttl = str(rng.choice([0, rng.randint(1000, 10 ** 9)]))
                cached = str(rng.randint(0, int(keys)))
                pairs = [("keys", keys), ("expires", exp), ("avg_ttl", ttl)] + ([("cached_keys", cached)] if rng.random() < .5 else [])
                cells = [f"db{db}"]
                for k, v in pairs:
                    cells += [k, v]
                d.line(f"db{db}:" + ",".join(f"{k}={v}" for k, v in pairs), "row", cells)
    return d
