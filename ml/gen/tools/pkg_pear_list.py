"""PHP `pear list` / `pear list -a` / `pecl list`: one block per channel,
an `Installed packages, channel X:` heading underlined with `=`, then a
Package/Version/State table (or `(no packages installed)`)."""
from lib import Doc

TOOL = "pear-list"

PEAR = ["Archive_Tar", "Console_Getopt", "PEAR", "Structures_Graph", "XML_Util", "Mail", "Mail_Mime",
        "Net_SMTP", "Net_Socket", "Auth_SASL", "HTTP_Request2", "Net_URL2", "Log", "DB", "MDB2",
        "Console_Table", "PHP_CodeSniffer", "Crypt_GPG", "Net_IDNA2", "Text_Diff", "Date", "Cache_Lite"]
PECL = ["xdebug", "redis", "imagick", "apcu", "memcached", "mongodb", "igbinary", "msgpack", "yaml",
        "swoole", "grpc", "protobuf", "pcov", "ast", "uuid", "mailparse", "ssh2", "event"]
STATES = ["stable", "stable", "stable", "stable", "beta", "alpha", "devel"]


def ver(rng, st):
    v = ".".join(str(rng.randint(0, 12)) for _ in range(3))
    if st == "beta":
        v += f"b{rng.randint(1, 4)}"
    elif st in ("alpha", "devel"):
        v += f"RC{rng.randint(1, 3)}" if rng.random() < .5 else f"a{rng.randint(1, 3)}"
    return v


def block(d, rng, channel, pool, empty=False):
    head = f"Installed packages, channel {channel}:"
    d.section(head, channel)
    d.skip("=" * len(head))
    if empty:
        d.skip("(no packages installed)")
        return
    rows = []
    for p in sorted(rng.sample(pool, rng.randint(1, min(len(pool), 12))), key=str.lower):
        st = rng.choice(STATES)
        rows.append([p, ver(rng, st), st])
    d.table(["Package", "Version", "State"], rows, gap=1)


def generate(rng):
    d = Doc()
    mode = rng.choice(["pear", "pecl", "all"])
    if mode == "pear":
        block(d, rng, "pear.php.net", PEAR)
    elif mode == "pecl":
        block(d, rng, "pecl.php.net", PECL, empty=rng.random() < .15)
    else:
        chans = [("__uri", [], True), ("doc.php.net", ["pman"], rng.random() < .6),
                 ("pear.php.net", PEAR, False), ("pecl.php.net", PECL, rng.random() < .3)]
        if rng.random() < .3:
            chans.insert(2, ("pear.phpunit.de", ["PHPUnit", "File_Iterator", "Text_Template", "PHP_Timer"],
                             rng.random() < .3))
        for i, (c, pool, empty) in enumerate(chans):
            if i:
                d.blank()
            block(d, rng, c, pool, empty or not pool)
    return d
