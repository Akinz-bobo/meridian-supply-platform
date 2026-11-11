#!/usr/bin/env python3
"""Fails when a decision record is missing from the index, or the index lists one that does not exist."""
import pathlib
import re
import sys

ADR = pathlib.Path(__file__).resolve().parent.parent / "docs" / "adr"
records = {p.name for p in ADR.glob("[0-9][0-9][0-9][0-9]-*.md")}
indexed = set(re.findall(r"\]\((\d{4}-[^)]+\.md)\)", (ADR / "README.md").read_text(encoding="utf-8")))

problems = [f"not in the index: {name}" for name in sorted(records - indexed)]
problems += [f"indexed but missing: {name}" for name in sorted(indexed - records)]
numbers = sorted(int(name[:4]) for name in records)
if numbers != list(range(1, len(numbers) + 1)):
    problems.append(f"record numbers are not a gapless sequence: {numbers}")

if problems:
    print("\n".join(problems))
    sys.exit(1)
print(f"{len(records)} decision records, all indexed.")
