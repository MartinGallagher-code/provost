"""stunnel foreground log (`stunnel -f` / syslog-less): `YYYY.MM.DD HH:MM:SS LOGn[id]: message`."""
from lib import Doc, fake

TOOL = "stunnel"


def generate(rng):
    d = Doc()
    y, mo, dd = rng.randint(2020, 2026), rng.randint(1, 12), rng.randint(1, 28)
    t = rng.randint(0, 86000)
    ver = rng.choice(["5.56", "5.63", "5.69", "5.70", "5.71", "5.72"])
    plat = rng.choice(["x86_64-pc-linux-gnu", "aarch64-unknown-linux-gnu", "x86_64-alpine-linux-musl", "amd64-portbld-freebsd13.2"])
    svcs = rng.sample(["https", "imaps", "smtps", "redis-tls", "pop3s", "ldaps", "mysql-tls", "psql", "mqtt"], rng.randint(1, 3))

    def out(level, thread, msg):
        nonlocal t
        t += rng.choice([0, 0, 0, 1, 2, rng.randint(3, 300)])
        ts = f"{y}.{mo:02d}.{dd:02d} {t // 3600 % 24:02d}:{t // 60 % 60:02d}:{t % 60:02d}"
        d.line(f"{ts} LOG{level}[{thread}]: {msg}", "row", [ts, f"LOG{level}", thread, msg])

    if rng.random() < .8:
        out(5, "ui", f"stunnel {ver} on {plat} platform")
        out(5, "ui", "Compiled with OpenSSL " + rng.choice(["3.0.2 15 Mar 2022", "3.0.8 7 Feb 2023", "1.1.1w  11 Sep 2023"]))
        out(5, "ui", "Running  with OpenSSL " + rng.choice(["3.0.11 19 Sep 2023", "3.0.13 30 Jan 2024", "1.1.1w  11 Sep 2023"]))
        out(5, "ui", "Threading:PTHREAD Sockets:POLL,IPv6 TLS:ENGINE,FIPS,OCSP,PSK,SNI Auth:LIBWRAP")
        out(5, "ui", "Reading configuration from file /etc/stunnel/" + rng.choice(["stunnel.conf", "redis.conf", "tls.conf"]))
        out(5, "ui", "UTF-8 byte order mark not detected")
        if rng.random() < .5:
            out(5, "ui", "FIPS mode disabled")
        if rng.random() < .3:
            out(4, "ui", "Service [%s] needs authentication to prevent MITM attacks" % svcs[0])
        out(5, "ui", "Configuration successful")
        if rng.random() < .4:
            out(6, "ui", "Binding service [%s] to :::%s: Address already in use (98)" % (svcs[0], fake.port(rng)))
    conn = 0
    for _ in range(rng.randint(3, 18)):
        svc = rng.choice(svcs)
        th = str(conn)
        conn += 1
        peer = f"{fake.ip(rng)}:{rng.randint(1024, 65535)}"
        out(5, th, f"Service [{svc}] accepted connection from {peer}")
        r = rng.random()
        if r < .15:
            out(3, th, "SSL_accept: ssl/record/ssl3_record.c:354: error:0A00010B:SSL routines::wrong version number")
            out(5, th, "Connection reset: 0 byte(s) sent to TLS, 0 byte(s) sent to socket")
            continue
        if r < .25:
            out(3, th, f"s_connect: connect 127.0.0.1:{fake.port(rng)}: Connection refused (111)")
            out(3, th, "No more addresses to connect")
            out(5, th, "Connection reset: 0 byte(s) sent to TLS, 0 byte(s) sent to socket")
            continue
        backend = f"127.0.0.1:{rng.choice([80, 8080, 6379, 143, 25, 5432])}"
        if rng.random() < .5:
            out(6, th, f"s_connect: connecting {backend}")
        out(5, th, f"s_connect: connected {backend}")
        out(5, th, f"Service [{svc}] connected remote server from 127.0.0.1:{rng.randint(30000, 60999)}")
        if rng.random() < .3:
            out(6, th, "TLS accepted: new session negotiated")
            out(6, th, rng.choice(["TLSv1.3 ciphersuite: TLS_AES_256_GCM_SHA384 (256-bit encryption)",
                                   "TLSv1.2 ciphersuite: ECDHE-RSA-AES256-GCM-SHA384 (256-bit encryption)"]))
        if rng.random() < .1:
            out(4, th, f"Service [{svc}]: Connection reset by peer")
        out(5, th, f"Connection closed: {rng.randint(0, 9_000_000)} byte(s) sent to TLS, {rng.randint(0, 900_000)} byte(s) sent to socket")
    return d
