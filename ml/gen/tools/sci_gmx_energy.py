"""GROMACS `gmx energy`: the `:-) GROMACS (-:` banner, Executable/Data
prefix kvs, the numbered energy-term menu (pairs of number + name per row),
`Statistics over ...` lines and the Average/Err.Est./RMSD/Tot-Drift table
whose last, unnamed column is the unit."""
from lib import Doc, fake

TOOL = "gmx-energy"

TERMS = ["Bond", "Angle", "Proper-Dih.", "Ryckaert-Bell.", "Improper-Dih.", "LJ-14", "Coulomb-14", "LJ-(SR)",
         "Disper.-corr.", "Coulomb-(SR)", "Coul.-recip.", "Position-Rest.", "Potential", "Kinetic-En.", "Total-Energy",
         "Conserved-En.", "Temperature", "Pres.-DC", "Pressure", "Constr.-rmsd", "Box-X", "Box-Y", "Box-Z", "Volume",
         "Density", "pV", "Enthalpy", "Vir-XX", "Vir-XY", "Vir-XZ", "Vir-YX", "Vir-YY", "Vir-YZ", "Vir-ZX", "Vir-ZY",
         "Vir-ZZ", "Pres-XX", "Pres-XY", "Pres-XZ", "Pres-YX", "Pres-YY", "Pres-YZ", "Pres-ZX", "Pres-ZY", "Pres-ZZ",
         "#Surf*SurfTen", "Box-Vel-XX", "Box-Vel-YY", "Box-Vel-ZZ", "T-Protein", "T-non-Protein", "T-System",
         "Lamb-Protein", "Lamb-non-Protein", "Lamb-System"]

UNITS = {"Temperature": ("K", 300, 2), "Pressure": ("bar", 1, 150), "Pres.-DC": ("bar", -150, 5),
         "Density": ("kg/m^3", 1010, 3), "Volume": ("nm^3", 250, 2), "Box-X": ("nm", 6.5, 0.02),
         "Box-Y": ("nm", 6.5, 0.02), "Box-Z": ("nm", 6.5, 0.02), "Constr.-rmsd": ("", 3e-6, 1e-7),
         "pV": ("kJ/mol", 15, 0.5), "T-Protein": ("K", 300, 2), "T-non-Protein": ("K", 300, 1.5),
         "T-System": ("K", 300, 1.6)}


def _g(x):
    return f"{x:g}"


def generate(rng):
    d = Doc()
    ver = rng.choice(["2019.6", "2020.4", "2021.5", "2022.3", "2023.3", "2024.1", "2018.8"])
    d.skip(" " * 22 + f":-) GROMACS - gmx energy, {ver} (-:")
    d.blank()
    if rng.random() < 0.6:
        d.skip(f"                            GROMACS is written by:")
        d.skip("     Andrey Alekseenko              Emile Apol              Rossen Apostolov     ")
        d.skip("and the project leaders:")
        d.skip("        Mark Abraham, Berk Hess, Erik Lindahl, and David van der Spoel")
        d.blank()
    prefix = rng.choice(["/usr/local/gromacs", "/opt/gromacs/" + ver, "/apps/gromacs/" + ver + "-gcc-cuda",
                         "/sw/eb/software/GROMACS/" + ver + "-foss-2022a"])
    pairs = [("Executable", prefix + "/bin/gmx" + rng.choice(["", "", "_mpi"])), ("Data prefix", prefix),
             ("Working dir", f"/scratch/{rng.choice(fake.USERS[1:7])}/{rng.choice(['md', 'lysozyme', 'membrane', 'run1', 'prod'])}")]
    d.kvs(pairs)
    edr = rng.choice(["ener.edr", "md.edr", "npt.edr", "nvt.edr", "prod_0.edr"])
    d.section("Command line:")
    cmd = f"gmx energy -f {edr}" + rng.choice(["", " -o energy.xvg", " -o potential.xvg", " -b 100 -e 1000"])
    d.line("  " + cmd, "row", [cmd])
    d.blank()
    if rng.random() < 0.3:
        d.skip(f"Back Off! I just backed up energy.xvg to ./#energy.xvg.{rng.randint(1, 9)}#")
    d.skip(f"Opened {edr} as {rng.choice(['single', 'single', 'double'])} precision energy file")
    d.blank()
    d.skip("Select the terms you want from the following list by")
    d.skip("selecting either (part of) the name or the number or a combination.")
    d.skip("End your selection with an empty line or a zero.")
    d.skip("-" * 67)
    pool = TERMS[:rng.randint(26, len(TERMS))]
    if rng.random() < 0.5:
        pool = [t for t in pool if t not in ("Position-Rest.", "Improper-Dih.", "Ryckaert-Bell.")]
    for i in range(0, len(pool), 4):
        chunk = pool[i:i + 4]
        text, cells = "", []
        for j, name in enumerate(chunk):
            num = i + j + 1
            text += f"{num:3d}  {name:<15}" if j < len(chunk) - 1 else f"{num:3d}  {name}"
            cells += [str(num), name]
        d.line(text, "row", cells)
    d.blank()
    chosen = rng.sample([t for t in pool if not t.startswith(("Vir", "Pres-", "Box-Vel", "Lamb", "#"))], rng.randint(1, 6))
    chosen.sort(key=pool.index)
    nfr = rng.randint(50, 50001)
    tend = nfr * rng.choice([2, 10, 20, 100]) / 1000.0 * rng.choice([1, 10])
    d.skip(f"Last energy frame read {nfr - 1} time {tend:.3f}         ")
    d.blank()
    steps = int(tend / 0.002)
    d.line(f"Statistics over {steps + 1} steps [ 0.0000 through {tend:.4f} ps ], {len(chosen)} data sets",
           "kv", ["Statistics over", f"{steps + 1} steps", f"[ 0.0000 through {tend:.4f} ps ]", f"{len(chosen)} data sets"])
    d.line(f"All statistics are over {nfr} points", "kv", ["All statistics are over", f"{nfr} points"])
    d.blank()
    hdr = ["Energy", "Average", "Err.Est.", "RMSD", "Tot-Drift", None]
    d.line(f"{'Energy':<24}{'Average':>11}{'Err.Est.':>11}{'RMSD':>11}{'Tot-Drift':>11}", "header", hdr)
    d.skip("-" * 79)
    for t in chosen:
        unit, mu, sd = UNITS.get(t, ("kJ/mol", rng.choice([-1, 1]) * 10 ** rng.uniform(2, 6), 0))
        if not sd:
            sd = abs(mu) * rng.uniform(0.001, 0.02)
        avg = mu * rng.uniform(0.98, 1.02) if mu else rng.uniform(-1, 1)
        err = "--" if rng.random() < 0.1 else _g(round(sd * rng.uniform(0.01, 0.5), 3) or 0.001)
        rmsd = _g(sd * rng.uniform(0.8, 1.2))
        drift = _g(sd * rng.uniform(-3, 3))
        vals = [t, _g(round(avg, 6)), err, rmsd, drift]
        text = f"{vals[0]:<24}{vals[1]:>11}{vals[2]:>11}{vals[3]:>11}{vals[4]:>11}"
        u = f"({unit})" if unit else None
        if u:
            text += f"  {u}"
        d.line(text, "row", vals + [u])
    d.blank()
    quote, who = rng.choice([("I Was Born to Have Adventure", "F. Zappa"), ("Everything's Under Control", "Pulp Fiction"),
                             ("It's Not Your Fault", "Good Will Hunting"), ("Disturb the Peace", "Unknown")])
    d.skip(f'GROMACS reminds you: "{quote}" ({who})')
    return d
