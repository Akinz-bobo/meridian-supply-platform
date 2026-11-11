#!/usr/bin/env python3
"""Fails when a relative link in a Markdown file points at a path that does not exist."""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
SKIP_DIRS = {"node_modules", ".terraform", ".git"}

broken = []
for path in ROOT.rglob("*.md"):
    if SKIP_DIRS & set(path.parts):
        continue
    in_code = False
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if line.lstrip().startswith("```"):
            in_code = not in_code
        if in_code:
            continue
        for target in LINK.findall(line):
            if re.match(r"^(https?:|mailto:|#)", target):
                continue
            file_part = target.split("#", 1)[0]
            if file_part and not (path.parent / file_part).exists():
                broken.append(f"{path.relative_to(ROOT)}:{number}: {target}")

if broken:
    print("Broken relative links:")
    print("\n".join(f"  {item}" for item in broken))
    sys.exit(1)
print("All relative links resolve.")
