"""WP-CLI `wp plugin list` (default table format, optional --fields)."""
from lib import Doc, fake

TOOL = "wp-plugin-list"

PLUGINS = ["akismet", "hello", "jetpack", "wordpress-seo", "woocommerce", "contact-form-7", "elementor",
           "classic-editor", "wordfence", "updraftplus", "wp-super-cache", "w3-total-cache", "redirection",
           "all-in-one-wp-migration", "advanced-custom-fields", "wpforms-lite", "litespeed-cache", "really-simple-ssl",
           "duplicate-post", "tinymce-advanced", "regenerate-thumbnails", "query-monitor", "wp-mail-smtp",
           "google-site-kit", "mailchimp-for-wp", "limit-login-attempts-reloaded", "redis-cache", "wp-graphql",
           "sucuri-scanner", "broken-link-checker", "the-events-calendar", "polylang", "safe-svg"]


def generate(rng):
    d = Doc()
    fields = ["name", "status", "update", "version"]
    extra = rng.random()
    if extra < .25:
        fields = ["name", "status", "update", "version", "update_version", "auto_update"]
    elif extra < .4:
        fields = ["name", "title", "status", "version"]
    elif extra < .5:
        fields = ["name", "status", "version", "update_version", "auto_update"]
    rows = []
    for name in sorted(rng.sample(PLUGINS, rng.randint(1, 14))):
        st = rng.choice(["active", "active", "active", "inactive", "inactive", "must-use", "dropin", "active-network"])
        ver = fake.version(rng) if rng.random() < .8 else f"{rng.randint(1, 9)}.{rng.randint(0, 9)}"
        if st == "dropin":
            name = rng.choice(["object-cache.php", "advanced-cache.php", "db.php"])
            ver = rng.choice(["", ver])
        upd = rng.choice(["none", "none", "none", "available", "version higher than expected"] if st != "dropin" else ["none"])
        uv = fake.version(rng) if upd == "available" else ""
        vals = {"name": name, "status": st, "update": upd, "version": ver, "update_version": uv,
                "auto_update": rng.choice(["off", "off", "on"]),
                "title": " ".join(w.capitalize() for w in name.replace(".php", "").split("-"))}
        rows.append([vals[f] for f in fields])
    d.pipe_table(fields, rows)
    if rng.random() < .15:
        d.line(f"Warning: {rng.randint(1, 4)} plugin(s) have updates available.", "skip")
    return d
