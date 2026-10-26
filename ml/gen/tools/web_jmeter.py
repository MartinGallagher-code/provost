"""JMeter non-GUI run (`jmeter -n -t plan.jmx -l out.jtl`): startup prose, then
summariser lines `summary +  N in hh:mm:ss = R/s Avg: .. Min: .. Max: .. Err: .. (..%)`."""
from lib import Doc, fake

TOOL = "jmeter"


def _clock(s):
    return f"{s // 3600:02d}:{s // 60 % 60:02d}:{s % 60:02d}"


def _date(parts, t):
    day, mon, dd, tz, yr = parts
    return f"{day} {mon} {dd:02d} {_clock(t % 86400)} {tz} {yr}"


def generate(rng):
    d = Doc()
    if rng.random() < .3:
        d.skip("WARN StatusConsoleListener The use of package scanning to locate plugins is deprecated and will be removed in a future release")
    if rng.random() < .3:
        d.skip("WARNING: package sun.awt.X11 not in java.desktop")
    d.skip("Creating summariser <summary>")
    plan = f"/{rng.choice(['opt', 'home/jenkins', 'tests'])}/{fake.word(rng)}/{fake.name(rng, '_')}.jmx"
    d.skip(f"Created the tree successfully using {plan}")
    t0 = rng.randint(0, 86400)
    epoch = rng.randint(1_600_000_000_000, 1_790_000_000_000)
    parts = (rng.choice(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]),
             rng.choice("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()), rng.randint(1, 28),
             rng.choice(["UTC", "CET", "EDT", "BST", "PST"]), rng.randint(2021, 2026))
    dt = _date(parts, t0)
    d.line(f"Starting standalone test @ {dt} ({epoch})", "kv", ["Starting standalone test", dt, f"({epoch})"])
    d.skip(f"Waiting for possible Shutdown/StopTestNow/HeapDump/ThreadDump message on port {rng.choice([4445, 4446])}")
    threads = rng.choice([1, 5, 10, 20, 50, 100, 250])
    interval = rng.choice([30, 30, 30, 10, 60])
    elapsed, tot_n, tot_err, mins, maxs, avgsum = 0, 0, 0, [], [], 0
    started = 0
    nsteps = rng.randint(1, 10)
    wa = rng.choice([4, 6, 7])
    for i in range(nsteps):
        dur = rng.randint(1, interval) if i == 0 else interval
        if i == nsteps - 1 and i:
            dur = rng.randint(1, interval)
        elapsed += dur
        last = i == nsteps - 1
        started = threads if last else min(threads, started + rng.randint(1, threads))
        finished = threads if last else 0
        active = started - finished
        n = rng.randint(1, 400) * dur
        err = rng.choice([0, 0, 0, rng.randint(1, max(1, n // 20))])
        avg = rng.randint(1, 3000)
        mn = rng.randint(0, avg)
        mx = avg + rng.randint(0, 20000)
        tot_n, tot_err = tot_n + n, tot_err + err
        mins.append(mn)
        maxs.append(mx)
        avgsum += avg * n

        def line(sign, n, secs, avg, mn, mx, err, tail):
            rate = f"{n / max(secs, 1):.1f}/s"
            pct = f"({100 * err / n:.2f}%)"
            text = (f"summary {sign} {n:>{wa}} in {_clock(secs)} = {rate:>8} Avg: {avg:>5} Min: {mn:>5} Max: {mx:>5} "
                    f"Err: {err:>5} {pct}")
            cells = ["summary", sign, str(n), f"in {_clock(secs)}", rate, "Avg", str(avg), "Min", str(mn), "Max", str(mx),
                     "Err", str(err), pct]
            if tail:
                text += " " + " ".join(f"{k}: {v}" for k, v in tail)
                for k, v in tail:
                    cells += [k, str(v)]
            d.line(text, "row", cells)

        if nsteps > 1:
            line("+", n, dur, avg, mn, mx, err, [("Active", active), ("Started", started), ("Finished", finished)])
        if i or nsteps == 1:
            line("=", tot_n, elapsed, avgsum // tot_n, min(mins), max(maxs), tot_err, [])
    t1 = t0 + elapsed
    d.line(f"Tidying up ...    @ {_date(parts, t1)} ({epoch + elapsed * 1000})", "kv", [])
    d.labels[-1]["cells"] = ["Tidying up", d.lines[-1].split("@ ")[1].split(" (")[0], f"({epoch + elapsed * 1000})"]
    d.skip("... end of run")
    return d
