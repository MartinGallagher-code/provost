"""avrdude: `avrdude: ...` log lines, `#####` progress bars, the verbose
part/programmer report (`Key : value` plus the memory-detail table with a
two-row header), and the closing summary."""
from lib import Doc, fake

TOOL = "avrdude"

PARTS = {
    "ATmega328P": ("m328p", "0x1e950f", 32768, 1024, 128),
    "ATmega2560": ("m2560", "0x1e9801", 262144, 4096, 256),
    "ATmega32U4": ("m32u4", "0x1e9587", 32768, 1024, 128),
    "ATtiny85": ("t85", "0x1e930b", 8192, 512, 64),
    "ATmega168": ("m168", "0x1e9406", 16384, 512, 128),
}
PROGRAMMERS = [("arduino", "Arduino", "Arduino"), ("usbasp", "usbasp", "USBasp, http://www.fischl.de/usbasp/"),
               ("avrisp2", "STK500V2", "Atmel AVR ISP mkII"), ("wiring", "Wiring", "Wiring"),
               ("avr109", "butterfly", "Atmel AppNote AVR109 Boot Loader")]


def bar(d, rng, verb):
    t = f"{rng.uniform(0, 12):.2f}s"
    d.line(f"{verb} | {'#' * 50} | 100% {t}", "row", [verb, "100%", t])


