"""`fastlane <platform> <lane>`: `[HH:MM:SS]: message` log lines with
`--- Step: name ---` banners, a terminal-table `Summary for <action>` box of
key | value rows, and the closing `fastlane summary` table (Step | Action |
Time (in s)) with its title row, then the finished/error line."""
from lib import Doc, fake

TOOL = "fastlane"

ACTIONS = ["default_platform", "setup_ci", "match", "cocoapods", "increment_build_number",
           "increment_version_number", "get_version_number", "gym", "build_app", "run_tests", "scan",
           "pilot", "upload_to_testflight", "deliver", "slack", "gradle", "upload_to_play_store",
           "supply", "badge", "commit_version_bump", "push_to_git_remote", "add_git_tag", "ensure_git_status_clean"]
MSGS = ["Cruising back to lane '{lane}' 🚘", "Successfully loaded '{dir}/fastlane/Appfile' 📄",
        "Driving the lane '{lane}' 🚀", "$ xcodebuild -showBuildSettings -workspace {app}.xcworkspace -scheme {app}",
        "Successfully exported and signed the ipa file:", "Generated plist file with the following values:",
        "Uploading binary to App Store Connect", "Successfully uploaded the new binary to App Store Connect",
        "▸ Compiling {app}ViewController.swift", "▸ Linking {app}", "Successfully finished processing the build",
        "Fetching certificates from git repo", "🔓  Successfully decrypted certificates repo",
        "Installed Provisioning Profile"]


def boxed_kv(d, title, pairs):
    kw = max(len(k) for k, _ in pairs)
    vw = max(max(len(v) for _, v in pairs), len(title) - kw - 3)
    inner = kw + vw + 5
    d.skip("+" + "-" * (inner) + "+")
    d.section("|" + title.center(inner) + "|", title)
    d.skip("+" + "-" * (kw + 2) + "+" + "-" * (vw + 2) + "+")
    for k, v in pairs:
        d.line(f"| {k.ljust(kw)} | {v.ljust(vw)} |", "kv", [k, v])
    d.skip("+" + "-" * (kw + 2) + "+" + "-" * (vw + 2) + "+")


