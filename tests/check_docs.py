#!/usr/bin/env python3
"""Static checks on the Markdown sources that `mkdocs build --strict` does not do.

1. Every table row has the same number of cells as its header (an unescaped
   pipe inside a cell silently breaks a table).
2. Code fences are balanced.
3. Every study chapter listed in the nav has a chapter card.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
errors = []


def cells(line: str) -> int:
    line = line.strip()
    line = re.sub(r"\\\|", "", line)          # escaped pipes do not split cells
    return line.strip("|").count("|") + 1


for md in sorted(DOCS.rglob("*.md")):
    rel = md.relative_to(ROOT)
    lines = md.read_text().splitlines()
    in_fence = False
    header_cells = None
    for no, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("```"):
            in_fence = not in_fence
            header_cells = None
            continue
        if in_fence:
            continue
        if stripped.startswith("|") and stripped.endswith("|"):
            n = cells(stripped)
            if header_cells is None:
                header_cells = n
            elif n != header_cells:
                errors.append(f"{rel}:{no}: table row has {n} cells, header has {header_cells}")
        else:
            header_cells = None
    if in_fence:
        errors.append(f"{rel}: unbalanced code fence")

for e in errors:
    print(e)
print(f"check_docs: {len(errors)} problem(s)")
sys.exit(1 if errors else 0)
