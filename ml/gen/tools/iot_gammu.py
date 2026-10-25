"""Gammu (GSM modem tool): `gammu identify`, `gammu monitor N` and
`gammu getallsms`: `Key  : value` reports padded to 20/32 columns, banners,
message headings and free-text SMS bodies."""
from lib import Doc, fake

TOOL = "gammu"

MODEMS = [("Huawei", "E3531 (E3531)", "22.521.23.00.00"), ("Huawei", "E173 (E173)", "11.126.85.00.209"),
          ("ZTE CORPORATION", "MF190 (MF190)", "BD_TMOP673A2V1.0.0B04"),
          ("Sierra Wireless, Incorporated", "MC7710 (MC7710)", "SWI9200X_03.05.29.02ap"),
          ("Quectel", "EC25 (EC25)", "EC25EFAR06A06M4G"), ("SIMCOM INCORPORATED", "SIM800 R14.18 (SIM800)", "1418B04SIM800C24")]
NETS = [("234 10", "O2 (UK)", "United Kingdom", "O2 - UK"), ("234 15", "Vodafone", "United Kingdom", "voda UK"),
        ("262 01", "Telekom.de", "Germany", "Telekom.de"), ("310 260", "T-Mobile", "United States", "T-Mobile"),
        ("208 01", "Orange", "France", "Orange F")]
BODIES = ["Your balance is GBP5.00. Top up now at the store.", "Code 482913 is your verification code.",
          "ALARM zone 3 triggered", "Reminder: your appointment is tomorrow at 10:30.",
          "Sensor 12 battery low (3.41V)", "OK", "You have used 80% of your data allowance."]


def kv(d, k, v, w=20):
    d.line(f"{k.ljust(w)} : {v}", "kv", [k, v])


def identify(d, rng):
    man, model, fw = rng.choice(MODEMS)
    kv(d, "Device", rng.choice(["/dev/ttyUSB0", "/dev/ttyUSB2", "/dev/ttyACM0", "/dev/serial0"]))
    kv(d, "Manufacturer", man)
    kv(d, "Model", model)
    kv(d, "Firmware", fw)
    if rng.random() < .4:
        kv(d, "Hardware", rng.choice(["CD6ATCPU", "MC7710", "R1C"]))
    imei = "".join(rng.choice("0123456789") for _ in range(15))
    kv(d, "IMEI", imei)
    if rng.random() < .3:
        kv(d, "Original IMEI", imei)
    if rng.random() < .3:
        kv(d, "Product code", rng.choice(["NPL-1", "RH-12", "E173"]))
    kv(d, "SIM IMSI", "".join(rng.choice("0123456789") for _ in range(15)))


def monitor(d, rng):
    d.skip("Press Ctrl+C to break...")
    d.skip("Entering monitor mode...")
    d.blank()
    for k in ["Enabling info about incoming SMS", "Enabling info about incoming CB",
              "Enabling info about calls", "Enabling info about USSD"]:
        kv(d, k, rng.choice(["No error.", "No error.", "Function not supported by phone."]), 32)
    code, opn, country, short = rng.choice(NETS)
    for _ in range(rng.randint(1, 3)):
        for k, tot in [("SIM phonebook", 250), ("Dialled numbers", 10), ("Received numbers", 10),
                       ("Missed numbers", 10), ("Own numbers", 2), ("Phone phonebook", 500)]:
            if rng.random() < .25:
                continue
            u = rng.randint(0, tot // 3)
            kv(d, k, f"{u:3d} used, {tot - u:3d} free")
        if rng.random() < .7:
            kv(d, "Battery level", f"{rng.choice([100, 100, 0, rng.randint(1, 99)])} percent")
            kv(d, "Charge state", rng.choice(["powered from AC", "battery connected and is being charged",
                                              "battery connected, but not powered"]))
        kv(d, "Signal strength", f"{rng.randint(-113, -51)} dBm")
        kv(d, "Network level", f"{rng.randint(0, 100)} percent")
        kv(d, "SIM SMS status", f"{rng.randint(0, 30)} used, {rng.randint(0, 3)} unread, {rng.choice([10, 20, 30, 50])} locations")
        if rng.random() < .5:
            kv(d, "Phone SMS status", f"0 used, 0 unread, {rng.choice([0, 255, 23])} locations")
        kv(d, "Network state", rng.choice(["home network", "roaming network", "requesting network",
                                           "not logged into network"]))
        lac, cid = f"{rng.randint(0, 65535):04X}", f"{rng.randint(0, 268435455):08X}"
        kv(d, "Network", f"{code} ({opn}, {country}), LAC {lac}, CID {cid}")
        kv(d, "Name in phone", f'"{short}"')
        if rng.random() < .3:
            kv(d, "Packet network state", rng.choice(["home network", "not logged into network"]))
            kv(d, "Packet network", f"{code} ({opn}, {country}), LAC {lac}, CID {cid}")
        d.blank()
    d.skip("Leaving monitor mode...")


def getallsms(d, rng):
    n = rng.randint(1, 5)
    for i in range(n):
        folder = rng.choice([("Inbox", "Inbox folder"), ("Outbox", "Outbox folder"), ("Inbox", "Inbox folder")])
        mem = rng.choice(["SIM memory", "phone memory"])
        head = f'Location {i + 1}, folder "{folder[0]}", {mem}, {folder[1]}'
        d.line(head, "section", [head])
        d.skip("SMS message")
        smsc = "+44" + "".join(rng.choice("0123456789") for _ in range(10))
        kv(d, "SMSC number", f'"{smsc}"')
        when = fake.date(rng, "datetime")
        y, rest = when.split("-", 1)
        mon = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()[int(rest[:2]) - 1]
        day = rng.choice("Mon Tue Wed Thu Fri Sat Sun".split())
        sent = f"{day} {rest[3:5]} {mon} {y} {when[11:]}  {rng.choice(['+0000', '+0100', '-0500'])}"
        kv(d, "Sent", sent)
        kv(d, "Coding", rng.choice(["Default GSM alphabet (no compression)", "Unicode (no compression)",
                                    "8-bit"]))
        num = rng.choice(["+447700900" + fake.num(rng, 100, 999), "O2", "+15550100" + fake.num(rng, 10, 99), "Vodafone"])
        kv(d, "Remote number", f'"{num}"')
        kv(d, "Status", rng.choice(["Read", "UnRead", "Sent", "UnSent"]))
        if rng.random() < .25:
            kv(d, "User Data Header", rng.choice(["Concatenated (linked) message, ID (8 bit) 172, part 1 of 2",
                                                  "Concatenated (linked) message, ID (16 bit) 3021, part 2 of 2"]))
        d.blank()
        d.skip(rng.choice(BODIES))
        d.blank()
    d.blank()
    d.skip(f"{n} SMS parts in {n} SMS sequences")


def generate(rng):
    d = Doc()
    rng.choice([identify, monitor, getallsms])(d, rng)
    return d
