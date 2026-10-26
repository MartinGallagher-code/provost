"""EMQX MQTT broker `emqx ctl clients list | subscriptions list | listeners |
broker stats`: `Client(id, k=v, ...)` records, `id -> topic:t qos:1` lines,
listener blocks of padded `key : value`, and dotted counter names."""
from lib import Doc, fake

TOOL = "emqx-ctl"

TOPICS = ["sensors/+/temperature", "home/livingroom/light/set", "devices/{id}/telemetry", "$SYS/brokers/#",
          "factory/line3/plc/#", "zigbee2mqtt/bridge/state", "tele/tasmota_5F2A1B/SENSOR", "#",
          "$share/workers/jobs/+", "lorawan/eu868/gateway/up"]


def client_id(rng):
    return rng.choice([f"mqttx_{fake.hexid(rng, 8)}", f"tasmota_{fake.hexid(rng, 6).upper()}",
                       f"esp32-{fake.hexid(rng, 6)}", f"node-red-{rng.randint(1, 9)}", f"zigbee2mqtt_{fake.hexid(rng, 8)}",
                       f"{fake.word(rng)}-gw-{rng.randint(1, 40):02d}", f"paho{rng.randint(10 ** 9, 10 ** 10)}"])


def clients(d, rng):
    for _ in range(rng.randint(2, 8)):
        cid = client_id(rng)
        ts = rng.randint(1690000000000, 1790000000000)
        pairs = [("username", rng.choice(["undefined", fake.user(rng), "device", "admin"])),
                 ("peername", f"{fake.ip(rng)}:{rng.randint(1024, 65535)}"),
                 ("clean_start", rng.choice(["true", "false"])), ("keepalive", str(rng.choice([30, 60, 120, 15]))),
                 ("session_expiry_interval", str(rng.choice([0, 0, 7200, 4294967295]))),
                 ("subscriptions", str(rng.randint(0, 12))), ("inflight", str(rng.randint(0, 3))),
                 ("awaiting_rel", "0"), ("delivered_msgs", str(rng.randint(0, 99999))),
                 ("enqueued_msgs", str(rng.randint(0, 999))), ("dropped_msgs", str(rng.randint(0, 9))),
                 ("connected", rng.choice(["true", "true", "false"])), ("created_at", str(ts)),
                 ("connected_at", str(ts + rng.randint(0, 900)))]
        text = f"Client({cid}, " + ", ".join(f"{k}={v}" for k, v in pairs) + ")"
        cells = ["Client", cid] + [x for kv in pairs for x in kv]
        d.line(text, "row", cells)


def subscriptions(d, rng):
    for _ in range(rng.randint(1, 10)):
        cid = client_id(rng)
        for t in rng.sample(TOPICS, rng.randint(1, 3)):
            t = t.replace("{id}", cid)
            vals = [("topic", t), ("qos", str(rng.choice([0, 1, 1, 2]))), ("nl", "0"),
                    ("rh", str(rng.choice([0, 0, 1]))), ("rap", "0")]
            text = f"{cid} -> " + " ".join(f"{k}:{v}" for k, v in vals)
            d.line(text, "row", [cid] + [x for kv in vals for x in kv])


def listeners(d, rng):
    kinds = [("tcp:default", "0.0.0.0:1883"), ("ssl:default", "0.0.0.0:8883"), ("ws:default", "0.0.0.0:8083"),
             ("wss:default", "0.0.0.0:8084"), ("quic:default", ":14567"), ("tcp:internal", "127.0.0.1:11883")]
    for name, addr in [k for k in kinds if rng.random() < .7] or kinds[:1]:
        d.section(name, name)
        conn = rng.randint(0, 50000)
        pairs = [("listen_on", addr), ("acceptors", str(rng.choice([4, 16, 32]))),
                 ("proxy_protocol", rng.choice(["false", "true"])), ("running", rng.choice(["true", "true", "false"])),
                 ("current_conn", str(conn)), ("max_conns", rng.choice(["infinity", "512000", "1024000", "5000000"]))]
        if rng.random() < .3:
            pairs.insert(1, ("type", name.split(":")[0]))
        for k, v in pairs:
            d.line(f"  {k.ljust(15)} : {v}", "kv", [k, v])


def stats(d, rng):
    names = ["channels.count", "channels.max", "cluster_sessions.count", "cluster_sessions.max",
             "connections.count", "connections.max", "delayed.count", "delayed.max", "live_connections.count",
             "live_connections.max", "retained.count", "retained.max", "sessions.count", "sessions.max",
             "suboptions.count", "suboptions.max", "subscribers.count", "subscribers.max",
             "subscriptions.count", "subscriptions.max", "subscriptions.shared.count", "subscriptions.shared.max",
             "topics.count", "topics.max"]
    w = max(len(n) for n in names) + rng.choice([0, 6])
    cur = 0
    for nm in names:
        if nm.endswith(".count"):
            cur = rng.randint(0, 10 ** rng.randint(1, 6))
            v = cur
        else:
            v = cur + rng.randint(0, cur + 3)
        d.line(f"{nm.ljust(w)} : {v}", "kv", [nm, str(v)])


def generate(rng):
    d = Doc()
    rng.choice([clients, subscriptions, listeners, stats])(d, rng)
    return d
