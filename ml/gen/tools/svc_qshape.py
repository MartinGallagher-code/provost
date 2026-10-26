"""Postfix `qshape`: queue age histogram per recipient (or sender) domain,
an unnamed right-aligned domain column, a TOTAL row, bucket columns."""
from lib import Doc, fake

TOOL = "qshape"

DOMAINS = ("gmail.com yahoo.com hotmail.com outlook.com aol.com icloud.com example.com example.org "
           "mail.ru yandex.ru gmx.de web.de comcast.net verizon.net qq.com 163.com protonmail.com "
           "btinternet.com orange.fr free.fr libero.it shaw.ca bigpond.com").split()


def generate(rng):
    d = Doc()
    t = rng.choice([5, 5, 5, 1, 10, 15, 60])
    nb = rng.randint(6, 11)
    buckets = [str(t * 2 ** i) for i in range(nb - 1)]
    buckets = buckets + [buckets[-1] + "+"]
    header = [None, "T"] + buckets
    ndom = rng.randint(1, 14)
    doms = rng.sample(DOMAINS, min(ndom, len(DOMAINS)))
    if rng.random() < 0.3:
        doms.append(f"{fake.word(rng)}-{rng.choice(['mail', 'mx', 'smtp'])}.{rng.choice(['co.uk', 'com.au', 'net', 'io'])}")
    rows = []
    totals = [0] * nb
    for dm in doms:
        if rng.random() < 0.5:
            counts = [rng.choice([0, 0, 0, 1, 2]) for _ in range(nb)]
        else:
            counts = [rng.choice([0, rng.randint(0, 40), rng.randint(0, 900)]) for _ in range(nb)]
        if not any(counts):
            counts[rng.randrange(nb)] = rng.randint(1, 30)
        rows.append([dm, str(sum(counts))] + [str(c) for c in counts])
        totals = [a + b for a, b in zip(totals, counts)]
    rows.sort(key=lambda r: -int(r[1]))
    rows = [["TOTAL", str(sum(totals))] + [str(c) for c in totals]] + rows
    if rng.random() < 0.3:
        d.skip(rng.choice(["# postqueue -p | qshape -s", "# qshape deferred", "# qshape -s hold"]))
    d.table(header, rows, gap=1, right=tuple(range(nb + 2)))
    return d
