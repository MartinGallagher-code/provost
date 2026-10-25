"""Ruby `bundler-audit check --update`: git/advisory-db update chatter, an
optional database stats block, then one `Key: value` block per advisory
(Name, Version, CVE, GHSA, Criticality, URL, Title, Solution) separated by
blank lines, ending with "Vulnerabilities found!" or "No vulnerabilities found"."""
from lib import Doc, fake

TOOL = "bundler-audit"

ADVISORIES = [
    ("actionpack", "Possible exposure of information vulnerability in Action Pack"),
    ("rack", "Denial of Service Vulnerability in Rack Multipart Parsing"),
    ("nokogiri", "Update packaged libxml2 to v2.10.4 to resolve multiple CVEs"),
    ("activerecord", "Possible RCE escalation bug with Serialized Columns in Active Record"),
    ("loofah", "Inefficient Regular Expression Complexity in Loofah"),
    ("rails-html-sanitizer", "Possible XSS vulnerability with certain configurations of rails-html-sanitizer"),
    ("puma", "HTTP Request Smuggling in puma"),
    ("devise", "Devise allows unauthorized access via confirmable"),
    ("sinatra", "sinatra does not validate expanded path matches"),
    ("globalid", "ReDoS based DoS vulnerability in GlobalID"),
    ("activesupport", "Possible XSS Vulnerability in Action View tag helpers"),
    ("tzinfo", "TZInfo relative path traversal vulnerability allows loading of arbitrary files"),
    ("websocket-extensions", "Regular Expression Denial of Service in websocket-extensions (RubyGem)"),
    ("rexml", "REXML round-trip instability"),
    ("net-imap", "net-imap rubygem vulnerable to possible DoS by memory exhaustion"),
]


def ver(rng):
    return f"{rng.randint(0, 7)}.{rng.randint(0, 20)}.{rng.randint(0, 12)}"


def generate(rng):
    d = Doc()
    picks = rng.sample(ADVISORIES, rng.randint(0, 5))
    if rng.random() < .7 or not picks:
        d.skip("Updating ruby-advisory-db ...")
        if rng.random() < .7:
            d.skip("From https://github.com/rubysec/ruby-advisory-db")
            d.skip(" * branch            master     -> FETCH_HEAD")
            d.skip(rng.choice(["Already up to date.", f"Updating {fake.hexid(rng, 7)}..{fake.hexid(rng, 7)}",
                               "Already up-to-date."]))
        d.skip("Updated ruby-advisory-db")
        if rng.random() < .6:
            d.section("ruby-advisory-db:")
            stamp = f"{rng.randint(2021, 2026)}-{rng.randint(1, 12):02d}-{rng.randint(1, 28):02d} " \
                    f"{rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d} " \
                    f"{rng.choice(['-0700', '+0000', '-0400', '+0200'])}"
            for k, v in (("advisories", f"{rng.randint(700, 1100)} advisories"), ("last updated", stamp),
                         ("commit", fake.hexid(rng, 40))):
                d.line(f"  {k}:\t{v}", "kv", [k, v])
    if rng.random() < .15:
        uri = f"git://github.com/{fake.word(rng)}/{fake.word(rng)}.git"
        d.line(f"Insecure Source URI found: {uri}", "kv", ["Insecure Source URI found", uri])
    if not picks:
        d.skip("No vulnerabilities found")
        return d
    for i, (gem, title) in enumerate(picks):
        if i:
            d.blank()
        v = ver(rng)
        a, b, c = (int(x) for x in v.split("."))
        pairs = [("Name", gem), ("Version", v)]
        r = rng.random()
        if r < .85:
            pairs.append(("CVE", f"CVE-{rng.randint(2015, 2026)}-{rng.randint(1000, 49999)}"))
        if r > .3:
            g = "-".join(fake.token(rng, 4) for _ in range(3))
            pairs.append(("GHSA", f"GHSA-{g}"))
        pairs.append(("Criticality", rng.choice(["Low", "Medium", "High", "Critical", "Unknown"])))
        pairs.append(("URL", rng.choice([
            f"https://groups.google.com/g/rubyonrails-security/c/{fake.token(rng, 11)}",
            f"https://github.com/advisories/GHSA-{fake.token(rng, 4)}-{fake.token(rng, 4)}-{fake.token(rng, 4)}",
            f"https://discuss.rubyonrails.org/t/cve-{rng.randint(2020, 2026)}-{rng.randint(1000, 49999)}/{rng.randint(10000, 90000)}"])))
        pairs.append(("Title", title))
        fixes = [f"'~> {a}.{b}.{c + 1}'", f"'>= {a + 1}.0.0'"] if rng.random() < .5 else [f"'>= {a}.{b + 1}.0'"]
        if rng.random() < .3:
            fixes = [f"'~> {a}.{b}.{c + 1}, >= {a}.{b}.{c + 1}.1'"] + fixes
        pairs.append(("Solution", rng.choice(["upgrade to " + ", ".join(fixes), "remove or disable this gem until a patch is available!"])))
        for k, val in pairs:
            d.kv(k, val)
    d.blank()
    d.skip("Vulnerabilities found!")
    return d
