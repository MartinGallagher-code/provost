"""Drush `drush status` / `drush core:status`: ` Key   : value` lines, with
multi-path values wrapped onto indented continuation lines."""
from lib import Doc, fake

TOOL = "drush-status"


def generate(rng):
    d = Doc()
    root = rng.choice(["/var/www/html", "/var/www/drupal", "/srv/" + fake.word(rng), "/app"])
    web = root + rng.choice(["/web", "/docroot", ""])
    php = rng.choice(["8.1", "8.2", "8.3"])
    dbup = rng.random() < .85
    major = rng.choice([9, 10, 10, 11])
    pairs = [
        ("Drupal version", f"{major}.{rng.randint(0, 3)}.{rng.randint(0, 12)}"),
        ("Site URI", rng.choice(["http://default", f"https://{fake.word(rng)}.example.com", "http://localhost"])),
        ("DB driver", rng.choice(["mysql", "mysql", "pgsql", "sqlite"])),
        ("DB hostname", rng.choice(["localhost", "127.0.0.1", "db", "mariadb", fake.host(rng)])),
        ("DB port", rng.choice(["3306", "5432", "3307"])),
        ("DB username", rng.choice(["drupal", "root", "db", fake.word(rng)])),
        ("DB name", rng.choice(["drupal", "drupal" + str(major), "db", fake.word(rng) + "_prod"])),
    ]
    if dbup:
        pairs += [("Database", "Connected"), ("Drupal bootstrap", "Successful"),
                  ("Default theme", rng.choice(["olivero", "bartik", "gin", fake.word(rng) + "_theme"])),
                  ("Admin theme", rng.choice(["claro", "seven", "gin"]))]
    pairs += [
        ("PHP binary", f"/usr/bin/php{php}"),
        ("PHP config", f"/etc/php/{php}/cli/php.ini"),
        ("PHP OS", rng.choice(["Linux", "Linux", "Darwin"])),
    ]
    if rng.random() < .6:
        pairs.append(("PHP version", f"{php}.{rng.randint(0, 25)}"))
    pairs += [
        ("Drush script", f"{root}/vendor/bin/drush"),
        ("Drush version", f"{rng.choice([11, 12, 13])}.{rng.randint(0, 6)}.{rng.randint(0, 9)}"),
        ("Drush temp", rng.choice(["/tmp", "/var/tmp"])),
        ("Drush configs", [f"{root}/vendor/drush/drush/drush.yml"] + ([f"{root}/drush/drush.yml"] if rng.random() < .6 else [])
                          + ([f"/home/{fake.user(rng)}/.drush/drush.yml"] if rng.random() < .3 else [])),
    ]
    if dbup:
        pairs.append(("Install profile", rng.choice(["standard", "minimal", "demo_umami", "config_installer"])))
    pairs += [("Drupal root", web), ("Site path", "sites/default"), ("Files, Public", "sites/default/files"),
              ("Files, Private", rng.choice(["", "../private", "/var/private"])), ("Files, Temp", "/tmp")]
    if rng.random() < .3:
        pairs.append(("Drupal Settings", f"{web}/sites/default/settings.php"))
    w = max(len(k) for k, _ in pairs) + rng.choice([1, 1, 2])
    for k, v in pairs:
        if k == "Files, Private" and not v:
            if rng.random() < .5:
                continue
            d.line(" " + k.ljust(w) + ":", "kv", [k])
            continue
        vals = v if isinstance(v, list) else [v]
        d.line(" " + k.ljust(w) + ": " + vals[0], "kv", [k, vals[0]])
        for extra in vals[1:]:
            d.line(" " * (w + 3) + extra, "cont", [extra])
    return d
