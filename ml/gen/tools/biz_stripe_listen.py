"""Stripe CLI `stripe listen --forward-to URL`: a Ready banner with the
webhook signing secret, then one fixed-layout line per event received
(`-->  type [evt_id]`) and per forwarded response (`<--  [status] METHOD url
[evt_id]`)."""
import string

from lib import Doc

TOOL = "stripe-listen"

EVENTS = ["customer.created", "customer.updated", "payment_intent.created", "payment_intent.succeeded",
          "payment_intent.payment_failed", "charge.succeeded", "charge.refunded", "invoice.created",
          "invoice.finalized", "invoice.paid", "invoice.payment_failed", "checkout.session.completed",
          "customer.subscription.created", "customer.subscription.updated", "payment_method.attached",
          "invoice.upcoming", "price.created", "product.updated"]


def rid(rng, n=24):
    return "".join(rng.choice(string.ascii_letters + string.digits) for _ in range(n))


def generate(rng):
    d = Doc()
    url = rng.choice(["http://localhost:4242/webhook", "localhost:3000/api/webhooks/stripe",
                      "http://127.0.0.1:8000/stripe/webhook/", "https://localhost:5001/webhooks"])
    if not url.startswith("http"):
        url = "http://" + url
    fwd = rng.random() < 0.8
    d.skip(f"> Ready! You are using Stripe API Version [{rng.choice(['2020-08-27', '2022-11-15', '2023-10-16', '2024-06-20'])}]. "
           f"Your webhook signing secret is whsec_{rid(rng, 32).lower()} (^C to quit)")
    y, mo, dd = rng.randint(2020, 2026), rng.randint(1, 12), rng.randint(1, 28)
    t = rng.randint(0, 86000)
    for _ in range(rng.randint(2, 12)):
        t += rng.choice([0, 0, 1, 1, 2, 5, 30, 120])
        ts = f"{y}-{mo:02d}-{dd:02d} {t // 3600 % 24:02d}:{t // 60 % 60:02d}:{t % 60:02d}"
        ev = rng.choice(EVENTS)
        eid = f"[evt_{rid(rng)}]"
        d.line(f"{ts}   --> {ev} {eid}", "row", [ts, ev, eid])
        if fwd:
            t += rng.choice([0, 0, 1])
            ts = f"{y}-{mo:02d}-{dd:02d} {t // 3600 % 24:02d}:{t // 60 % 60:02d}:{t % 60:02d}"
            st = rng.choice(["200", "200", "200", "200", "204", "400", "500", "404"])
            if rng.random() < 0.05:
                msg = f"[ERROR] Failed to POST: Post \"{url}\": dial tcp 127.0.0.1:{url.split(':')[-1].split('/')[0]}: connect: connection refused"
                d.line(f"{ts}            {msg}", "row", [ts, "[ERROR]", msg[len("[ERROR] "):]])
            else:
                d.line(f"{ts}  <--  [{st}] POST {url} {eid}", "row", [ts, f"[{st}]", "POST", url, eid])
    return d
