"""`jenkins-cli list-plugins`: a headerless aligned table of short name,
display name (multi-word) and version, with the available update in
parentheses when there is one."""
from lib import Doc

TOOL = "jenkins-cli"

PLUGINS = [
    ("git", "Git plugin"), ("git-client", "Git client plugin"), ("workflow-aggregator", "Pipeline"),
    ("workflow-job", "Pipeline: Job"), ("workflow-cps", "Pipeline: Groovy"),
    ("workflow-step-api", "Pipeline: Step API"), ("workflow-durable-task-step", "Pipeline: Nodes and Processes"),
    ("credentials", "Credentials Plugin"), ("credentials-binding", "Credentials Binding Plugin"),
    ("ssh-credentials", "SSH Credentials Plugin"), ("matrix-auth", "Matrix Authorization Strategy Plugin"),
    ("blueocean", "Blue Ocean"), ("docker-workflow", "Docker Pipeline"), ("kubernetes", "Kubernetes plugin"),
    ("configuration-as-code", "Configuration as Code Plugin"), ("job-dsl", "Job DSL"),
    ("timestamper", "Timestamper"), ("ws-cleanup", "Workspace Cleanup Plugin"), ("ant", "Ant Plugin"),
    ("gradle", "Gradle Plugin"), ("junit", "JUnit Plugin"), ("mailer", "Mailer Plugin"),
    ("email-ext", "Email Extension Plugin"), ("github-branch-source", "GitHub Branch Source Plugin"),
    ("pipeline-stage-view", "Pipeline: Stage View Plugin"), ("ace-editor", "JavaScript GUI Lib: ACE Editor bundle plugin"),
    ("jquery3-api", "JQuery3 API Plugin"), ("bouncycastle-api", "bouncycastle API Plugin"),
    ("script-security", "Script Security Plugin"), ("antisamy-markup-formatter", "OWASP Markup Formatter Plugin"),
    ("build-timeout", "Build Timeout"), ("cloudbees-folder", "Folders Plugin"), ("ldap", "LDAP Plugin"),
    ("pam-auth", "PAM Authentication plugin"), ("role-strategy", "Role-based Authorization Strategy"),
    ("slack", "Slack Notification Plugin"), ("sonar", "SonarQube Scanner for Jenkins"),
    ("warnings-ng", "Warnings Plugin"), ("jacoco", "JaCoCo plugin"), ("lockable-resources", "Lockable Resources plugin"),
    ("trilead-api", "Trilead API Plugin"), ("plain-credentials", "Plain Credentials Plugin"),
]


def version(rng):
    s = rng.random()
    if s < .35:
        return f"{rng.randint(1, 5)}.{rng.randint(0, 40)}" + (f".{rng.randint(0, 9)}" if rng.random() < .5 else "")
    if s < .7:
        return f"{rng.randint(100, 1400)}.v{''.join(rng.choice('0123456789abcdef') for _ in range(rng.randint(6, 12)))}"
    if s < .85:
        return f"{rng.randint(2, 4)}.{rng.randint(100, 2600)}.v{rng.randint(1, 9)}{rng.choice('abcdef')}{rng.randint(10, 99)}_{rng.randint(1000, 9999)}"
    return f"{rng.randint(1, 3)}.{rng.randint(0, 99)}-{rng.randint(1, 400)}.v{rng.choice('abcdef')}{rng.randint(100, 999)}"


def generate(rng):
    d = Doc()
    rows = []
    for name, disp in rng.sample(PLUGINS, rng.randint(3, 30)):
        v = version(rng)
        upd = f"({version(rng)})" if rng.random() < .25 else None
        rows.append((name, disp, v, upd))
    if rng.random() < .5:
        rows.sort()
    w0 = max(len(r[0]) for r in rows) + 1
    w1 = max(len(r[1]) for r in rows) + 1
    for name, disp, v, upd in rows:
        text = name.ljust(w0) + disp.ljust(w1) + v + (" " + upd if upd else "")
        d.line(text, "row", [name, disp, v] + ([upd] if upd else []))
    return d
