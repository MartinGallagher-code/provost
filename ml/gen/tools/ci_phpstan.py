"""`phpstan analyse` (table error format): a config note, progress-bar lines,
one Symfony-style boxed table per file (`Line` + the file path as header,
long messages wrapped onto continuation lines, tip/identifier lines), then the
`[ERROR] Found N errors` or `[OK] No errors` block."""
import textwrap

from lib import Doc

TOOL = "phpstan"

FILES = ["src/Controller/UserController.php", "src/Entity/Order.php", "src/Service/Mailer.php",
         "src/Repository/InvoiceRepository.php", "app/Http/Middleware/Authenticate.php",
         "app/Models/User.php", "src/Command/ImportCsvCommand.php", "lib/Cache/RedisPool.php",
         "src/EventSubscriber/LocaleSubscriber.php", "tests/Unit/MoneyTest.php", "src/Kernel.php"]
MSGS = [
    ("Method {c}::index() has no return type specified.", "missingType.return"),
    ("Access to an undefined property {c}::$nmae.", "property.notFound"),
    ("Parameter #1 $id of method {c}::find() expects int, string given.", "argument.type"),
    ("Call to an undefined method {c}::fullName().", "method.notFound"),
    ("Variable $result might not be defined.", "variable.undefined"),
    ("Property {c}::$items type has no value type specified in iterable type array.", "missingType.iterableValue"),
    ("Cannot call method format() on DateTimeImmutable|null.", "method.nonObject"),
    ("Strict comparison using === between int and null will always evaluate to false.", "identical.alwaysFalse"),
    ("Unreachable statement - code above always terminates.", "deadCode.unreachable"),
    ("Dead catch - Doctrine\\ORM\\NoResultException is never thrown in the try block.", "catch.neverThrown"),
    ("Method {c}::handle() should return int but returns int|false.", "return.type"),
]


def boxed(d, header, rows, width):
    w0 = max(len(header[0]), max(len(r[0]) for r in rows))
    w1 = width
    rule = " " + "-" * (w0 + 2) + " " + "-" * (w1 + 2) + " "
    fmt = lambda a, b: " " + " " + a.ljust(w0) + "   " + b.ljust(w1) + "  "
    d.skip(rule)
    d.line(fmt(*header), "header", list(header))
    d.skip(rule)
    for line, parts in rows:
        first, rest = parts[0], parts[1:]
        d.line(fmt(line, first), "row", [line, first])
        for p in rest:
            d.line(fmt("", p), "cont", [p])
    d.skip(rule)
    d.blank()


def generate(rng):
    d = Doc()
    lvl = rng.random() < .4
    if rng.random() < .8:
        cfg = rng.choice(["/app/phpstan.neon", "/app/phpstan.neon.dist", "/home/runner/work/api/api/phpstan.dist.neon"])
        d.skip(f"Note: Using configuration file {cfg}.")
    nfiles = rng.randint(5, 2000)
    steps = sorted({nfiles} | {rng.randint(0, nfiles) for _ in range(rng.choice([0, 0, 1, 2, 3]))})
    bar = 28
    for s in steps:
        p = 100 * s // nfiles
        fill = bar * s // nfiles
        cnt = f"{str(s).rjust(len(str(nfiles)))}/{nfiles}"
        pct = f"{p:3d}%"
        d.line(f" {cnt} [{'▓' * fill}{'░' * (bar - fill)}] {pct}", "row", [cnt, pct.strip()])
    d.blank()
    nerr = 0
    clean = rng.random() < .2
    if not clean:
        width = rng.randint(50, 90)
        for f in rng.sample(FILES, rng.randint(1, 5)):
            rows = []
            for ln in sorted(rng.sample(range(1, 400), rng.randint(1, 6))):
                msg, ident = rng.choice(MSGS)
                cls = "App\\" + f.split("/")[-1][:-4] if "{c}" in msg else ""
                text = msg.replace("{c}", cls)
                parts = textwrap.wrap(text, width)
                if rng.random() < .5:
                    parts.append(f"🪪  {ident}")
                if rng.random() < .15:
                    parts.append("💡 Learn more: https://phpstan.org/blog/solving-phpstan-access-to-undefined-property")
                rows.append((str(ln), parts))
                nerr += 1
            boxed(d, ("Line", f), rows, max(width, len(f)) + 1)
    if clean:
        d.line(" [OK] No errors".ljust(rng.choice([15, 80])), "row", ["[OK]", "No errors"])
    else:
        msg = f"Found {nerr} error{'s' if nerr > 1 else ''}"
        d.line(f" [ERROR] {msg}".ljust(80), "row", ["[ERROR]", msg])
    d.blank()
    if rng.random() < .25:
        d.skip("💡 Tip of the Day:")
        d.skip("PHPStan is performing only the most basic checks.")
        d.skip("You can pass a higher rule level through the --level option")
        d.skip("(the default and current level is 0) to analyse code more thoroughly.")
        d.blank()
    return d
