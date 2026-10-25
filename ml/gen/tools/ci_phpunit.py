"""`phpunit` run: version banner, Runtime/Configuration key/values, rows of
progress dots ending `  63 / 120 ( 52%)`, a Time/Memory line, failure details,
and the OK (...) or `Tests: N, Assertions: N, Failures: N.` summary."""
from lib import Doc, fake

TOOL = "phpunit"

CLASSES = ["UserTest", "OrderServiceTest", "CartTest", "InvoiceRepositoryTest", "AuthControllerTest",
           "MoneyTest", "SlugifierTest", "RouterTest", "MailerTest", "CsvImporterTest", "TokenTest"]
METHODS = ["testCreate", "testItCalculatesTotals", "testRejectsInvalidEmail", "testFindByStatus",
           "testRedirectsGuests", "testRoundsHalfUp", "testHandlesUnicode", "testMatchesRoute",
           "testSendsWelcomeMail", "testSkipsHeaderRow", "testExpiresAfterOneHour"]
MESSAGES = ["Failed asserting that false is true.",
            "Failed asserting that two strings are identical.",
            "Failed asserting that 3 matches expected 2.",
            "Failed asserting that null is not null.",
            "Failed asserting that an array has the key 'id'."]


def generate(rng):
    d = Doc()
    major = rng.choice([9, 10, 10, 11])
    ver = f"{major}.{rng.randint(0, 6)}.{rng.randint(0, 25)}"
    d.skip(f"PHPUnit {ver} by Sebastian Bergmann and contributors.")
    d.blank()
    pairs = [("Runtime", f"PHP {rng.choice(['8.1', '8.2', '8.3'])}.{rng.randint(0, 28)}"
              + (" with Xdebug 3.3.1" if rng.random() < .2 else ""))]
    if rng.random() < .85:
        pairs.append(("Configuration", rng.choice(["/app/phpunit.xml", "/var/www/html/phpunit.xml.dist",
                                                   "/home/runner/work/shop/shop/phpunit.xml"])))
    if major >= 10 and rng.random() < .4:
        pairs.append(("Random Seed", str(rng.randint(1600000000, 1800000000))))
    d.kvs(pairs)
    d.blank()

    total = rng.randint(5, 400)
    marks = []
    fails, errs, skips, risky = [], 0, 0, 0
    for i in range(total):
        r = rng.random()
        if r < .02:
            marks.append("F")
            fails.append(i)
        elif r < .03:
            marks.append("E")
            errs += 1
        elif r < .06:
            marks.append("S")
            skips += 1
        elif r < .07:
            marks.append("R")
            risky += 1
        else:
            marks.append(".")
    per = 63
    w = len(str(total))
    for start in range(0, total, per):
        chunk = "".join(marks[start:start + per])
        done = min(start + per, total)
        p = f"({100 * done // total:3d}%)"
        cnt = f"{str(done).rjust(w)} / {total}"
        text = chunk.ljust(per) + " " + cnt + " " + p
        d.line(text, "row", [cnt, p])
    d.blank()
    t = (f"00:{rng.randint(0, 59):02d}.{rng.randint(0, 999):03d}" if major >= 10
         else f"{rng.uniform(0.05, 90):.2f} seconds" if rng.random() < .5 else f"00:{rng.randint(0, 59):02d}.{rng.randint(0, 999):03d}")
    mem = f"{rng.choice([6, 8, 10, 12, 16, 18, 24, 32, 48, 64, 128])}.00 MB"
    d.line(f"Time: {t}, Memory: {mem}", "row", ["Time", t, "Memory", mem])
    d.blank()

    nf = len(fails) + errs
    if errs:
        d.skip(f"There {'was' if errs == 1 else 'were'} {errs} error{'s' if errs > 1 else ''}:")
        d.blank()
        for k in range(errs):
            cls, m = rng.choice(CLASSES), rng.choice(METHODS)
            name = f"Tests\\{rng.choice(['Unit', 'Feature', 'Integration'])}\\{cls}::{m}"
            d.section(f"{k + 1}) {name}", name)
            d.skip(rng.choice(["Error: Call to undefined method App\\Models\\User::fullName()",
                               "TypeError: App\\Money::add(): Argument #1 ($other) must be of type App\\Money, int given",
                               "PDOException: SQLSTATE[HY000] [2002] Connection refused"]))
            d.blank()
            d.skip(f"/app/tests/{cls}.php:{rng.randint(10, 400)}")
            d.blank()
        if fails:
            d.skip("--")
            d.blank()
    if fails:
        d.skip(f"There {'was' if len(fails) == 1 else 'were'} {len(fails)} failure{'s' if len(fails) > 1 else ''}:")
        d.blank()
        for k in range(len(fails)):
            cls, m = rng.choice(CLASSES), rng.choice(METHODS)
            name = f"Tests\\{rng.choice(['Unit', 'Feature'])}\\{cls}::{m}"
            if rng.random() < .3:
                name += f" with data set #{rng.randint(0, 9)}"
            d.section(f"{k + 1}) {name}", name)
            d.skip(rng.choice(MESSAGES))
            d.blank()
            d.skip(f"/app/tests/{rng.choice(['Unit', 'Feature'])}/{cls}.php:{rng.randint(10, 400)}")
            d.blank()

    ran = total
    asserts = ran * rng.randint(1, 6) + rng.randint(0, 9)
    if nf:
        d.skip("FAILURES!" if fails else "ERRORS!")
        parts = [("Tests", str(ran)), ("Assertions", str(asserts))]
        if errs:
            parts.append(("Errors", str(errs)))
        if fails:
            parts.append(("Failures", str(len(fails))))
        if skips:
            parts.append(("Skipped", str(skips)))
        if risky:
            parts.append(("Risky", str(risky)))
        text = ", ".join(f"{k}: {v}" for k, v in parts) + "."
        d.line(text, "row", [x for kv in parts for x in kv])
    elif skips or risky:
        d.skip("OK, but incomplete, skipped, or risky tests!" if major < 10 else "OK, but some tests have issues!")
        parts = [("Tests", str(ran)), ("Assertions", str(asserts))]
        if skips:
            parts.append(("Skipped", str(skips)))
        if risky:
            parts.append(("Risky", str(risky)))
        d.line(", ".join(f"{k}: {v}" for k, v in parts) + ".", "row", [x for kv in parts for x in kv])
    else:
        a, b = f"{ran} test{'s' if ran > 1 else ''}", f"{asserts} assertions"
        d.line(f"OK ({a}, {b})", "row", ["OK", a, b])
    if rng.random() < .2:
        d.blank()
        d.skip(f"Generating code coverage report in Clover XML format ... done [{fake.flt(rng, 0.1, 9, 2)} sec]")
    return d
