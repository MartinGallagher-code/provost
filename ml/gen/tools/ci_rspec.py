"""`rspec --format documentation`: an indented tree of example groups and
examples (with `(FAILED - 1)` / `(PENDING: ...)` marks), then Pending and
Failures detail blocks, the Finished-in timing, the examples/failures count
line and the `rspec ./spec/...:12 # ...` rerun list."""
from lib import Doc, fake

TOOL = "rspec"

SUBJECTS = ["User", "Order", "Invoice", "Cart", "PaymentGateway", "Api::V1::PostsController",
            "SessionsController", "Slugger", "ReportMailer", "InventoryJob", "Subscription", "Coupon"]
METHODS = ["#full_name", "#total", ".search", "#valid?", "#refund!", "GET /index", "POST /create",
           "#to_param", "#deliver", ".perform", "#expired?", "#apply"]
CONTEXTS = ["when the user is an admin", "with an expired token", "when empty", "validations",
            "associations", "with valid params", "with invalid params", "when the cart has items",
            "scopes", "callbacks"]
EXAMPLES = ["returns the first and last name", "is valid with valid attributes", "requires an email",
            "returns http success", "renders the index template", "raises an error",
            "creates a new record", "does not create a record", "sends one email", "is expected to eq 42",
            "enqueues the job", "applies a 10% discount", "returns nil", "belongs to account",
            "is expected to validate that :name cannot be empty/falsy", "redirects to the login page"]


def generate(rng):
    d = Doc()
    seed = str(rng.randint(1000, 65535))
    randomized = rng.random() < .5
    if randomized:
        d.kv("Randomized with seed", seed, sep=" ")
        d.blank()
    failed, pending = [], []
    for _ in range(rng.randint(1, 4)):
        subj = rng.choice(SUBJECTS)
        d.section(subj)
        for _ in range(rng.randint(1, 3)):
            groups = [rng.choice(METHODS)]
            if rng.random() < .5:
                groups.append(rng.choice(CONTEXTS))
            for depth, g in enumerate(groups, 1):
                d.section("  " * depth + g, g)
            ind = "  " * (len(groups) + 1)
            for ex in rng.sample(EXAMPLES, rng.randint(1, 4)):
                full = " ".join([subj] + groups + [ex]).replace(" #", "#").replace(" .", ".")
                r = rng.random()
                loc = f"./spec/{rng.choice(['models', 'requests', 'services', 'jobs', 'mailers'])}/" \
                      f"{subj.lower().replace('::', '/')}_spec.rb:{rng.randint(3, 240)}"
                if r < .08:
                    failed.append((full, loc))
                    mark = f"(FAILED - {len(failed)})"
                    d.line(f"{ind}{ex} {mark}", "row", [ex, mark])
                elif r < .14:
                    why = rng.choice(["Not yet implemented", "waiting on API v2", "flaky on CI", "Temporarily skipped with xit"])
                    pending.append((full, why, loc))
                    mark = f"(PENDING: {why})"
                    d.line(f"{ind}{ex} {mark}", "row", [ex, mark])
                else:
                    d.line(ind + ex, "row", [ex])
        d.blank()
    n = sum(1 for lab in d.labels if lab["role"] == "row")
    if pending:
        d.line("Pending: (Failures listed here are expected and do not affect your suite's status)",
               "section", ["Pending"])
        d.blank()
        for k, (full, why, loc) in enumerate(pending, 1):
            d.line(f"  {k}) {full}", "row", [str(k), full])
            d.skip(f"     # {why}")
            d.skip(f"     # {loc}")
            d.blank()
    if failed:
        d.section("Failures:")
        d.blank()
        for k, (full, loc) in enumerate(failed, 1):
            d.line(f"  {k}) {full}", "row", [str(k), full])
            expr = rng.choice(["expect(user.full_name).to eq(\"Ada Lovelace\")", "expect(response).to have_http_status(:ok)",
                               "expect { subject }.to change(Order, :count).by(1)", "expect(total).to eq(42)"])
            d.kv("Failure/Error", expr, indent="     ")
            if rng.random() < .7:
                exp, got = rng.choice([("\"Ada Lovelace\"", "\"Ada  Lovelace\""), ("42", "41"), ("200", "302"), ("1", "0")])
                d.line(f"       expected: {exp}", "kv", ["expected", exp])
                d.line(f"            got: {got}", "kv", ["got", got])
                d.blank()
                d.skip("       (compared using ==)")
            else:
                d.skip(f"       expected `Order.count` to have changed by 1, but was changed by 0")
            d.skip(f"     # {loc}:in `block ({rng.randint(2, 4)} levels) in <top (required)>'")
            d.blank()
    t = f"{rng.uniform(0.01, 300):.{rng.choice([2, 4, 5])}f}"
    load = f"{rng.uniform(0.2, 12):.{rng.choice([2, 3])}f}"
    tval = f"{t} seconds" if float(t) < 60 else f"{int(float(t)) // 60} minutes {float(t) % 60:.2f} seconds"
    d.line(f"Finished in {tval} (files took {load} seconds to load)", "kv",
           ["Finished in", tval, f"files took {load} seconds to load"])
    parts = [f"{n} example{'s' if n != 1 else ''}", f"{len(failed)} failure{'s' if len(failed) != 1 else ''}"]
    if pending:
        parts.append(f"{len(pending)} pending")
    d.line(", ".join(parts), "row", parts)
    if failed:
        d.blank()
        d.section("Failed examples:")
        d.blank()
        for full, loc in failed:
            cmd = f"rspec {loc}"
            d.line(f"{cmd} # {full}", "row", [cmd, full])
    if randomized:
        d.blank()
        d.kv("Randomized with seed", seed, sep=" ")
        d.blank()
    return d
