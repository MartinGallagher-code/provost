"""AWS Elastic Beanstalk `eb status` (optionally --verbose): an 'Environment details
for:' line, then indented key: value lines, with per-instance lines in verbose mode."""
from lib import Doc, fake

TOOL = "eb-status"

PLATFORMS = ["Python 3.8 running on 64bit Amazon Linux 2/3.3.13",
             "Node.js 18 running on 64bit Amazon Linux 2023/6.0.2",
             "Docker running on 64bit Amazon Linux 2/3.6.0",
             "PHP 8.1 running on 64bit Amazon Linux 2/3.5.4",
             "Corretto 17 running on 64bit Amazon Linux 2023/4.1.0"]


def generate(rng):
    d = Doc()
    app = fake.name(rng)
    env = f"{app}-{rng.choice(['prod', 'dev', 'staging', 'env'])}"
    region = rng.choice(["us-east-1", "us-west-2", "eu-west-1", "ap-southeast-2", "eu-central-1"])
    d.line(f"Environment details for: {env}", "kv", ["Environment details for", env])
    y, mo, dd = rng.randint(2019, 2026), rng.randint(1, 12), rng.randint(1, 28)
    ver = rng.choice([f"app-{y % 100:02d}{mo:02d}{dd:02d}_{rng.randint(0, 235959):06d}",
                      f"app-{fake.hexid(rng, 7)}-{y % 100:02d}{mo:02d}{dd:02d}_{rng.randint(0, 235959):06d}",
                      "Sample Application", f"v{fake.version(rng)}"])
    status = rng.choice(["Ready", "Ready", "Updating", "Launching", "Terminating"])
    health = rng.choice(["Green", "Green", "Yellow", "Red", "Grey"])
    pairs = [("Application name", app), ("Region", region), ("Deployed Version", ver),
             ("Environment ID", "e-" + fake.token(rng, 10)),
             ("Platform", f"arn:aws:elasticbeanstalk:{region}::platform/{rng.choice(PLATFORMS)}"),
             ("Tier", rng.choice(["WebServer-Standard-1.0", "WebServer-Standard-1.0", "Worker-SQS/HTTP-1.0"])),
             ("CNAME", rng.choice([f"{env}.eba-{fake.token(rng, 8)}.{region}.elasticbeanstalk.com", "UNKNOWN"])),
             ("Updated", f"{fake.date(rng, 'datetime')}.{rng.randint(0, 999999):06d}+00:00"),
             ("Status", status), ("Health", health)]
    for k, v in pairs:
        d.kv(k, v, indent="  ")
    if rng.random() < .55:
        n = rng.randint(1, 5)
        d.kv("Running instances", str(n), indent="  ")
        for _ in range(n):
            iid = "i-0" + fake.hexid(rng, 16)
            d.kv(iid, rng.choice(["InService", "InService", "InService", "OutOfService", "Pending"]), indent="     ")
        if rng.random() < .6:
            d.kv("Current CPU Utilization", f"{rng.uniform(0, 100):.1f}%", indent="  ")
    return d
