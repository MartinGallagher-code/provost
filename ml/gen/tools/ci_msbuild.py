"""`msbuild` / `dotnet msbuild -clp:PerformanceSummary`: version banner,
`Project -> output.dll` lines and compiler warnings, then the Project
Evaluation / Project / Target / Task Performance Summary sections (headerless
`  123 ms  Name   2 calls` tables), Build succeeded/FAILED with Warning(s) and
Error(s) counts, and Time Elapsed."""
from lib import Doc

TOOL = "msbuild"

PROJECTS = ["Contoso.Core", "Contoso.Api", "Contoso.Web", "Contoso.Data", "Contoso.Tests", "Fabrikam.Shared",
            "Fabrikam.Worker", "Tools.Migrator", "Northwind.Domain", "Northwind.Infrastructure"]
TARGETS = ["_CheckForInvalidConfigurationAndPlatform", "ResolveAssemblyReferences", "CoreCompile",
           "_CopyFilesMarkedCopyLocal", "GenerateBuildDependencyFile", "ResolvePackageAssets",
           "IncrementalClean", "CopyFilesToOutputDirectory", "_HandlePackageFileConflicts",
           "GenerateTargetFrameworkMonikerAttribute", "ResolveTargetingPackAssets", "Restore",
           "_GenerateRestoreProjectPathWalk", "GetCopyToOutputDirectoryItems", "Build", "PrepareForBuild"]
TASKS = ["Csc", "Copy", "ResolveAssemblyReference", "ResolvePackageAssets", "Message", "MakeDir",
         "GenerateDepsFile", "WriteLinesToFile", "AssignTargetPath", "Delete", "MSBuild", "Touch",
         "ResolvePackageFileConflicts", "FindUnderPath", "RestoreTask", "CallTarget"]
WARNS = [("CS0168", "The variable 'ex' is declared but never used"),
         ("CS8618", "Non-nullable property 'Name' must contain a non-null value when exiting constructor. Consider declaring the property as nullable."),
         ("CS1998", "This async method lacks 'await' operators and will run synchronously."),
         ("NU1603", "Contoso.Api depends on Serilog (>= 3.0.0) but Serilog 3.0.0 was not found. An approximate best match of Serilog 3.0.1 was resolved."),
         ("CS0618", "'WebClient.WebClient()' is obsolete: 'WebRequest, HttpWebRequest, ServicePoint, and WebClient are obsolete. Use HttpClient instead.'"),
         ("MSB3277", "Found conflicts between different versions of \"System.Text.Json\" that could not be resolved.")]


def perf(rng, d, title, names, w, indent=""):
    d.section(title)
    rows = []
    for n in rng.sample(names, rng.randint(2, min(len(names), 12))):
        rows.append((rng.choice([0, 0, rng.randint(0, 20), rng.randint(0, 900), rng.randint(100, 20000)]), n,
                     rng.choice([1, 1, 2, 3, 4, 8, 12, 40])))
    rows.sort()
    nw = max(len(r[1]) for r in rows) + rng.randint(1, 4)
    for ms, n, calls in rows:
        a, c = f"{ms} ms", f"{calls} calls"
        d.line(f"{indent}{a.rjust(w)}  {n.ljust(nw)}{c.rjust(9)}", "row", [a, n, c])
    d.blank()


def generate(rng):
    d = Doc()
    root = rng.choice(["/src", "/home/runner/work/contoso/contoso", "C:\\agent\\_work\\1\\s", "/builds/team/app"])
    win = root.startswith("C:")
    sep = "\\" if win else "/"
    tfm = rng.choice(["net6.0", "net8.0", "net8.0", "netstandard2.0", "net48"])
    cfg = rng.choice(["Debug", "Release"])
    if rng.random() < .6:
        d.skip(f"MSBuild version 17.{rng.randint(3, 11)}.{rng.randint(0, 9)}+{''.join(rng.choice('0123456789abcdef') for _ in range(9))} for .NET")
    else:
        d.skip(f"Microsoft (R) Build Engine version 16.{rng.randint(8, 11)}.0+{''.join(rng.choice('0123456789abcdef') for _ in range(9))} for .NET")
        d.skip("Copyright (C) Microsoft Corporation. All rights reserved.")
        d.blank()
    d.skip("  Determining projects to restore...")
    projs = rng.sample(PROJECTS, rng.randint(1, 6))
    if rng.random() < .5:
        d.skip("  All projects are up-to-date for restore.")
    else:
        for p in projs[:rng.randint(1, len(projs))]:
            t = f"{rng.randint(80, 9000)} ms" if rng.random() < .7 else f"{rng.uniform(1, 30):.2f} sec"
            d.skip(f"  Restored {root}{sep}{p}{sep}{p}.csproj (in {t}).")
    warns = []
    failed = rng.random() < .15
    for p in projs:
        proj = f"{root}{sep}{p}{sep}{p}.csproj"
        for _ in range(rng.choice([0, 0, 0, 1, 2])):
            code, msg = rng.choice(WARNS)
            loc = f"{root}{sep}{p}{sep}{rng.choice(['Program', 'Startup', 'Services' + sep + 'OrderService', 'Models' + sep + 'User'])}.cs({rng.randint(1, 400)},{rng.randint(1, 60)})"
            warns.append((loc, "warning", code, msg, f"[{proj}]"))
            d.line(f"{loc}: warning {code}: {msg} [{proj}]", "row", [loc, "warning", code, msg, f"[{proj}]"])
        if failed and p == projs[-1]:
            loc = f"{root}{sep}{p}{sep}Program.cs({rng.randint(1, 99)},{rng.randint(1, 40)})"
            err = (loc, "error", "CS1002", "; expected", f"[{proj}]")
            d.line(f"{loc}: error CS1002: ; expected [{proj}]", "row", list(err))
            continue
        out = f"{root}{sep}{p}{sep}bin{sep}{cfg}{sep}{tfm}{sep}{p}.dll"
        d.line(f"  {p} -> {out}", "row", [p, out])
    d.blank()
    if rng.random() < .75:
        w = rng.choice([8, 9, 10])
        perf(rng, d, "Project Evaluation Performance Summary:",
             [f"{root}{sep}{p}{sep}{p}.csproj" for p in projs] + [f"{root}{sep}{projs[0].split('.')[0]}.sln"], w)
        if rng.random() < .5:
            perf(rng, d, "Project Performance Summary:",
                 [f"{root}{sep}{p}{sep}{p}.csproj" for p in projs] + [f"{root}{sep}{projs[0].split('.')[0]}.sln"], w)
        perf(rng, d, "Target Performance Summary:", TARGETS, w)
        perf(rng, d, "Task Performance Summary:", TASKS, w)
    if failed:
        d.skip("Build FAILED.")
    else:
        d.skip("Build succeeded.")
    if warns or failed:
        d.blank()
    for wrn in warns:
        d.line(f"{wrn[0]}: warning {wrn[2]}: {wrn[3]} {wrn[4]}", "row", list(wrn))
    if failed:
        d.line(f"{err[0]}: error CS1002: ; expected {err[4]}", "row", list(err))
    nw = f"{len(warns)} Warning(s)"
    ne = f"{1 if failed else 0} Error(s)"
    d.line("    " + nw, "row", [nw])
    d.line("    " + ne, "row", [ne])
    d.blank()
    h, m, s = 0, rng.randint(0, 9), rng.uniform(0, 59.99)
    el = f"{h:02d}:{m:02d}:{s:05.2f}"
    d.kv("Time Elapsed", el, sep=" ")
    return d
