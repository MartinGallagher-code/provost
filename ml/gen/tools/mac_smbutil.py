"""macOS `smbutil statshares -a`: `=` ruled header, a share-name row followed
by attribute rows whose first column is empty, `-` rules between shares."""
from lib import Doc, fake

TOOL = "smbutil-statshares"

W = 30


def generate(rng):
    d = Doc()
    rule = "=" * 98
    d.blank()
    d.skip(rule)
    d.line(f"{'SHARE':<{W}}{'ATTRIBUTE TYPE':<{W}}VALUE", "header", ["SHARE", "ATTRIBUTE TYPE", "VALUE"])
    d.skip(rule)
    nshares = rng.randint(1, 3)
    for s in range(nshares):
        share = rng.choice(["Public", "homes", "Time Machine", "media", "scans", "alice", "Projects 2024", "IPC$", "backup"])
        server = rng.choice([f"{fake.word(rng)}-nas._smb._tcp.local", fake.host(rng), fake.ip(rng), "DS920PLUS"])
        d.line(f"{share:<{W}}", "row", [share, None, None])
        ver = rng.choice(["SMB_3.1.1", "SMB_3.0.2", "SMB_3.0", "SMB_2.1", "SMB_2.002"])
        attrs = [("SERVER_NAME", server), ("USER_ID", str(rng.choice([501, 502, 503, 1026])))]
        for neg in rng.sample(["SMBV_NEG_SMB1_ENABLED", "SMBV_NEG_SMB2_ENABLED", "SMBV_NEG_SMB3_ENABLED"], rng.randint(1, 3)):
            attrs.append(("SMB_NEGOTIATE", neg))
        attrs.append(("SMB_VERSION", ver))
        if ver.startswith("SMB_3"):
            attrs.append(("SMB_ENCRYPT_ALGORITHMS", rng.choice(["AES_128_CCM_ENABLED", "AES_128_GCM_ENABLED"])))
            for extra in rng.sample(["AES_256_CCM_ENABLED", "AES_256_GCM_ENABLED"], rng.randint(0, 2)):
                attrs.append(("SMB_ENCRYPT_ALGORITHMS", extra))
            attrs.append(("SMB_CURR_ENCRYPT_ALGORITHM", rng.choice(["OFF", "OFF", "AES-128-GCM"])))
            if rng.random() < .5:
                attrs.append(("SMB_SIGN_ALGORITHMS", "AES_128_CMAC_ENABLED"))
                attrs.append(("SMB_CURR_SIGN_ALGORITHM", rng.choice(["AES_128_GMAC", "AES_128_CMAC"])))
        attrs.append(("SMB_SHARE_TYPE", "PIPE" if share == "IPC$" else "DISK"))
        for flag in ["SIGNING_SUPPORTED", "EXTENDED_SECURITY_SUPPORTED", "UNIX_SUPPORT", "LARGE_FILE_SUPPORTED",
                     "OS_X_SERVER", "QUERYINFO_NOT_SUPPORTED", "FILE_IDS_SUPPORTED", "DFS_SUPPORTED",
                     "FILE_LEASING_SUPPORTED", "MULTI_CREDIT_SUPPORTED", "ENCRYPTION_REQUIRED", "MULTI_CHANNEL_SUPPORTED"]:
            if rng.random() < .7:
                attrs.append((flag, "TRUE"))
        if rng.random() < .6:
            attrs.append(("SESSION_RECONNECT_TIME", f"{rng.randint(0, 3)}:{rng.randint(0, 59)}"))
            attrs.append(("SESSION_RECONNECT_COUNT", str(rng.randint(0, 9))))
        for k, v in attrs:
            d.line(f"{'':<{W}}{k:<{W}}{v}", "row", [None, k, v])
        d.blank()
        d.skip("-" * 98)
    return d
