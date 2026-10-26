"""linuxptp `pmc -u -b 0 'GET ...'`: a `sending:` line per request, a
response heading per port, then tab-indented aligned key/value fields."""
from lib import Doc, fake

TOOL = "pmc"


def cid(rng):
    h = fake.hexid(rng, 12)
    return f"{h[:6]}.fffe.{h[6:]}"


def flt(rng, lo, hi):
    return f"{rng.uniform(lo, hi):.1f}"


DATASETS = {
    "CURRENT_DATA_SET": lambda rng: [("stepsRemoved", str(rng.randint(0, 4))),
                                     ("offsetFromMaster", flt(rng, -900, 900)),
                                     ("meanPathDelay", flt(rng, 0, 20000))],
    "TIME_STATUS_NP": lambda rng: [("master_offset", str(rng.randint(-3000, 3000))),
                                   ("ingress_time", str(rng.randint(10 ** 18, 2 * 10 ** 18))),
                                   ("cumulativeScaledRateOffset", f"{rng.uniform(-1e-5, 1e-5):+.9f}"),
                                   ("scaledLastGmPhaseChange", "0"),
                                   ("gmTimeBaseIndicator", "0"),
                                   ("lastGmPhaseChange", "0x0000'0000000000000000.0000"),
                                   ("gmPresent", rng.choice(["true", "false"])),
                                   ("gmIdentity", cid(rng))],
    "PARENT_DATA_SET": lambda rng: [("parentPortIdentity", cid(rng) + "-" + str(rng.randint(1, 4))),
                                    ("parentStats", "0"),
                                    ("observedParentOffsetScaledLogVariance", "0xffff"),
                                    ("observedParentClockPhaseChangeRate", "0x7fffffff"),
                                    ("grandmasterPriority1", str(rng.choice([128, 127, 0, 255]))),
                                    ("gm.ClockClass", str(rng.choice([6, 7, 52, 135, 248]))),
                                    ("gm.ClockAccuracy", rng.choice(["0x21", "0x20", "0xfe", "0x31"])),
                                    ("gm.OffsetScaledLogVariance", rng.choice(["0x4e5d", "0xffff", "0x436a"])),
                                    ("grandmasterPriority2", str(rng.choice([128, 127]))),
                                    ("grandmasterIdentity", cid(rng))],
    "DEFAULT_DATA_SET": lambda rng: [("twoStepFlag", str(rng.randint(0, 1))),
                                     ("slaveOnly", str(rng.randint(0, 1))),
                                     ("numberPorts", str(rng.randint(1, 4))),
                                     ("priority1", str(rng.choice([128, 127, 0]))),
                                     ("clockClass", str(rng.choice([248, 255, 6]))),
                                     ("clockAccuracy", rng.choice(["0xfe", "0x21"])),
                                     ("offsetScaledLogVariance", "0xffff"),
                                     ("priority2", "128"),
                                     ("clockIdentity", cid(rng)),
                                     ("domainNumber", str(rng.choice([0, 0, 24, 127]))),],
    "PORT_DATA_SET": lambda rng: [("portIdentity", cid(rng) + "-1"),
                                  ("portState", rng.choice(["SLAVE", "MASTER", "LISTENING", "PASSIVE", "FAULTY"])),
                                  ("logMinDelayReqInterval", str(rng.randint(-4, 0))),
                                  ("peerMeanPathDelay", str(rng.choice([0, rng.randint(0, 9000)]))),
                                  ("logAnnounceInterval", str(rng.randint(-3, 1))),
                                  ("announceReceiptTimeout", "3"),
                                  ("logSyncInterval", str(rng.randint(-4, 0))),
                                  ("delayMechanism", str(rng.randint(1, 2))),
                                  ("logMinPdelayReqInterval", "0"),
                                  ("versionNumber", "2")],
    "TIME_PROPERTIES_DATA_SET": lambda rng: [("currentUtcOffset", "37"),
                                             ("leap61", "0"), ("leap59", "0"),
                                             ("currentUtcOffsetValid", str(rng.randint(0, 1))),
                                             ("ptpTimescale", "1"),
                                             ("timeTraceable", str(rng.randint(0, 1))),
                                             ("frequencyTraceable", str(rng.randint(0, 1))),
                                             ("timeSource", rng.choice(["0x20", "0xa0", "0x40"]))],
}


def generate(rng):
    d = Doc()
    names = rng.sample(sorted(DATASETS), rng.randint(1, 3))
    ident = cid(rng)
    for name in names:
        d.line(f"sending: GET {name}", "kv", ["sending", f"GET {name}"])
        for port in range(rng.choice([1, 1, 1, 2])):
            title = f"{ident}-{port} seq {rng.randint(0, 4)} RESPONSE MANAGEMENT {name}"
            d.section("\t" + title + " ", title)
            pairs = DATASETS[name](rng)
            if rng.random() < 0.2:
                pairs = pairs[:max(1, len(pairs) - rng.randint(1, 3))]
            w = max(len(k) for k, _ in pairs) + rng.choice([1, 4, 9])
            w = max(w, 27 if rng.random() < .5 else w)
            for k, v in pairs:
                d.line("\t\t" + k.ljust(w) + v, "kv", [k, v])
    return d
