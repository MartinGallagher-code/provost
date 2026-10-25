"""`karma start --single-run`: log4js lines (`14 06 2024 10:22:01.123:INFO
[launcher]: ...`), per-browser `Executed N of M SUCCESS (x secs / y secs)`
progress lines, FAILED spec lines with indented stack traces and a TOTAL line."""
from lib import Doc, fake

TOOL = "karma"

SPECS = ["AppComponent should create the app", "AppComponent should render title",
         "AuthService should store the token", "CartComponent should add an item",
         "UserService #fetch returns the user", "DatePipe formats ISO dates",
         "HeaderComponent should toggle the menu", "LoginForm should disable submit when invalid",
         "ApiInterceptor adds the Authorization header", "OrderStore reducer handles LOAD_SUCCESS"]


def generate(rng):
    d = Doc()
    day, mon, yr = rng.randint(1, 28), rng.randint(1, 12), rng.randint(2021, 2025)
    clock = [rng.randint(0, 23), rng.randint(0, 59), rng.uniform(0, 50)]

    def stamp():
        clock[2] += rng.uniform(0.001, 2.5)
        if clock[2] >= 60:
            clock[2] -= 60
            clock[1] = (clock[1] + 1) % 60
        return f"{day:02d} {mon:02d} {yr} {clock[0]:02d}:{clock[1]:02d}:{clock[2]:06.3f}"

    def log(level, comp, msg):
        t = stamp()
        d.line(f"{t}:{level} [{comp}]: {msg}", "row", [t, level, comp, msg])

    browsers = []
    for _ in range(rng.choices([1, 2, 3], [6, 3, 1])[0]):
        b = rng.choice([(f"Chrome Headless {rng.randint(100, 126)}.0.{rng.randint(5000, 6500)}.{rng.randint(10, 200)} (Linux x86_64)", "ChromeHeadless"),
                        (f"Chrome {rng.randint(100, 126)}.0.0.0 (Mac OS 10.15.7)", "Chrome"),
                        (f"Firefox {rng.randint(100, 128)}.0 (Ubuntu 0.0.0)", rng.choice(["Firefox", "FirefoxHeadless"])),
                        (f"HeadlessChrome {rng.randint(100, 126)}.0.0.0 (Windows 10)", "ChromeHeadlessCI")])
        if b[0] not in [x[0] for x in browsers]:
            browsers.append(b)
    launchers = [x[1] for x in browsers]
    browsers = [x[0] for x in browsers]
    ver = f"6.{rng.randint(0, 4)}.{rng.randint(0, 4)}"
    if rng.random() < .3:
        log("WARN", "karma", "No captured browser, open http://localhost:9876/")
    log("INFO", "karma-server", f"Karma v{ver} server started at http://localhost:{rng.choice([9876, 9876, 9877])}/")
    log("INFO", "launcher", f"Launching browsers {', '.join(launchers)} with concurrency unlimited")
    for b in launchers:
        log("INFO", "launcher", f"Starting browser {b.replace('CI', '').replace('Headless', '')}")
    for b in browsers:
        log("INFO", b, f"Connected on socket {fake.token(rng, 20)} with id {rng.randint(10000000, 99999999)}")
    if rng.random() < .3:
        log("WARN", "web-server", f"404: /{rng.choice(['favicon.ico', 'assets/logo.svg', 'api/config'])}")

    total = rng.randint(4, 600)
    for b in browsers:
        done, failed, skipped = 0, 0, 0
        t_all = t_net = 0.0
        while done < total:
            done = min(total, done + rng.randint(1, max(1, total // 3)))
            if rng.random() < .08:
                failed += 1
                spec = rng.choice(SPECS)
                d.line(f"{b} {spec} FAILED", "row", [b, spec, "FAILED"])
                d.skip(f"\tError: Expected {rng.choice(['undefined', 'false', 0, 'null'])} to be truthy.")
                d.skip("\t    at <Jasmine>")
                d.skip(f"\t    at UserContext.apply (src/app/{rng.choice(['app', 'auth', 'cart'])}.component.spec.ts:{rng.randint(10, 90)}:{rng.randint(5, 40)})")
            if rng.random() < .05:
                skipped += rng.randint(1, 3)
            step = rng.uniform(0.001, 4)
            t_all += step
            t_net += step * rng.uniform(.6, .95)
            a = f"{t_all:.3f} secs" if t_all >= .001 else "0 secs"
            net = f"{t_net:.3f} secs" if done < total or rng.random() < .8 else "0 secs"
            tail = f"({a} / {net})"
            res = [f"({failed} FAILED)"] if failed else []
            if skipped:
                res.append(f"(skipped {skipped})")
            mark = "ERROR" if rng.random() < .01 else ("SUCCESS" if not failed else None)
            if mark:
                res.append(mark)
            prog = f"Executed {done} of {total}"
            d.line(f"{b}: {prog} {' '.join(res)} {tail}", "row", [b, prog] + res + [a, net])
    if len(browsers) > 1 or rng.random() < .6:
        fails = sum(1 for lab in d.labels if lab["cells"][-1:] == ["FAILED"])
        ok = total * len(browsers) - fails
        parts = ([f"{fails} FAILED"] if fails else []) + [f"{ok} SUCCESS"]
        d.line("TOTAL: " + ", ".join(parts), "row", ["TOTAL"] + parts)
    return d
