"""ISC `dhcp-lease-list`: banner lines, a fixed-width printf table (MAC, IP,
hostname truncated to 14, valid until, manufacturer) under a `===` rule;
or `--parsable` key/value lines."""
from lib import Doc, fake

TOOL = "dhcp-lease-list"

VENDORS = ["Apple, Inc.", "Dell Inc.", "Raspberry Pi Foundation", "Intel Corporate", "Samsung Electronics Co.,Ltd",
           "HUAWEI TECHNOLOGIES CO.,LTD", "Hewlett Packard", "Espressif Inc.", "Super Micro Computer, Inc.",
           "Ubiquiti Networks Inc.", "Sonos, Inc.", "Brother Industries, LTD.", "Amazon Technologies Inc.",
           "Google, Inc.", "Xiaomi Communications Co Ltd", "TP-LINK TECHNOLOGIES CO.,LTD."]
HOSTS = ["laptop", "printer", "android-8f3c2a1b9d0e4f57", "iPhone", "DESKTOP-4KQ7J2M", "raspberrypi", "nas",
         "ESP_3A2B1C", "living-room-tv", "Galaxy-S21", "MacBook-Pro", "camera-front-door", "kitchen-echo",
         "build-server-01", "thermostat", "wlan0"]


def generate(rng):
    d = Doc()
    oui = rng.random() < 0.5
    parsable = rng.random() < 0.25
    leases = rng.choice(["/var/lib/dhcp/dhcpd.leases", "/var/lib/dhcpd/dhcpd.leases", "/var/db/dhcpd.leases"])
    if not oui:
        d.skip("To get manufacturer names please download http://standards.ieee.org/regauth/oui/oui.txt "
               "to /usr/local/etc/oui.txt")
    d.skip(f"Reading leases from {leases}")
    rows = []
    for _ in range(rng.randint(1, 16)):
        mac = fake.mac(rng)
        ip = f"{rng.choice(['192.168.1', '192.168.0', '10.0.0', '172.16.5'])}.{rng.randint(2, 254)}"
        h = rng.choice(HOSTS + ["-NA-"])
        y, m, dd = rng.randint(2022, 2026), rng.randint(1, 12), rng.randint(1, 28)
        valid = f"{y}-{m:02d}-{dd:02d} {rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d}"
        man = rng.choice(VENDORS) if oui else "-NA-"
        rows.append((mac, ip, h, valid, man))
    rows.sort(key=lambda r: tuple(int(x) for x in r[1].split(".")))
    if parsable:
        for mac, ip, h, valid, man in rows:
            text = f"MAC {mac} IP {ip} HOSTNAME {h} BEGIN {valid} END {valid} MANUFACTURER {man}"
            d.line(text, "row", ["MAC", mac, "IP", ip, "HOSTNAME", h, "BEGIN", valid, "END", valid,
                                 "MANUFACTURER", man])
        return d
    d.line("%-19s%-16s%-15s%-20s%-20s" % ("MAC", "IP", "hostname", "valid until", "manufacturer"), "header",
           ["MAC", "IP", "hostname", "valid until", "manufacturer"])
    d.skip("=" * 95)
    for mac, ip, h, valid, man in rows:
        h14 = h[:14]
        text = "%-19s%-16s%-14.14s %-20s%-20s" % (mac, ip, h, valid, man)
        d.line(text, "row", [mac, ip, h14, valid, man])
    return d
