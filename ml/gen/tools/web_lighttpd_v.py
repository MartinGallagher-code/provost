"""`lighttpd -V`: a version banner, optional Build-Date, then sections listing
compiled-in handlers and features as `\t+ name` / `\t- name` lines."""
from lib import Doc, fake

TOOL = "lighttpd-V"

EVENTS = ["select (generic)", "poll (Unix)", "epoll (Linux)", "/dev/poll (Solaris)", "eventports (Solaris)",
          "kqueue (FreeBSD)", "libev (generic)"]
NETWORK = ["linux-sendfile", "freebsd-sendfile", "darwin-sendfile", "solaris-sendfilev", "writev", "write", "mmap support"]
FEATURES = ["IPv6 support", "zlib support", "brotli support", "zstd support", "bzip2 support", "crypt support",
            "OpenSSL support", "mbedTLS support", "GnuTLS support", "WolfSSL support", "Nettle support", "NSS crypto support",
            "PCRE support", "PCRE2 support", "MySQL support", "PgSQL support", "DBI support", "Kerberos support",
            "LDAP support", "PAM support", "memcached support", "FAM support", "LUA support", "xml support",
            "SQLite support", "GDBM support", "libunwind support", "Maxmind GeoIP2 support", "xattr support",
            "extended attributes support"]


def generate(rng):
    d = Doc()
    ver = rng.choice(["1.4.55", "1.4.59", "1.4.63", "1.4.69", "1.4.71", "1.4.73", "1.4.76"])
    tag = rng.choice(["(ssl)", "(ssl)", "", "(rev: 1.4.73-7-gb9e4a2d0)"])
    d.skip(f"lighttpd/{ver} {tag} - a light and fast webserver".replace("  ", " "))
    old = rng.random() < .35
    if old:
        md = fake.date(rng, "syslog")
        d.kv("Build-Date", f"{md[:6]} {rng.randint(2019, 2025)} {md[7:]}")
    d.blank()
    linux = rng.random() < .8
    sections = [("Event Handlers:", EVENTS), ("Network handler:", NETWORK), ("Features:", FEATURES)]
    if old:
        sections.insert(2, ("Network handlers (beta):", ["linux-aio-sendfile", "posix-aio", "gthread-aio"]))
    for title, items in sections:
        d.section(title)
        d.blank()
        if title.startswith("Features") and rng.random() < .3:
            items = rng.sample(items, rng.randint(10, len(items)))
        for it in items:
            if title.startswith("Event"):
                on = it.startswith(("select", "poll")) or (linux and "Linux" in it) or (not linux and "FreeBSD" in it) \
                     or (rng.random() < .15 and "libev" in it)
            elif title.startswith("Network"):
                on = ("linux" in it and linux) or ("freebsd" in it and not linux) or it in ("writev", "write") \
                     or (it == "mmap support" and rng.random() < .7)
            else:
                on = rng.random() < .55
            flag = "+" if on else "-"
            d.line(f"\t{flag} {it}", "row", [flag, it])
        d.blank()
    return d
