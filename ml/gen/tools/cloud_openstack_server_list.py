"""OpenStack `openstack server list` (and --long): a +---+ bordered pipe table with
networks like `private=10.0.0.5, 172.24.4.9` and booted-from-volume image cells."""
from lib import Doc, fake

TOOL = "openstack-server-list"


def generate(rng):
    d = Doc()
    long = rng.random() < .35
    hdr = ["ID", "Name", "Status"] + (["Task State", "Power State"] if long else []) + ["Networks", "Image", "Flavor"]
    if long:
        hdr += ["Availability Zone", "Host", "Properties"]
    rows = []
    for _ in range(rng.randint(1, 10)):
        st = rng.choice(["ACTIVE", "ACTIVE", "ACTIVE", "SHUTOFF", "ERROR", "BUILD", "PAUSED"])
        nets = "; ".join(f"{rng.choice(['private', 'public', 'shared', fake.word(rng) + '-net'])}="
                         + ", ".join(fake.ip(rng, v6=rng.random() < .15) for _ in range(rng.choice([1, 1, 2])))
                         for _ in range(rng.choice([0, 1, 1, 1, 2])))
        img = rng.choice(["cirros-0.6.2-x86_64-disk", "ubuntu-22.04", "Ubuntu 20.04 LTS", "centos-stream-9",
                          "N/A (booted from volume)", "debian-12-genericcloud-amd64", ""])
        flav = rng.choice(["m1.tiny", "m1.small", "m1.medium", "m1.large", "ds2G", "c2.xlarge", "gp1.supersonic"])
        r = [fake.uuid(rng), rng.choice([fake.name(rng), fake.word(rng) + str(rng.randint(1, 9))]), st]
        if long:
            r += [{"BUILD": "spawning", "ERROR": None}.get(st, rng.choice([None] * 6 + ["deleting", "powering-off"])),
                  {"ACTIVE": "Running", "SHUTOFF": "Shutdown", "PAUSED": "Paused"}.get(st, "NOSTATE")]
        r += [nets or None, img or None, flav]
        if long:
            r += [rng.choice(["nova", "az1", "zone-a"]), rng.choice([fake.host(rng), "compute-0" + str(rng.randint(1, 9))]),
                  rng.choice([None, None, "role='web'", f"env='{rng.choice(['prod', 'dev'])}', owner='{fake.user(rng)}'"])]
        rows.append(r)
    d.pipe_table(hdr, rows)
    return d
