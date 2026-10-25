"""`bitbake <image>` (non-interactive): progress lines (`Parsing recipes: 100%
|###| Time: 0:00:12`), parse summary prose, NOTE:/WARNING: log lines, the
Build Configuration `KEY = "value"` block (layer lines sharing a revision
print the value only on the last one), the Sstate summary and Tasks Summary."""
from lib import Doc, fake

TOOL = "bitbake"

MACHINES = ["qemux86-64", "raspberrypi4-64", "beaglebone-yocto", "imx8mm-evk", "genericx86-64", "qemuarm64", "jetson-xavier-nx-devkit"]
LAYERS = ["meta", "meta-poky", "meta-yocto-bsp", "meta-oe", "meta-python", "meta-networking", "meta-multimedia",
          "meta-raspberrypi", "meta-freescale", "meta-virtualization", "meta-security", "meta-custom", "meta-tegra"]
RECIPES = ["busybox_1.36.1.bb", "openssl_3.2.1.bb", "linux-yocto_6.6.bb", "glibc_2.39.bb", "systemd_255.4.bb",
           "python3_3.12.3.bb", "core-image-minimal.bb", "u-boot_2024.01.bb", "dropbear_2022.83.bb"]
TASKS = ["do_fetch", "do_unpack", "do_patch", "do_configure", "do_compile", "do_install", "do_package",
         "do_package_write_rpm", "do_populate_sysroot", "do_rootfs", "do_image_wic"]


def bar(rng, d, label):
    w = rng.randint(30, 60)
    t = f"0:{rng.randint(0, 5):02d}:{rng.randint(0, 59):02d}"
    d.line(f"{label}: 100% |{'#' * w}| Time: {t}", "row", [label, "100%", "Time", t])


