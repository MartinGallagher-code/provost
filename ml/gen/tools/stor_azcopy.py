"""Azure `azcopy copy|sync SRC DST`: INFO lines, job start and log path,
comma-separated progress lines with a throughput pair, then a `Job ...
summary` block of `key: value` lines ending in Final Job Status."""
from lib import Doc, fake

TOOL = "azcopy-copy"


def generate(rng):
    d = Doc()
    sync = rng.random() < .25
    d.line("INFO: Scanning...", "row", ["INFO", "Scanning..."])
    if rng.random() < .7:
        msg = rng.choice(["Any empty folders will not be processed, because source and/or destination doesn't have full folder support",
                          "Authenticating to destination using Azure AD",
                          "Autosense: Detected that you have an Azure DevOps Pipeline...",
                          "Discovering local files..."])
        d.line(f"INFO: {msg}", "row", ["INFO", msg])
    d.blank()
    job = fake.uuid(rng)
    d.skip(f"Job {job} has started")
    home = rng.choice(["/root", "/home/" + fake.user(rng), "C:\\Users\\" + fake.user(rng)])
    sep = "\\" if home.startswith("C:") else "/"
    log = f"{home}{sep}.azcopy{sep}{job}.log"
    d.kv("Log file is located at", log)
    d.blank()
    total = rng.choice([1, rng.randint(2, 40), rng.randint(40, 50000)])
    failed_final = rng.choice([0, 0, 0, 0, rng.randint(1, max(1, total // 5))])
    skipped_final = rng.choice([0, 0, rng.randint(0, total)]) if sync or rng.random() < .3 else 0
    skipped_final = min(skipped_final, total - failed_final)
    steps = rng.randint(1, 8)
    done = failed = 0
    for i in range(steps):
        last = i == steps - 1
        skipped = 0
        if last:
            failed, skipped = failed_final, skipped_final
            done = total - failed - skipped
        else:
            done = min(total - failed_final - skipped_final, done + rng.randint(0, max(1, total // steps)))
            failed = min(failed_final, failed + rng.randint(0, 1))
        pend = total - done - failed - skipped
        pct = f"{100.0 if last else min(99.9, (done + failed + skipped) * 100 / total):.1f} %"
        tp = f"{rng.uniform(0, 2000):.4f}".rstrip("0").rstrip(".") if rng.random() < .8 else "0"
        cells = [pct, f"{done} Done", f"{failed} Failed", f"{pend} Pending", f"{skipped} Skipped", f"{total} Total"]
        d.line(", ".join(cells) + ", 2-sec Throughput (Mb/s): " + tp, "row", cells + ["2-sec Throughput (Mb/s)", tp])
    d.blank()
    d.blank()
    d.section(f"Job {job} summary", f"Job {job} summary")
    mins = f"{rng.uniform(0.01, 300):.4f}"
    status = "Completed" if not failed_final else rng.choice(["CompletedWithErrors", "Failed"])
    if skipped_final and not failed_final:
        status = "CompletedWithSkipped"
    files = total - rng.randint(0, total // 10)
    folders = total - files
    pairs = [("Elapsed Time (Minutes)", mins),
             ("Number of File Transfers", str(files)),
             ("Number of Folder Property Transfers", str(folders))]
    if rng.random() < .7:
        pairs.append(("Number of Symlink Transfers", "0"))
    pairs += [("Total Number of Transfers", str(total)),
              ("Number of File Transfers Completed", str(max(0, files - failed_final - skipped_final))),
              ("Number of Folder Transfers Completed", str(folders)),
              ("Number of File Transfers Failed", str(failed_final)),
              ("Number of Folder Transfers Failed", "0"),
              ("Number of File Transfers Skipped", str(skipped_final)),
              ("Number of Folder Transfers Skipped", "0"),
              ("TotalBytesTransferred", str(rng.randint(0, 2 ** 40))),
              ("Final Job Status", status)]
    if sync and rng.random() < .5:
        pairs.insert(1, ("Files Scanned at Source", str(total + rng.randint(0, 100))))
        pairs.insert(2, ("Files Scanned at Destination", str(rng.randint(0, total))))
    for k, v in pairs:
        d.kv(k, v)
    d.blank()
    return d
