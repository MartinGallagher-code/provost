"""coinmon: cryptocurrency prices in a cli-table3 box (unicode rules, a
header row, one row per coin), optionally in another fiat currency (-c)."""
from lib import Doc

TOOL = "coinmon"

COINS = ["BTC", "ETH", "USDT", "BNB", "SOL", "XRP", "USDC", "ADA", "DOGE", "TRX", "AVAX", "DOT",
         "LINK", "MATIC", "LTC", "BCH", "XLM", "ATOM", "XMR", "ETC", "FIL", "NEAR", "APT", "ARB"]


def money(rng, v):
    if v >= 1e9:
        return f"{v / 1e9:,.2f} B"
    if v >= 1e6:
        return f"{v / 1e6:,.2f} M"
    return f"{v:,.0f}"


def generate(rng):
    d = Doc()
    cur = rng.choice(["USD", "USD", "USD", "EUR", "GBP", "JPY", "AUD"])
    sym = {"USD": "$", "EUR": "€", "GBP": "£", "JPY": "¥", "AUD": "A$"}[cur]
    vol = rng.random() < 0.5
    n = rng.randint(3, 15)
    top = rng.random() < 0.6
    coins = COINS[:n] if top else rng.sample(COINS, n)
    hdr = ["Rank", "Coin", f"Price ({cur})", "Change 24H"] + (["Change 1H"] if rng.random() < .3 else []) + ["Market Cap", "Supply"] + (["Volume 24H"] if vol else [])
    rows = []
    for i, c in enumerate(coins):
        price = rng.choice([rng.uniform(0.05, 2), rng.uniform(2, 500), rng.uniform(500, 70000)])
        cap = 10 ** rng.uniform(8, 12.2)
        supply = cap / price
        r = [str(i + 1 if top else COINS.index(c) + 1), c,
             f"{price:.2f}" if price > 1 else f"{price:.4f}", f"{rng.uniform(-15, 15):.2f}%"]
        if "Change 1H" in hdr:
            r.append(f"{rng.uniform(-3, 3):.2f}%")
        r += [sym + money(rng, cap), f"{supply:,.0f}"]
        if vol:
            r.append(sym + money(rng, rng.uniform(1e5, 3e10)))
        rows.append(r)
    rows.sort(key=lambda r: int(r[0]))
    w = [max(len(x) for x in col) for col in zip(hdr, *rows)]

    def line(cells):
        return "│" + "│".join(" " + c.ljust(wi) + " " for c, wi in zip(cells, w)) + "│"

    def rule(l, m, r):
        return l + m.join("─" * (wi + 2) for wi in w) + r

    if rng.random() < 0.3:
        d.skip("✔ Data fetched")
    d.skip(rule("┌", "┬", "┐"))
    d.line(line(hdr), "header", hdr)
    d.skip(rule("├", "┼", "┤"))
    for r in rows:
        d.line(line(r), "row", r)
    d.skip(rule("└", "┴", "┘"))
    return d
