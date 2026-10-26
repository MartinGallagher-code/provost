"""stm32flash (STM32 UART/I2C bootloader flasher): banner, `Key : value`
device report with `- RAM :` sub-items, then `Wrote address 0x... (n%)`
progress lines and a closing status."""
from lib import Doc, fake

TOOL = "stm32flash"

DEVICES = [("0x0410", "STM32F10xxx Medium-density", "20KiB", "512b", "128KiB", "4x1024", "16b", "2KiB"),
           ("0x0414", "STM32F10xxx High-density", "64KiB", "512b", "512KiB", "2x2048", "16b", "2KiB"),
           ("0x0413", "STM32F40xxx/41xxx", "128KiB", "12288b", "1024KiB", "1x16384", "64b", "30KiB"),
           ("0x0440", "STM32F030x8/F05xxx", "8KiB", "2048b", "64KiB", "4x1024", "16b", "3KiB"),
           ("0x0435", "STM32L43xxx/44xxx", "64KiB", "12288b", "256KiB", "1x2048", "16b", "28KiB"),
           ("0x0460", "STM32G07xxx/08xxx", "36KiB", "6144b", "128KiB", "1x2048", "128b", "28KiB")]


def generate(rng):
    d = Doc()
    ver = rng.choice(["0.5", "0.6", "0.7"])
    d.skip(f"stm32flash {ver}")
    d.blank()
    d.skip("http://stm32flash.sourceforge.net/")
    d.blank()
    mode = rng.choice(["write", "write", "read", "erase", "info"])
    if mode == "write":
        parser = rng.choice(["Intel HEX", "Raw BINARY"])
        d.kv("Using Parser", parser, sep=" : ")
        if parser == "Raw BINARY" or rng.random() < .5:
            size = rng.randint(1024, 120000)
            d.kv("Size", str(size), sep=" " * 9 + ": ")
    elif mode == "read":
        d.kv("Using Parser", "Raw BINARY", sep=" : ")
    iface = rng.choice(["serial_posix", "serial_posix", "serial_w32", "i2c"])
    if iface == "i2c":
        conf = f"addr 0x{rng.choice([0x39, 0x3b, 0x56])}"
    else:
        conf = f"{rng.choice([115200, 57600, 9600, 230400, 460800])} 8E1"
    d.line(f"Interface {iface}: {conf}", "kv", [f"Interface {iface}", conf])
    did, name, ram, res, flash, sect, opt, sysram = rng.choice(DEVICES)
    for k, v in [("Version", f"0x{rng.choice([22, 31, 40, 30, '3a'])}"), ("Option 1", "0x00"), ("Option 2", "0x00"),
                 ("Device ID", f"{did} ({name})")]:
        d.line(f"{k.ljust(12)} : {v}", "kv", [k, v])
    for k, v in [("RAM", f"Up to {ram}  ({res} reserved by bootloader)"),
                 ("Flash", f"Up to {flash} (size first sector: {sect})"),
                 ("Option RAM", opt), ("System RAM", sysram)]:
        d.line(f"- {k.ljust(10)} : {v}", "kv", [k, v])
    if mode == "info":
        return d
    base = 0x08000000
    total = int(flash[:-3]) * 1024
    if mode == "write":
        d.skip("Write to memory")
        d.skip("Erasing memory")
        verb = "Wrote"
        n = rng.randint(2048, min(total, 160000))
    elif mode == "read":
        d.skip("Memory read")
        verb = "Read"
        n = total if rng.random() < .5 else rng.randint(4096, total)
    else:
        if rng.random() < .5:
            d.skip("Erasing memory")
        else:
            d.skip(f"Erasing memory, page range {rng.randint(0, 3)} - {rng.randint(8, 63)}")
        d.skip("Done.")
        return d
    step = 256 * rng.choice([1, 4, 16, 64])
    steps = max(2, min(40, n // step))
    chunk = ((n + steps - 1) // steps + 255) // 256 * 256
    prefix = "Wrote" if verb == "Wrote" else "Read"
    if mode == "write" and rng.random() < .3:
        prefix = "Wrote and verified"
    i = 0
    while True:
        i += 1
        done = min(n, i * chunk)
        last = done >= n
        a = f"0x{base + done:08x}"
        pct = f"({100.0 * done / n:.2f}%)"
        text = f"{prefix} address {a} {pct} " + ("Done." if last else "")
        d.line(text, "row", [f"{prefix} address", a, pct] + (["Done."] if last else []))
        if last:
            break
    d.blank()
    if mode == "write" and rng.random() < .7:
        go = rng.choice(["0x08000000", "0x08000000", "0x08002000"])
        d.line(f"Starting execution at address {go}... done.", "kv", ["Starting execution at address", f"{go}... done."])
    if rng.random() < .3:
        d.blank()
    return d
