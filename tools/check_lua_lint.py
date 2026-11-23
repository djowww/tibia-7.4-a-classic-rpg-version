#!/usr/bin/env python3
"""Luacheck gate for the server Lua scripts.

Reports only what breaks at run time and cannot be seen by a syntax check:
reads of names that nothing defines (typos, missing helpers) and scripts that
create globals other than their event callbacks, which silently overwrite
same-named globals of every other script in the same Lua state.

The set of valid globals is derived on every run from the C++ registrations in
src/luascript.cpp and from the Lua libraries, so new API needs no list upkeep.
"""
import argparse
import json
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
BASELINE = ROOT / "tests" / "lua-lint-baseline.json"
SHARED_LIBRARIES = ("global.lua", "lib")
CPP_PATTERNS = (
    r'registerClass\(\s*"(\w+)"',
    r'registerTable\(\s*"(\w+)"',
    r'registerGlobalMethod\(\s*"(\w+)"',
    r'registerGlobalVariable\(\s*"(\w+)"',
    r'registerGlobalBoolean\(\s*"(\w+)"',
    r'luaL_register\(\s*\w+\s*,\s*"(\w+)"',
    r'lua_register\(\s*\w+\s*,\s*"(\w+)"',
    r'lua_setglobal\(\s*\w+\s*,\s*"(\w+)"',
    r'registerEnum\(\s*(\w+)\s*\)',
)
WARNING = re.compile(r"^(?P<file>.+?):(?P<line>\d+):\d+: \((?P<code>[EW]\d+)\) (?P<text>.*)$")
NAME = re.compile(r"'([^']+)'")
# Event entry points looked up by the server after loading each script.
CALLBACK = re.compile(r"^(on[A-Z]\w*|canJoin)$")


def cpp_globals():
    names = set()
    for source in sorted((ROOT / "src").glob("*.cpp")):
        text = source.read_text(encoding="utf-8", errors="replace")
        for pattern in CPP_PATTERNS:
            names.update(re.findall(pattern, text))
    return names


def luacheck(executable, paths, extra):
    if not paths:
        return []
    command = [executable, "--no-color", "--codes", "--formatter", "plain", "--no-config",
               "--std", "luajit", "--no-max-line-length", *extra, "--", *[str(path) for path in paths]]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)
    if result.returncode not in (0, 1, 2):
        raise SystemExit(f"luacheck failed ({result.returncode}): {result.stderr.strip()}")
    findings = []
    for line in result.stdout.splitlines():
        match = WARNING.match(line)
        # Syntax errors (E0xx) are left to the LuaJIT parse step of the CI,
        # which knows the files that are bare table constructors.
        if match and match.group("code").startswith("W"):
            findings.append(match.groupdict())
    return findings


def defined_globals(executable, paths):
    """Names assigned at global scope by the given library files."""
    names = set()
    for finding in luacheck(executable, paths, ["--only", "111", "112", "131"]):
        match = NAME.search(finding["text"])
        if match:
            names.add(match.group(1).split(".")[0])
    return names


def relative(path):
    path = pathlib.Path(path)
    if not path.is_absolute():
        path = ROOT / path
    return path.resolve().relative_to(ROOT).as_posix()


def lua_files(path):
    if path.is_file():
        return [path] if path.suffix == ".lua" else []
    return sorted(path.rglob("*.lua")) if path.is_dir() else []


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luacheck", default="luacheck")
    parser.add_argument("--update-baseline", action="store_true",
                        help="rewrite the baseline with the current findings")
    args = parser.parse_args()
    executable = shutil.which(args.luacheck)
    if not executable:
        raise SystemExit("luacheck was not found; install it (apt install lua-check)")

    shared = [file for name in SHARED_LIBRARIES for file in lua_files(DATA / name)]
    base = cpp_globals() | defined_globals(executable, shared)

    findings = []
    for system in sorted(path for path in DATA.iterdir() if (path / "scripts").is_dir()):
        libraries = lua_files(system / "lib")
        known = base | defined_globals(executable, libraries)
        extra = ["--only", "111", "112", "113", "--globals", *sorted(known)]
        for finding in luacheck(executable, lua_files(system / "scripts"), extra):
            name = NAME.search(finding["text"])
            name = name.group(1) if name else ""
            if finding["code"] == "W111" and CALLBACK.match(name):
                continue
            findings.append({"file": relative(finding["file"]), "code": finding["code"],
                             "name": name, "line": int(finding["line"]), "text": finding["text"]})
        for finding in luacheck(executable, libraries, ["--only", "113", "--globals", *sorted(known)]):
            name = NAME.search(finding["text"])
            findings.append({"file": relative(finding["file"]), "code": finding["code"],
                             "name": name.group(1) if name else "", "line": int(finding["line"]),
                             "text": finding["text"]})
    for finding in luacheck(executable, shared, ["--only", "113", "--globals", *sorted(base)]):
        name = NAME.search(finding["text"])
        findings.append({"file": relative(finding["file"]), "code": finding["code"],
                         "name": name.group(1) if name else "", "line": int(finding["line"]),
                         "text": finding["text"]})

    current = sorted({(f["file"], f["code"], f["name"]) for f in findings})
    if args.update_baseline:
        lines = ",\n".join(" " + json.dumps(list(entry)) for entry in current)
        BASELINE.write_text("[\n" + lines + "\n]\n", encoding="utf-8")
        print(f"Baseline updated with {len(current)} known findings.")
        return 0
    baseline = {tuple(entry) for entry in json.loads(BASELINE.read_text(encoding="utf-8"))} if BASELINE.exists() else set()
    new = [f for f in findings if (f["file"], f["code"], f["name"]) not in baseline]
    fixed = sorted(baseline - set(current))
    for finding in new:
        print(f"{finding['file']}:{finding['line']}: ({finding['code']}) {finding['text']}")
    if fixed:
        print(f"{len(fixed)} baseline entries no longer occur; run with --update-baseline to drop them:")
        for entry in fixed:
            print("  " + " ".join(entry))
    print(f"Lua lint: {len(new)} new, {len(current) - len({(f['file'], f['code'], f['name']) for f in new})} known, {len(fixed)} fixed.")
    return 1 if new or fixed else 0


if __name__ == "__main__":
    sys.exit(main())