def generate(rng):
    d = Doc()
    part = rng.choice(list(PARTS))
    short, sig, flash, eep, page = PARTS[part]
    prog, ptype, pdesc = rng.choice(PROGRAMMERS)
    port = rng.choice(["/dev/ttyUSB0", "/dev/ttyACM0", "usb", "/dev/cu.usbmodem14101", "COM3"])
    hexf = rng.choice(["firmware.hex", "build/blink.ino.hex", "/tmp/arduino_build_812345/sketch.ino.hex",
                       "main.hex", ".pio/build/uno/firmware.hex"])
    verbose = rng.random() < .45
    ver = rng.choice(["6.3-20171130", "7.0", "7.1", "6.4"])
    if verbose:
        d.line(f"avrdude: Version {ver}", "kv", ["Version", ver])
        d.skip("         Copyright (c) 2000-2005 Brian Dean, http://www.bdmicro.com/")
        d.skip("         Copyright (c) 2007-2014 Joerg Wunsch")
        d.blank()
        conf = rng.choice(["/etc/avrdude.conf", "/usr/local/etc/avrdude.conf",
                           "/home/pi/.arduino15/packages/arduino/tools/avrdude/6.3.0-arduino17/etc/avrdude.conf"])
        d.line(f'         System wide configuration file is "{conf}"', "kv",
               ["System wide configuration file is", f'"{conf}"'])
        if rng.random() < .6:
            u = f"/home/{fake.user(rng)}/.avrduderc"
            d.line(f'         User configuration file is "{u}"', "kv", ["User configuration file is", f'"{u}"'])
            d.line('         User configuration file does not exist or is not a regular file, skipping', "skip")
        d.blank()
        pairs = [("Using Port", port), ("Using Programmer", prog)]
        if prog in ("arduino", "wiring"):
            pairs.append(("Overriding Baud Rate", rng.choice(["115200", "57600", "19200"])))
        pairs += [("AVR Part", part), ("Chip Erase delay", f"{rng.choice([9000, 10500, 4500])} us"),
                  ("PAGEL", rng.choice(["PD7", "P00"])), ("BS2", rng.choice(["PC2", "P00"])),
                  ("RESET disposition", rng.choice(["dedicated", "possible i/o"])),
                  ("RETRY pulse", "SCK"), ("serial program mode", "yes"),
                  ("parallel program mode", rng.choice(["yes", "no"])), ("Timeout", "200"),
                  ("StabDelay", "100"), ("CmdexeDelay", "25"), ("SyncLoops", "32"), ("ByteDelay", "0"),
                  ("PollIndex", "3"), ("PollValue", "0x53")]
        for k, v in pairs:
            d.kv(k, v, sep=" : ", key_width=29, indent="         ")
        d.line("         Memory Detail                 :", "section", ["Memory Detail"])
        d.blank()
        d.line("                                  Block Poll               Page                       Polled",
               "header", ["Block", "Poll", "Page", "Polled"])
        hdr = ["Memory Type", "Mode", "Delay", "Size", "Indx", "Paged", "Size", "Size", "#Pages", "MinW", "MaxW", "ReadBack"]
        d.line("           Memory Type Mode Delay Size  Indx Paged  Size   Size #Pages MinW  MaxW   ReadBack",
               "header", hdr)
        d.skip("           ----------- ---- ----- ----- ---- ------ ------ ---- ------ ----- ----- ---------")
        mems = [("eeprom", 65, rng.choice([20, 10]), 4, 0, "no", eep, 4, 0, 3600, 3600, "0xff 0xff"),
                ("flash", 65, rng.choice([6, 10]), page, 0, "yes", flash, page, flash // page, 4500, 4500, "0xff 0xff")]
        for m, sz in [("lfuse", 1), ("hfuse", 1), ("efuse", 1), ("lock", 1), ("calibration", 1), ("signature", 3)]:
            if m == "efuse" and rng.random() < .2:
                continue
            mems.append((m, 0, 0, 0, 0, "no", sz, 0, 0, 0 if m in ("calibration", "signature") else 4500,
                         0 if m in ("calibration", "signature") else 4500, "0x00 0x00"))
        for m in mems:
            vals = [m[0]] + [str(x) for x in m[1:]]
            text = "           %-11s %4s %5s %5s %4s %-6s %6s %4s %6s %5s %5s %s" % tuple(vals)
            d.line(text, "row", vals)
        d.blank()
        prs = [("Programmer Type", ptype), ("Description", pdesc)]
        if prog in ("arduino", "avrisp2"):
            prs += [("Hardware Version", str(rng.randint(2, 3))), ("Firmware Version", f"{rng.randint(1, 4)}.{rng.randint(0, 9)}")]
            prs += [("Vtarget", f"{rng.choice([0.3, 5.0, 3.3, 4.9])} V"), ("Varef", f"{rng.choice([0.3, 5.0])} V"),
                    ("Oscillator", rng.choice(["28.800 kHz", "Off", "3.686 MHz"])), ("SCK period", f"{rng.choice([3.3, 1.1, 8.7])} us")]
        for k, v in prs:
            d.kv(k, v, sep=": ", key_width=16, indent="         ")
        d.blank()
    d.skip("avrdude: AVR device initialized and ready to accept instructions")
    d.blank()
    bar(d, rng, "Reading")
    d.blank()
    sigv = sig if rng.random() < .85 else "0x000000"
    if sigv == "0x000000":
        d.line(f"avrdude: Device signature = {sigv}", "kv", ["Device signature", sigv])
        d.skip("avrdude: Yikes!  Invalid device signature.")
        d.skip("         Double check connections and try again, or use -F to override")
        d.skip("         this check.")
        d.blank()
        d.skip("avrdude done.  Thank you.")
        return d
    d.line(f"avrdude: Device signature = {sigv} (probably {short})", "kv",
           ["Device signature", f"{sigv} (probably {short})"])
    if verbose and rng.random() < .7:
        lf, hf, ef = (f"{rng.randint(0, 255):02X}" for _ in range(3))
        d.line(f"avrdude: safemode: lfuse reads as {lf}", "kv", ["safemode: lfuse reads as", lf])
        d.line(f"avrdude: safemode: hfuse reads as {hf}", "kv", ["safemode: hfuse reads as", hf])
        d.line(f"avrdude: safemode: efuse reads as {ef}", "kv", ["safemode: efuse reads as", ef])
    mode = rng.choice(["write", "write", "read"])
    if mode == "write":
        if rng.random() < .6:
            d.skip("avrdude: NOTE: \"flash\" memory has been specified, an erase cycle will be performed")
            d.skip("         To disable this feature, specify the -D option.")
            d.skip("avrdude: erasing chip")
        n = rng.randint(400, flash - 512)
        d.skip(f'avrdude: reading input file "{hexf}"')
        d.skip('avrdude: input file %s auto detected as Intel Hex' % hexf)
        d.skip(f"avrdude: writing flash ({n} bytes):")
        d.blank()
        bar(d, rng, "Writing")
        d.blank()
        d.skip(f"avrdude: {n} bytes of flash written")
        if rng.random() < .85:
            d.skip(f"avrdude: verifying flash memory against {hexf}:")
            d.skip(f'avrdude: load data flash data from input file {hexf}:')
            d.skip(f"avrdude: input file {hexf} contains {n} bytes")
            d.skip("avrdude: reading on-chip flash data:")
            d.blank()
            bar(d, rng, "Reading")
            d.blank()
            d.skip("avrdude: verifying ...")
            d.skip(f"avrdude: {n} bytes of flash verified")
    else:
        out = rng.choice(["backup.hex", "dump.bin", "flash.hex"])
        d.skip(f"avrdude: reading flash memory:")
        d.blank()
        bar(d, rng, "Reading")
        d.blank()
        d.skip(f'avrdude: writing output file "{out}"')
    d.blank()
    e, h, l = rng.choice(["FD", "FF", "05"]), rng.choice(["DE", "DA", "D9", "DF"]), rng.choice(["FF", "E2", "62"])
    fs = f"(E:{e}, H:{h}, L:{l})"
    d.line(f"avrdude: safemode: Fuses OK {fs}", "kv", ["safemode", f"Fuses OK {fs}"])
    d.blank()
    d.skip("avrdude done.  Thank you.")
    d.blank()
    return d
