#!/usr/bin/env python3
"""Compile complete actual sources with fail-closed synthetic boundaries."""
import hashlib
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("root", nargs="?", default=".")
parser.add_argument("--expect-baseline", action="store_true")
args = parser.parse_args()
root = Path(args.root).resolve()
here = Path(__file__).resolve().parent
plugin = root / "photos-v2"
sdk = plugin / "4D Plugin API"
sources = [sdk / "4DPluginAPI.c", *sorted((sdk / "Classes").glob("*.cpp")),
           plugin / "4DPlugin.cpp", here / "main.mm"]
protected = {
    "4DPluginAPI.c": "478081f0238f6bc5393222f574bc2656f010b67b",
    "4DPluginAPI.h": "9054b45ffc7ff6f5b8d57529a3788a55d977b314",
    "4DPluginAPI.def": "996ecc4ab11ad165de9192eba2e7478db141c757",
    "EntryPoints.h": "730f2f77ff2713fb2fe4b7d6562baeedf5f664cb",
    "Flags.h": "10a83185333dac06a62dda61b9f9428243d1e2ee",
    "PrivateTypes.h": "77053dc0c0a3718d2d3b6f158371a6af78c6ae66",
    "PublicTypes.h": "2bb392e73e9c556c274fe0a75b3a6b83e310b77c",
    "licence.txt": "e6af14f72d6e5e9bde3eab35d18f5f23823e46a2",
}
for name, blob in protected.items():
    data = (sdk / name).read_bytes()
    actual = hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()
    if actual != blob:
        raise RuntimeError("protected SDK changed: " + name)
for path in sorted(sdk.rglob("*")) + sorted((plugin / "v11/4D Plugin API").rglob("*")) + [
        plugin / "4DPlugin.cpp", plugin / "manifest.json"]:
    if path.is_file():
        print(hashlib.sha256(path.read_bytes()).hexdigest(), path.relative_to(root), flush=True)
for path in sorted(here.rglob("*")):
    if path.is_file():
        print(hashlib.sha256(path.read_bytes()).hexdigest(), path.relative_to(here), flush=True)

with tempfile.TemporaryDirectory(prefix="photos-v2-ownership-") as directory:
    out = Path(directory)
    flags = [
        "-g", "-O1", "-fsanitize=address,undefined", "-fno-sanitize=alignment",
        "-fno-omit-frame-pointer", "-Wno-deprecated-declarations", "-Wno-multichar",
        "-Wno-deprecated-builtins", "-Wno-incompatible-pointer-types",
        "-I" + str(here), "-I" + str(plugin), "-I" + str(sdk), "-I" + str(sdk / "Classes"),
        "-include", str(here / "Carbon/Carbon.h"),
        "-x", "objective-c++", "-std=c++14",
    ]
    objects = []
    for i, source in enumerate(sources):
        obj = out / (str(i) + ".o")
        subprocess.run(["clang++", *flags, "-c", str(source), "-o", str(obj)], check=True)
        objects.append(str(obj))
    exe = out / "ownership"
    subprocess.run(["clang++", "-fsanitize=address,undefined", *objects,
                    "-framework", "Foundation", "-framework", "CoreFoundation",
                    "-o", str(exe)], check=True)
    linked = subprocess.check_output(["otool", "-L", str(exe)], text=True)
    if any(name in linked for name in ("ScriptingBridge", "AppKit", "Carbon.framework", "Photos.framework")):
        raise RuntimeError("real platform boundary linked")
    imports = subprocess.check_output(["nm", "-u", str(exe)], text=True)
    exact = {
        "_abort", "_calloc", "_free", "_malloc", "_realloc", "_memcmp", "_memcpy",
        "_memmove", "_memset", "_strlen", "_strcmp", "_isspace", "_sprintf", "_snprintf",
        "_printf", "_fprintf", "_fwrite", "_puts", "_exit", "_atexit", "_bzero",
        "dyld_stub_binder", "__Unwind_Resume", "__tlv_bootstrap", "_memchr",
        "_kCFAllocatorDefault", "_CFRelease", "_CFStringCreateWithBytes",
        "_CFStringCreateWithCharacters", "_CFStringGetLength", "_CFStringGetCharacters",
        "_CFStringGetMaximumSizeForEncoding", "_CFStringGetBytes",
        "_NSZeroSize", "__DefaultRuneLocale",
        "__objc_empty_cache",
    }
    allowed_classes = {"NSObject", "NSString", "NSMutableString", "NSArray", "NSAutoreleasePool"}
    unexpected = []
    for symbol in (line.strip() for line in imports.splitlines() if line.strip()):
        if any(name in symbol for name in ("fstream", "filebuf", "filesystem", "random_device")):
            raise RuntimeError("external data import: " + symbol)
        if symbol.startswith("_OBJC_CLASS_$_") and symbol.split("$_", 1)[1] in allowed_classes:
            continue
        if symbol in exact or symbol.startswith(("___", "__Z", "_objc_", "_OBJC_METACLASS_$_NSObject")):
            continue
        unexpected.append(symbol)
    if unexpected:
        raise RuntimeError("unexpected imports before execution: " + repr(unexpected))
    print("PASS pre-execution synthetic boundary/import gate", flush=True)
    env = dict(os.environ, ASAN_OPTIONS="detect_leaks=0:abort_on_error=1",
               UBSAN_OPTIONS="halt_on_error=1")
    cases = subprocess.check_output([str(exe), "--list"], env=env, text=True).splitlines()
    expected = json.loads((here / "baseline.json").read_text()) if args.expect_baseline else None
    if expected is not None and set(cases) != set(expected):
        raise RuntimeError("baseline case inventory changed")
    results = {}
    mismatches = []
    for case in cases:
        print("CASE", case, flush=True)
        probe = subprocess.run([str(exe), case], env=env, text=True, capture_output=True)
        print(probe.stdout, end="", flush=True)
        print(probe.stderr, end="", file=sys.stderr, flush=True)
        results[case] = probe.returncode
        if expected is not None:
            contract = expected[case]
            output = probe.stdout + probe.stderr
            if probe.returncode != contract["exit_code"] or any(
                    signature not in output for signature in contract["signatures"]):
                mismatches.append(case)
    print("case_exit_codes=" + repr(results), flush=True)
    print(f"TOTAL {len(results)} PASS {sum(code == 0 for code in results.values())} "
          f"FAIL {sum(code != 0 for code in results.values())}", flush=True)
    if expected is not None:
        print("BASELINE expectation mismatches=" + repr(mismatches), flush=True)
        sys.exit(1 if mismatches else 0)
    sys.exit(1 if any(results.values()) else 0)