def generate(rng):
    d = Doc()
    release = rng.choice(["kirkstone", "scarthgap", "dunfell", "nanbield", "master"])
    ver = {"kirkstone": "4.0", "scarthgap": "5.0", "dunfell": "3.1", "nanbield": "4.3", "master": "5.1"}[release]
    if rng.random() < .4:
        msg = f"Started PRServer with DBfile: /build/cache/prserv.sqlite3, Address: 127.0.0.1:{rng.randint(30000, 60000)}, PID: {rng.randint(1000, 99999)}"
        d.line(f"NOTE: {msg}", "row", ["NOTE", msg])
    if rng.random() < .6:
        bar(rng, d, "Loading cache")
        d.skip(f"Loaded {rng.randint(1000, 5000)} entries from dependency cache.")
    else:
        bar(rng, d, "Parsing recipes")
        n = rng.randint(800, 3000)
        d.skip(f"Parsing of {n} .bb files complete (0 cached, {n} parsed). {n * 2 + rng.randint(0, 99)} targets, "
               f"{rng.randint(0, 200)} skipped, 0 masked, 0 errors.")
    if rng.random() < .5:
        msg = rng.choice([f"Host distribution \"ubuntu-24.04\" has not been validated with this version of the build system; you may possibly experience unexpected failures. It is recommended that you use a tested distribution.",
                          "You have included the meta-virtualization layer, but 'virtualization' has not been enabled in your DISTRO_FEATURES."])
        d.line(f"WARNING: {msg}", "row", ["WARNING", msg])
    d.line("NOTE: Resolving any missing task queue dependencies", "row", ["NOTE", "Resolving any missing task queue dependencies"])
    d.blank()
    d.section("Build Configuration:")
    arch = rng.choice(["aarch64", "x86_64", "arm"])
    pairs = [("BB_VERSION", f"2.{rng.randint(0, 8)}.{rng.randint(0, 9)}"), ("BUILD_SYS", "x86_64-linux"),
             ("NATIVELSBSTRING", rng.choice(["universal", "ubuntu-22.04", "debian-12"])),
             ("TARGET_SYS", f"{arch}-poky-linux" + ("-gnueabi" if arch == "arm" else "")),
             ("MACHINE", rng.choice(MACHINES)), ("DISTRO", rng.choice(["poky", "poky", "custom-distro", "poky-tiny"])),
             ("DISTRO_VERSION", f"{ver}.{rng.randint(1, 20)}"),
             ("TUNE_FEATURES", rng.choice(["aarch64 armv8a crc cortexa72", "m64 core2", "arm vfp cortexa8 neon callconvention-hard", "m64 x86-64-v3"])),
             ("TARGET_FPU", rng.choice(["", "hard"]))]
    for k, v in pairs:
        val = f'"{v}"'
        d.line(f"{k.ljust(20)} = {val}", "kv", [k, val])
    layers = ["meta", "meta-poky", "meta-yocto-bsp"] + rng.sample(LAYERS[3:], rng.randint(0, 6))
    groups = []
    for l in layers:
        if groups and rng.random() < .6:
            groups[-1].append(l)
        else:
            groups.append([l])
    for g in groups:
        rev = f'"{rng.choice([release, release, "HEAD", "main"])}:{fake.hexid(rng, 40)}"'
        for l in g[:-1]:
            d.line(l.ljust(20) + " ", "kv", [l])
        d.line(f"{g[-1].ljust(20)} = {rev}", "kv", [g[-1], rev])
    d.blank()
    bar(rng, d, "Initialising tasks")
    want = rng.randint(200, 6000)
    loc = rng.randint(0, want)
    mir = rng.randint(0, want - loc)
    miss = want - loc - mir
    cur = rng.randint(0, 3000)
    match = f"{100 * (loc + mir) // want}% match"
    comp = f"{100 * (loc + mir + cur) // (want + cur)}% complete"
    d.line(f"Sstate summary: Wanted {want} Local {loc} Mirrors {mir} Missed {miss} Current {cur} ({match}, {comp})", "row",
           ["Sstate summary", "Wanted", str(want), "Local", str(loc), "Mirrors", str(mir), "Missed", str(miss),
            "Current", str(cur), match, comp])
    d.line("NOTE: Executing Tasks", "row", ["NOTE", "Executing Tasks"])
    total = want + cur + rng.randint(100, 900)
    if rng.random() < .5:
        for i in sorted(rng.sample(range(1, total), rng.randint(1, 8))):
            rec, task = rng.choice(RECIPES), rng.choice(TASKS)
            msg = rng.choice([f"Running task {i} of {total} (/build/poky/meta/recipes-core/{rec.split('_')[0]}/{rec}:{task})",
                              f"recipe {rec[:-3].replace('_', '-')}-r0: task {task}: Started",
                              f"recipe {rec[:-3].replace('_', '-')}-r0: task {task}: Succeeded"])
            d.line(f"NOTE: {msg}", "row", ["NOTE", msg])
    failed = rng.random() < .15
    if failed:
        rec, task = rng.choice(RECIPES), rng.choice(TASKS[3:6])
        msg = f"{rec[:-3].replace('_', '-')}-r0 {task}: oe_runmake failed"
        d.line(f"ERROR: {msg}", "row", ["ERROR", msg])
        msg = f"Task (/build/poky/meta/recipes-core/{rec.split('_')[0]}/{rec}:{task}) failed with exit code '1'"
        d.line(f"ERROR: {msg}", "row", ["ERROR", msg])
        msg = (f"Tasks Summary: Attempted {total} tasks of which {rng.randint(0, total)} didn't need to be rerun and 1 failed.")
    else:
        msg = f"Tasks Summary: Attempted {total} tasks of which {rng.randint(0, total)} didn't need to be rerun and all succeeded."
    d.line(f"NOTE: {msg}", "row", ["NOTE", msg])
    if failed:
        d.blank()
        d.skip("Summary: 1 task failed:")
        d.skip(f"  /build/poky/meta/recipes-core/{rec.split('_')[0]}/{rec}:{task}")
        d.skip("Summary: There was 1 ERROR message, returning a non-zero exit code.")
    elif rng.random() < .3:
        d.blank()
        d.skip(f"Summary: There {'was 1 WARNING message' if rng.random() < .5 else 'were 2 WARNING messages'}.")
    return d
