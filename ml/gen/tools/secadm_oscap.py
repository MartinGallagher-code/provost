"""OpenSCAP `oscap xccdf eval`: optional warnings, the `--- Starting
Evaluation ---` banner, then one Title/Rule/Ident/Result block per rule
(tab-separated), blocks separated by blank lines."""
from lib import Doc

TOOL = "oscap"

RULES = [("Ensure /tmp Located On Separate Partition", "partition_for_tmp"),
         ("Ensure /var/log Located On Separate Partition", "partition_for_var_log"),
         ("Set Password Maximum Age", "accounts_maximum_age_login_defs"),
         ("Set Password Minimum Length in login.defs", "accounts_password_minlen_login_defs"),
         ("Disable SSH Root Login", "sshd_disable_root_login"),
         ("Set SSH Idle Timeout Interval", "sshd_set_idle_timeout"),
         ("Ensure auditd Collects File Deletion Events by User", "audit_rules_file_deletion_events"),
         ("Enable auditd Service", "service_auditd_enabled"),
         ("Install AIDE", "package_aide_installed"),
         ("Configure Periodic Execution of AIDE", "aide_periodic_cron_checking"),
         ("Ensure SELinux State is Enforcing", "selinux_state"),
         ("Configure SELinux Policy", "selinux_policytype"),
         ("Verify Permissions on /etc/shadow File", "file_permissions_etc_shadow"),
         ("Verify Group Who Owns passwd File", "file_groupowner_etc_passwd"),
         ("Disable Ctrl-Alt-Del Reboot Activation", "disable_ctrlaltdel_reboot"),
         ("Enable Kernel Parameter to Enforce DAC on Hardlinks", "sysctl_fs_protected_hardlinks"),
         ("Disable Kernel Parameter for IP Forwarding on IPv4 Interfaces", "sysctl_net_ipv4_ip_forward"),
         ("Ensure gpgcheck Enabled In Main yum Configuration", "ensure_gpgcheck_globally_activated"),
         ("Remove the Kerberos Server Package", "package_krb5-server_removed"),
         ("Uninstall telnet-server Package", "package_telnet-server_removed"),
         ("Configure Multiple DNS Servers in /etc/resolv.conf", "network_configure_name_resolution"),
         ("Lock Accounts After Failed Password Attempts", "accounts_passwords_pam_faillock_deny"),
         ("Ensure PAM Enforces Password Requirements - Minimum Uppercase Characters", "accounts_password_pam_ucredit"),
         ("Record Attempts to Alter Logon and Logout Events - faillock", "audit_rules_login_events_faillock"),
         ("Ensure rsyslog is Installed", "package_rsyslog_installed")]
RESULTS = ["pass"] * 6 + ["fail"] * 3 + ["notapplicable", "notchecked", "error", "informational", "fixed"]


def generate(rng):
    d = Doc()
    if rng.random() < .3:
        d.skip("WARNING: Datastream component 'scap_org.open-scap_cref_security-data-oval-com.redhat.rhsa-RHEL8.xml.bz2' "
               "points out to the remote 'https://access.redhat.com/security/data/oval/com.redhat.rhsa-RHEL8.xml.bz2'. "
               "Use '--fetch-remote-resources' option to download it.")
        d.skip("WARNING: Skipping 'https://access.redhat.com/security/data/oval/com.redhat.rhsa-RHEL8.xml.bz2' file "
               "which is referenced from datastream")
    if rng.random() < .8:
        d.skip("--- Starting Evaluation ---")
        d.blank()
    sep = "\t"
    rules = rng.sample(RULES, rng.randint(2, 12))
    for i, (title, rid) in enumerate(rules):
        if i:
            d.blank()
        d.kv("Title", title, sep=sep)
        d.kv("Rule", "xccdf_org.ssgproject.content_rule_" + rid, sep=sep)
        for _ in range(rng.choice([0, 1, 1, 1, 2])):
            ident = rng.choice([f"CCE-{rng.randint(80000, 90999)}-{rng.randint(0, 9)}",
                                f"CCE-{rng.randint(26000, 27999)}-{rng.randint(0, 9)}"])
            d.kv("Ident", ident, sep=sep)
        d.kv("Result", rng.choice(RESULTS), sep=sep)
    return d
