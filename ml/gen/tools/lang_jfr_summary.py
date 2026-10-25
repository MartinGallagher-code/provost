"""`jfr summary recording.jfr` (JDK 14+): a short key/value preamble, then an
aligned event-type table under a `====` rule."""
from lib import Doc, fake

TOOL = "jfr-summary"

EVENTS = """jdk.ObjectAllocationSample jdk.ExecutionSample jdk.NativeMethodSample jdk.ThreadPark
jdk.JavaMonitorEnter jdk.GCPhasePause jdk.GCPhasePauseLevel1 jdk.GCPhasePauseLevel2 jdk.GarbageCollection
jdk.G1GarbageCollection jdk.YoungGarbageCollection jdk.OldGarbageCollection jdk.GCHeapSummary
jdk.MetaspaceSummary jdk.G1HeapSummary jdk.CPULoad jdk.ThreadCPULoad jdk.ThreadContextSwitchRate
jdk.ClassLoadingStatistics jdk.ThreadAllocationStatistics jdk.CompilerStatistics jdk.Compilation
jdk.CompilerInlining jdk.CodeCacheStatistics jdk.SafepointBegin jdk.SafepointEnd jdk.ExecuteVMOperation
jdk.SocketRead jdk.SocketWrite jdk.FileRead jdk.FileWrite jdk.JavaExceptionThrow jdk.JavaErrorThrow
jdk.ExceptionStatistics jdk.ActiveSetting jdk.ActiveRecording jdk.JVMInformation jdk.OSInformation
jdk.CPUInformation jdk.InitialSystemProperty jdk.InitialEnvironmentVariable jdk.SystemProcess
jdk.NativeLibrary jdk.ModuleExport jdk.ModuleRequire jdk.ThreadStart jdk.ThreadEnd jdk.ThreadSleep
jdk.ThreadDump jdk.PhysicalMemory jdk.NetworkUtilization jdk.ObjectCount jdk.OldObjectSample
jdk.TenuringDistribution jdk.GCConfiguration jdk.GCHeapConfiguration jdk.YoungGenerationConfiguration
jdk.BooleanFlag jdk.IntFlag jdk.LongFlag jdk.StringFlag jdk.UnsignedLongFlag jdk.DoubleFlag
jdk.Metadata jdk.CheckPoint jdk.VirtualThreadPinned jdk.VirtualThreadStart jdk.ContainerConfiguration
jdk.ContainerCPUUsage jdk.ContainerMemoryUsage jdk.SecurityPropertyModification jdk.TLSHandshake""".split()


def generate(rng):
    d = Doc()
    d.blank()
    pre = [("Version", rng.choice(["2.0", "2.1"])),
           ("Chunks", str(rng.choice([1, 1, 1, 2, 3, rng.randint(4, 40)])))]
    if rng.random() < .4:
        pre.append(("Size", f"{rng.randint(80000, 90000000)} bytes"))
    tz = rng.choice(["(UTC)", "(UTC)", "(CET)"])
    pre.append(("Start", fake.date(rng, "datetime") + " " + tz))
    dur = rng.choice([f"{rng.randint(1, 3600)} s", f"{rng.randint(1, 600)} s", f"{rng.randint(1, 59)} min"])
    pre.append(("Duration", dur))
    for k, v in pre:
        d.line(f" {k}: {v}", "kv", [k, v])
    d.blank()
    events = rng.sample(EVENTS, rng.randint(8, min(len(EVENTS), 45)))
    rows = []
    for e in events:
        cnt = rng.choice([0, 1, 2, rng.randint(3, 99), rng.randint(100, 9999), rng.randint(10000, 900000)])
        size = 0 if cnt == 0 else cnt * rng.randint(8, 160) + rng.randint(0, 900)
        rows.append((e, cnt, size))
    rows.sort(key=lambda r: -r[1])
    ew = max(rng.choice([40, 44, 46]), max(len(e) for e, _, _ in rows) + 1)
    header = " " + "Event Type".ljust(ew) + "Count".rjust(10) + "  Size (bytes) "
    d.line(header, "header", ["Event Type", "Count", "Size (bytes)"])
    d.skip("=" * (len(header) - 1 + rng.choice([0, 0, 1])))
    for e, cnt, size in rows:
        d.line(" " + e.ljust(ew) + str(cnt).rjust(10) + str(size).rjust(14), "row", [e, str(cnt), str(size)])
    return d
