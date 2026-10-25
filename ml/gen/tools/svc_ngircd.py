"""`ngircd --configtest`: version/copyright banner, a prompt, then the
parsed configuration as `[SECTION]` headings over indented `Key = value`."""
from lib import Doc, fake

TOOL = "ngircd"


def yn(rng):
    return rng.choice(["yes", "no"])


def generate(rng):
    d = Doc()
    ver = rng.choice(["26.1", "26", "25", "27", "24"])
    feats = "+".join(rng.sample(["DEBUG", "IDENT", "IPv6", "IRCPLUS", "PAM", "SSL", "SYSLOG", "TCPWRAP", "ZLIB"],
                               rng.randint(3, 8)))
    d.skip(f"ngircd {ver}-{feats}-{rng.choice(['x86_64/pc/linux-gnu', 'aarch64/unknown/linux-gnu', 'amd64/unknown/freebsd13.2'])}")
    d.skip("Copyright (c)2001-2024 Alexander Barton (<alex@barton.de>) and Contributors.")
    d.kv("Homepage", "<http://ngircd.barton.de/>")
    d.blank()
    d.skip("This is free software; see the source for copying conditions. There is NO")
    d.skip("warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.")
    d.blank()
    conf = rng.choice(["/etc/ngircd/ngircd.conf", "/etc/ngircd.conf", "/usr/local/etc/ngircd.conf"])
    d.skip(f'Reading configuration from "{conf}" ...')
    if rng.random() < .3:
        d.skip(f'Reading configuration from "{conf[:-5]}.conf.d/local.conf" ...')
    d.skip("OK, press enter to see a dump of your server configuration ...")
    d.blank()
    net = rng.choice(["example.net", "irc.lan", "chat.example.org", "freenode-ish.local"])
    srv = f"irc.{net}" if not net.startswith(("irc", "chat")) else net
    sections = [
        ("GLOBAL", [("Name", srv), ("AdminInfo1", rng.choice(["Example Admin", "", "Debian User"])),
                    ("AdminInfo2", rng.choice(["Anywhere On Earth", "Berlin, Germany", ""])),
                    ("AdminEMail", f"{fake.user(rng)}@{net}"), ("HelpFile", "/usr/share/doc/ngircd/Commands.txt.gz"),
                    ("Info", rng.choice(["Server Info Text", "Our IRC server", ""])),
                    ("Listen", rng.choice(["0.0.0.0,::", "127.0.0.1", "0.0.0.0"])),
                    ("MotdFile", "/etc/ngircd/ngircd.motd"), ("MotdPhrase", ""),
                    ("Network", rng.choice(["", "ExampleNet"])), ("Password", ""),
                    ("PidFile", "/run/ngircd/ngircd.pid"),
                    ("Ports", rng.choice(["6667", "6667, 6668", "6667, 6668, 6669", "6697"])),
                    ("ServerGID", rng.choice(["irc", "65534"])), ("ServerUID", rng.choice(["irc", "65534"]))]),
        ("LIMITS", [("ConnectRetry", str(rng.choice([60, 30, 120]))), ("IdleTimeout", "0"),
                    ("MaxConnections", str(rng.choice([0, 500, 1000]))),
                    ("MaxConnectionsIP", str(rng.choice([5, 10, 0]))), ("MaxJoins", str(rng.choice([10, 20, 0]))),
                    ("MaxListSize", "100"), ("MaxNickLength", str(rng.choice([9, 15, 30]))),
                    ("MaxPenaltyTime", "-1"), ("PingTimeout", "120"), ("PongTimeout", "20")]),
        ("OPTIONS", [("AllowedChannelTypes", "#&+"), ("AllowRemoteOper", yn(rng)),
                     ("ChrootDir", ""), ("CloakHost", ""), ("CloakHostModeX", ""),
                     ("CloakHostSalt", fake.token(rng, 32)), ("CloakUserToNick", yn(rng)),
                     ("ConnectIPv4", "yes"), ("ConnectIPv6", yn(rng)), ("DefaultUserModes", ""),
                     ("DNS", yn(rng)), ("IncludeDir", "/etc/ngircd/conf.d"), ("MorePrivacy", yn(rng)),
                     ("NoticeBeforeRegistration", "no"), ("OperCanUseMode", yn(rng)),
                     ("OperChanPAutoOp", "yes"), ("OperServerMode", "no"), ("PAM", yn(rng)),
                     ("PAMIsOptional", "no"), ("RequireAuthPing", "no"), ("ScrubCTCP", "no"),
                     ("SyslogFacility", rng.choice(["local1", "daemon"])), ("WebircPassword", "")]),
        ("SSL", [("CertFile", f"/etc/ssl/certs/{srv}.pem"), ("CipherList", "HIGH:!aNULL:@STRENGTH:!SSLv3"),
                 ("DHFile", ""), ("KeyFile", f"/etc/ssl/private/{srv}.key"), ("KeyFilePassword", ""),
                 ("Ports", rng.choice(["6697", "6697, 9999", ""]))]),
    ]
    for _ in range(rng.randint(0, 2)):
        sections.append(("OPERATOR", [("Name", rng.choice(["TheOper", fake.user(rng), "admin"])),
                                      ("Password", "ThePwd" if rng.random() < .5 else "********"),
                                      ("Mask", rng.choice(["", f"*!*@{fake.ip(rng)}", "*!ident@somewhere.example.com"]))]))
    for _ in range(rng.randint(0, 2)):
        sections.append(("SERVER", [("Name", f"irc{rng.randint(2, 9)}.{net}"), ("Host", fake.host(rng)),
                                    ("Bind", ""), ("Port", "6667"), ("MyPassword", "MySecret"),
                                    ("PeerPassword", "PeerSecret"), ("Group", str(rng.randint(0, 3))),
                                    ("Passive", yn(rng)), ("SSLConnect", yn(rng)), ("ServiceMask", "")]))
    for _ in range(rng.randint(0, 3)):
        sections.append(("CHANNEL", [("Name", "#" + fake.word(rng)), ("Modes", rng.choice(["tnk", "tn", "+tnl", ""])),
                                     ("Key", rng.choice(["", "Secret"])), ("KeyFile", ""),
                                     ("MaxUsers", str(rng.choice([0, 23, 100]))),
                                     ("Topic", rng.choice(["Our ngircd testing channel", "", "Welcome!"]))]))
    for i, (name, pairs) in enumerate(sections):
        d.section(f"[{name}]")
        for k, v in pairs:
            text = f"  {k} = {v}"
            d.line(text if v else text.rstrip() + " ", "kv", [k, v or None])
        if i < len(sections) - 1:
            d.blank()
    return d