def generate(rng):
    d = Doc()
    plat = rng.choice(["ios", "android", "ios", "mac"])
    lane = f"{plat} {rng.choice(['beta', 'release', 'test', 'build', 'nightly', 'screenshots'])}"
    app = rng.choice(["Weather", "Acme", "Pulse", "Tally", "Fieldbook", "Runner"])
    wdir = rng.choice(["/Users/runner/work/app/app", "/builds/mobile/app", "/Users/ci/agent/_work/3/s"])
    h, m, s = rng.randint(0, 23), rng.randint(0, 59), rng.randint(0, 59)

    def clock(adv=None):
        nonlocal h, m, s
        s += rng.randint(0, 3) if adv is None else adv
        m, s = m + s // 60, s % 60
        h, m = (h + m // 60) % 24, m % 60
        return f"{h:02d}:{m:02d}:{s:02d}"

    def log(msg):
        t = clock()
        d.line(f"[{t}]: {msg}", "row", [t, msg])

    def rule(n):
        d.skip(f"[{clock(0)}]: " + "-" * n)

    if rng.random() < .4:
        d.skip("[✔] 🚀 ")
    if rng.random() < .3:
        log("fastlane detected a Gemfile in the current directory")
        log("However, it seems like you didn't use `bundle exec`")
        log("To launch fastlane faster, please use")
    android = {"gradle", "upload_to_play_store", "supply"}
    apple = {"match", "cocoapods", "gym", "build_app", "run_tests", "scan", "pilot", "upload_to_testflight", "deliver"}
    pool = [a for a in ACTIONS if a not in (apple if plat == "android" else android)]
    msgs = [x for x in MSGS if "Driving" not in x and (plat != "android" or not any(
        w in x for w in ("xcode", "App Store", "▸", "Provisioning", "certificates", "ipa", "plist")))]
    msgs += ["$ ./gradlew bundleRelease -p .", "BUILD SUCCESSFUL in 1m 12s", "Uploading AAB to Google Play"] if plat == "android" else []
    steps = rng.sample(pool, rng.randint(2, min(9, len(pool))))
    if "default_platform" in steps:
        steps.remove("default_platform")
    steps = (["default_platform"] if rng.random() < .8 else []) + steps
    timings = []
    failed_at = len(steps) - 1 if rng.random() < .2 else None
    for i, act in enumerate(steps):
        txt = f"--- Step: {act} ---"
        rule(len(txt))
        t = clock()
        d.line(f"[{t}]: {txt}", "row", [t, f"Step: {act}"])
        rule(len(txt))
        if i == 0 and act == "default_platform":
            log(MSGS[2].format(lane=lane))
        for _ in range(rng.randint(0, 4)):
            log(rng.choice(msgs).format(lane=lane, dir=wdir, app=app))
        if act in ("gym", "build_app", "scan", "run_tests", "pilot") and rng.random() < .6:
            d.blank()
            pairs = {"gym": [("workspace", f"{app}.xcworkspace"), ("scheme", app), ("clean", rng.choice(["true", "false"])),
                             ("output_directory", "./build"), ("output_name", f"{app}.ipa"),
                             ("export_method", rng.choice(["app-store", "ad-hoc", "development"])),
                             ("xcodebuild_formatter", "xcbeautify"), ("build_path", f"/Users/runner/Library/Developer/Xcode/Archives/2024-0{rng.randint(1, 9)}-1{rng.randint(0, 9)}")],
                     "scan": [("workspace", f"{app}.xcworkspace"), ("scheme", f"{app}Tests"), ("device", "iPhone 15"),
                              ("code_coverage", "true"), ("output_types", "html,junit"), ("skip_build", "false")],
                     "pilot": [("api_key_path", "fastlane/api_key.json"), ("ipa", f"./build/{app}.ipa"),
                               ("skip_waiting_for_build_processing", "true"), ("distribute_external", "false"),
                               ("changelog", rng.choice(["Bug fixes and performance improvements", "Nightly build"]))]}
            key = {"build_app": "gym", "run_tests": "scan"}.get(act, act)
            ps = pairs[key]
            ps = ps[:rng.randint(3, len(ps))]
            ver = f"2.{rng.randint(200, 225)}.{rng.randint(0, 3)}"
            boxed_kv(d, f"Summary for {key} {ver}", ps)
            d.blank()
        dur = rng.choice([0, 0, 0, 1, 2, rng.randint(3, 60), rng.randint(60, 900)])
        clock(dur)
        timings.append((act, str(dur)))
        if failed_at == i:
            log(f"Error building the application - see the log above")
            break
    d.blank()
    head = ["Step", "Action", "Time (in s)"]
    rows = [["💥" if failed_at == i else str(i + 1), a, t] for i, (a, t) in enumerate(timings)]
    if rng.random() < .3:  # fastlane prints its own bundle-exec step first
        rows.insert(0, ["1", "Verifying fastlane version", "0"])
        rows = [[str(k + 1) if r[0] != "💥" else r[0]] + r[1:] for k, r in enumerate(rows)]
    w = [max(len(r[c]) for r in rows + [head]) for c in range(3)]
    sep = "+" + "+".join("-" * (x + 2) for x in w) + "+"
    inner = len(sep) - 2
    d.skip(sep)
    d.section("|" + "fastlane summary".center(inner) + "|", "fastlane summary")
    d.skip(sep)
    d.line("| " + " | ".join(head[c].ljust(w[c]) for c in range(3)) + " |", "header", head)
    d.skip(sep)
    for r in rows:
        # terminal-table pads by display width: the emoji takes two columns
        cells = [r[c].ljust(w[c] - (1 if r[c] == "💥" else 0)) for c in range(3)]
        d.line("| " + " | ".join(cells) + " |", "row", r)
    d.skip(sep)
    d.blank()
    # the closing line is a footer, not a log record
    if failed_at is not None:
        d.skip(f"[{clock()}]: fastlane finished with errors")
        d.blank()
        d.skip("[!] Error building the application - see the log above")
    else:
        d.skip(f"[{clock()}]: " + rng.choice(["fastlane.tools finished successfully 🎉",
                                             f"fastlane.tools just saved you {rng.randint(2, 40)} minutes! 🎉"]))
    return d
