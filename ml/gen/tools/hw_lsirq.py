"""util-linux `lsirq`: interrupt counters, right-aligned IRQ and TOTAL
columns; or the -n (no header) and -P (KEY="value" pairs) forms."""
from lib import Doc

TOOL = "lsirq"

NAMED = [("LOC", "Local timer interrupts"), ("CAL", "Function call interrupts"), ("RES", "Rescheduling interrupts"),
         ("TLB", "TLB shootdowns"), ("PMI", "Performance monitoring interrupts"), ("IWI", "IRQ work interrupts"),
         ("NMI", "Non-maskable interrupts"), ("THR", "Threshold APIC interrupts"), ("MCP", "Machine check polls"),
         ("SPU", "Spurious interrupts"), ("DFR", "Deferred Error APIC interrupts"), ("MCE", "Machine check exceptions"),
         ("TRM", "Thermal event interrupts"), ("PIN", "Posted-interrupt notification event"),
         ("NPI", "Nested posted-interrupt event"), ("PIW", "Posted-interrupt wakeup event"),
         ("HYP", "Hypervisor callback interrupts"), ("ERR", ""), ("MIS", "")]
DEVS = ["nvme0q0", "nvme0q1", "nvme0q2", "xhci_hcd", "ahci[0000:00:17.0]", "i915", "amdgpu", "enp2s0",
        "eno1-TxRx-0", "eno1-TxRx-1", "iwlwifi:default_queue", "iwlwifi:queue_1", "snd_hda_intel:card0",
        "mei_me", "thunderbolt", "intel-ipu", "virtio0-config", "virtio1-input.0", "megasas0-msix0",
        "mlx5_comp0@pci:0000:3b:00.0", "idma64.0", "i801_smbus", "rtw88_pci", "nvidia", "vfio-msix[0](0000:41:00.0)"]
LEGACY = [("0", "IR-IO-APIC 2-edge timer"), ("8", "IR-IO-APIC 8-edge rtc0"), ("9", "IR-IO-APIC 9-fasteoi acpi"),
          ("1", "IR-IO-APIC 1-edge i8042"), ("12", "IR-IO-APIC 12-edge i8042"), ("14", "IR-IO-APIC 14-fasteoi INT345D:00"),
          ("16", "IR-IO-APIC 16-fasteoi i801_smbus"), ("4", "IO-APIC 4-edge ttyS0")]


def generate(rng):
    d = Doc()
    rows = []
    for irq, name in rng.sample(NAMED, rng.randint(3, len(NAMED))):
        rows.append([irq, name])
    for irq, name in rng.sample(LEGACY, rng.randint(0, 4)):
        rows.append([irq, name])
    base = rng.choice([120, 24, 32, 40])
    for k, dev in enumerate(rng.sample(DEVS, rng.randint(2, 12))):
        kind = rng.choice(["IR-PCI-MSI", "IR-PCI-MSIX", "PCI-MSI", "PCI-MSIX"])
        hw = rng.choice([524288, 327680, 1048576, 32768, 2097152, 3145728]) + rng.randint(0, 8)
        rows.append([str(base + k), f"{kind}-{rng.choice(['0000:00:14.0', '0000:01:00.0', '0000:02:00.0'])} {hw}-edge {dev}"
                     if rng.random() < 0.3 else f"{kind} {hw}-edge {dev}"])
    big = rng.choice([10 ** 4, 10 ** 6, 10 ** 8])
    for r in rows:
        r.insert(1, str(int(rng.random() ** 3 * big)))
    if rng.random() < 0.8:
        rows.sort(key=lambda r: -int(r[1]))
    rows = [[r[0], r[1], r[2] or None] for r in rows]
    form = rng.choices(["table", "noheader", "pairs", "two"], [5, 2, 2, 1])[0]
    if form == "pairs":
        for irq, tot, name in rows:
            text = f'IRQ="{irq}" TOTAL="{tot}" NAME="{name or ""}"'
            d.line(text, "row", ["IRQ", irq, "TOTAL", tot, "NAME"] + ([name] if name else []))
    elif form == "two":
        d.table(["IRQ", "TOTAL"], [r[:2] for r in rows], gap=1, right=(0, 1))
    else:
        d.table(["IRQ", "TOTAL", "NAME"] if form == "table" else None, rows, gap=1, right=(0, 1))
    return d
