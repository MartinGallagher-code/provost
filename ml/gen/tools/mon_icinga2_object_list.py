"""`icinga2 object list [--type T]`: one block per object, headed
`Object 'name' of type 'Type':`, with `% declared in ...` provenance comments
and `* attr = value` lines; dictionary attributes nest one level deeper."""
from lib import Doc, fake

TOOL = "icinga2-object-list"

CONF = ["/etc/icinga2/conf.d/hosts.conf", "/etc/icinga2/conf.d/services.conf", "/etc/icinga2/zones.d/master/{w}.conf",
        "/usr/share/icinga2/include/command-plugins.conf", "/etc/icinga2/conf.d/templates.conf",
        "/etc/icinga2/conf.d/{w}/{w}.conf"]


def _where(rng):
    f = rng.choice(CONF).format(w=fake.word(rng))
    a = rng.randint(1, 400)
    return f"'{f}', lines {a}:1-{a + rng.randint(0, 30)}:{rng.randint(1, 3)}"


def _q(s):
    return f'"{s}"'


def _attrs(rng, typ, name, host):
    a = []
    if typ == "Host":
        a += [("__name", _q(name)), ("action_url", _q("")), ("address", _q(fake.ip(rng))),
              ("address6", _q(fake.ip(rng, True) if rng.random() < .3 else "")),
              ("check_command", _q(rng.choice(["hostalive", "ping4", "dummy"]))),
              ("check_interval", str(rng.choice([60, 300]))), ("display_name", _q(name)),
              ("enable_active_checks", "true"), ("enable_notifications", rng.choice(["true", "false"])),
              ("groups", "[ " + ", ".join(_q(g) for g in rng.sample(["linux-servers", "web", "db", "dc1", "prod"], rng.randint(0, 3))) + " ]"),
              ("max_check_attempts", str(rng.choice([3, 5]))), ("name", _q(name)),
              ("retry_interval", str(rng.choice([30, 60]))),
              ("templates", "[ " + ", ".join(_q(t) for t in [name, "generic-host"]) + " ]"),
              ("type", _q("Host"))]
    elif typ == "Service":
        cmd = rng.choice(["ping4", "disk", "load", "procs", "http", "ssh", "swap", "users", "apt", "ntp_time"])
        a += [("__name", _q(name)), ("action_url", _q("")),
              ("check_command", _q(cmd)), ("check_interval", str(rng.choice([60, 300, 600]))),
              ("check_period", _q("")), ("display_name", _q(name.split("!")[1])),
              ("enable_flapping", "false"), ("enable_perfdata", "true"),
              ("groups", "[ ]" if rng.random() < .5 else f'[ "{cmd}" ]'), ("host_name", _q(host)),
              ("max_check_attempts", str(rng.choice([3, 5]))), ("name", _q(name.split("!")[1])),
              ("retry_interval", str(rng.choice([30, 60]))), ("templates", '[ "generic-service" ]'),
              ("type", _q("Service"))]
    elif typ == "CheckCommand":
        a += [("__name", _q(name)), ("command", f'[ "/usr/lib/nagios/plugins/check_{name}" ]'),
              ("env", "null"), ("execute", "PluginCheck"), ("name", _q(name)),
              ("templates", f'[ "{name}", "plugin-check-command" ]'), ("timeout", str(rng.choice([60, 30]))),
              ("type", _q("CheckCommand"))]
    else:  # Zone / Endpoint / User
        a += [("__name", _q(name)), ("name", _q(name)), ("type", _q(typ))]
        if typ == "Endpoint":
            a += [("host", _q(fake.ip(rng))), ("log_duration", str(86400)), ("port", _q("5665"))]
        elif typ == "Zone":
            a += [("endpoints", f'[ "{fake.host(rng)}" ]'), ("global", rng.choice(["true", "false"])),
                  ("parent", _q(rng.choice(["", "master"])))]
        else:
            a += [("email", _q(f"{fake.user(rng)}@example.com")), ("enable_notifications", "true"),
                  ("groups", '[ "icingaadmins" ]')]
    a += [("zone", _q(rng.choice(["", "", "master", fake.word(rng)])))]
    a.sort(key=lambda kv: kv[0])
    return a


def _vars(rng, typ):
    if typ == "Host":
        return [("os", _q(rng.choice(["Linux", "Windows", "FreeBSD"]))),
                ("http_vhosts", None), ("disks", None), ("notification", None)][:rng.randint(1, 4)]
    if typ == "Service":
        return [("sla", _q(rng.choice(["24x7", "workhours"]))),
                ("disk_wfree", _q(f"{rng.randint(10, 25)}%")), ("disk_cfree", _q(f"{rng.randint(3, 9)}%"))][:rng.randint(1, 3)]
    return []


def generate(rng):
    d = Doc()
    typ = rng.choice(["Host", "Service", "Service", "CheckCommand", "Zone", "Endpoint", "User"])
    hosts = [fake.host(rng).split(".")[0] for _ in range(4)]
    for i in range(rng.randint(1, 4)):
        if i:
            d.blank()
        host = rng.choice(hosts)
        name = {"Host": host, "Service": f"{host}!{rng.choice(['ping4', 'disk /', 'load', 'ssh', 'http', 'procs', 'swap'])}",
                "CheckCommand": rng.choice(["disk", "load", "ping4", "http", "ssh", "procs", "mysql", "pgsql"]),
                "Zone": rng.choice(["master", "global-templates", "director-global", fake.word(rng)]),
                "Endpoint": fake.host(rng), "User": fake.user(rng)}[typ]
        head = f"Object '{name}' of type '{typ}':"
        d.section(head, f"Object '{name}' of type '{typ}'")
        d.skip(f"  % declared in {_where(rng)}")
        for k, v in _attrs(rng, typ, name, host):
            d.line(f"  * {k} = {v}", "kv", [k, v])
            if rng.random() < .12:
                d.skip(f"    % = modified in {_where(rng)}")
        vs = _vars(rng, typ)
        if vs:
            d.section("  * vars", "vars")
            for k, v in vs:
                if v is None:
                    d.section(f"    * {k}", k)
                    for _ in range(rng.randint(1, 2)):
                        sub = rng.choice(["/", "/var", "/home", fake.word(rng)])
                        d.section(f"      * {sub}", sub)
                        d.line(f"        * disk_partitions = {_q(sub)}", "kv", ["disk_partitions", _q(sub)])
                else:
                    d.line(f"    * {k} = {v}", "kv", [k, v])
                if rng.random() < .3:
                    d.skip(f"      % = modified in {_where(rng)}")
    if rng.random() < .5:
        d.blank()
    return d
