"""`xcodebuild -list` / `-showsdks` / `-version`: indented, sectioned listings
(Targets:, Build Configurations:, Schemes:), tab-separated SDK rows with their
-sdk selector, or the two-line version report."""
from lib import Doc

TOOL = "xcodebuild"

APPS = ["Weather", "Notes", "TodoApp", "Acme", "PhotoKit", "Runner", "MyApp", "Pulse", "Tally", "Fieldbook"]
CONFIGS = ["Debug", "Release", "Staging", "Beta", "Profile", "AppStore"]


def invocation(rng, d, args):
    if rng.random() < .35:
        d.section("Command line invocation:")
        cmd = "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild " + args
        d.line("    " + cmd, "row", [cmd])
        d.blank()
        if rng.random() < .5:
            d.section("User defaults from command line:")
            for k, v in rng.sample([("IDEPackageSupportUseBuiltinSCM", "YES"), ("IDEBuildOperationMaxNumberOfConcurrentCompileTasks", "8"),
                                    ("DVTDeveloperModeEnabled", "NO")], rng.randint(1, 2)):
                d.kv(k, v, sep=" = ", indent="    ")
            d.blank()


def do_list(rng, d):
    app = rng.choice(APPS)
    invocation(rng, d, "-list" + (f" -project {app}.xcodeproj" if rng.random() < .3 else ""))
    kind = "workspace" if rng.random() < .3 else "project"
    d.section(f"Information about {kind} \"{app}\":", f"Information about {kind} \"{app}\"")
    if kind == "project":
        targets = [app] + rng.sample([f"{app}Tests", f"{app}UITests", f"{app}Widget", f"{app}Kit",
                                      f"{app} Watch App", f"{app}NotificationService", "Pods-" + app], rng.randint(0, 5))
        d.section("    Targets:")
        for t in targets:
            d.line("        " + t, "row", [t])
        d.blank()
        cfgs = ["Debug", "Release"] + rng.sample(CONFIGS[2:], rng.randint(0, 2))
        d.section("    Build Configurations:")
        for c in cfgs:
            d.line("        " + c, "row", [c])
        d.blank()
        d.skip(f"    If no build configuration is specified and -scheme is not passed then \"{rng.choice(cfgs[:2])}\" is used.")
        d.blank()
    d.section("    Schemes:")
    schemes = [app] + rng.sample([f"{app}-Staging", f"{app}Kit", f"{app} (Production)", "Alamofire", "SnapKit",
                                  "Pods-" + app, f"{app}Widget", "RxSwift"], rng.randint(0, 5))
    for s in schemes:
        d.line("        " + s, "row", [s])
    d.blank()


def do_sdks(rng, d):
    invocation(rng, d, "-showsdks")
    x = rng.choice([(14, 0), (15, 2), (15, 4), (16, 1)])
    ios = f"{x[0] + 2}.{x[1]}"
    mac = f"{x[0] - 1}.{x[1]}"
    plats = [("DriverKit SDKs:", [(f"DriverKit {x[0] + 8}.{x[1]}", f"driverkit{x[0] + 8}.{x[1]}")]),
             ("iOS SDKs:", [(f"iOS {ios}", f"iphoneos{ios}")]),
             ("iOS Simulator SDKs:", [(f"Simulator - iOS {ios}", f"iphonesimulator{ios}")]),
             ("macOS SDKs:", [(f"macOS {mac}", f"macosx{mac}")] + ([(f"macOS {mac[:2]}.0", f"macosx{mac[:2]}.0")] if rng.random() < .3 else [])),
             ("tvOS SDKs:", [(f"tvOS {ios}", f"appletvos{ios}")]),
             ("tvOS Simulator SDKs:", [(f"Simulator - tvOS {ios}", f"appletvsimulator{ios}")]),
             ("visionOS SDKs:", [(f"visionOS 1.{x[1] % 3}", f"xros1.{x[1] % 3}")]),
             ("watchOS SDKs:", [(f"watchOS {x[0] - 5}.{x[1]}", f"watchos{x[0] - 5}.{x[1]}")]),
             ("watchOS Simulator SDKs:", [(f"Simulator - watchOS {x[0] - 5}.{x[1]}", f"watchsimulator{x[0] - 5}.{x[1]}")])]
    keep = [p for p in plats if p[0].startswith(("iOS", "macOS")) or rng.random() < .6]
    for title, sdks in keep:
        d.section(title)
        for name, sel in sdks:
            flag = f"-sdk {sel}"
            d.line(f"\t{name.ljust(30)}\t{flag}", "row", [name, flag])
        d.blank()


def do_version(rng, d):
    major = rng.choice([13, 14, 15, 16])
    v = f"{major}.{rng.randint(0, 4)}" + (f".{rng.randint(1, 3)}" if rng.random() < .4 else "")
    d.kv("Xcode", v, sep=" ")
    b = f"{major + 8}{rng.choice('ABCDEFG')}{rng.randint(10, 600)}{rng.choice(['', 'a', 'b', 'e'])}"
    d.kv("Build version", b, sep=" ")
    if rng.random() < .3:  # -version -sdk
        d.blank()
        d.section(f"iPhoneOS{major + 2}.{rng.randint(0, 4)}.sdk - iOS {major + 2}.{rng.randint(0, 4)} (iphoneos{major + 2}.{rng.randint(0, 4)})")
        pairs = [("SDKVersion", f"{major + 2}.{rng.randint(0, 4)}"),
                 ("Path", f"/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS{major + 2}.2.sdk"),
                 ("PlatformVersion", f"{major + 2}.{rng.randint(0, 4)}"),
                 ("PlatformPath", "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform"),
                 ("BuildID", "".join(rng.choice("0123456789ABCDEF") for _ in range(8)) + "-" + "".join(rng.choice("0123456789ABCDEF") for _ in range(4))),
                 ("ProductBuildVersion", f"{major + 6}C{rng.randint(50, 99)}"),
                 ("ProductCopyright", "1983-2024 Apple Inc."),
                 ("ProductName", "iPhone OS"),
                 ("ProductVersion", f"{major + 2}.{rng.randint(0, 4)}")]
        for k, v in pairs:
            d.kv(k, v)


def generate(rng):
    d = Doc()
    rng.choice([do_list, do_list, do_sdks, do_version])(rng, d)
    return d
