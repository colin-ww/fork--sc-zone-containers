"""Print every apt package the given Dockerfiles `apt-get install`, space-separated.

Used by .github/workflows/r-sysdeps-check.yml to rebuild the image's apt layer
in a bare ubuntu:24.04 container. Skips packages from Microsoft's apt repo
(not configured there; no R package links them).
"""
import re
import sys

SKIP = {"msodbcsql18", "mssql-tools18"}
pkgs = set()
for path in sys.argv[1:]:
    txt = open(path).read()
    for m in re.finditer(r"apt-get install", txt):
        for i, line in enumerate(txt[m.start():].split("\n")):
            code = re.sub(r"#.*", "", line)
            if i == 0:
                code = code.split("apt-get install", 1)[1]
            stop = False
            for tok in code.replace("\\", " ").split():
                if tok.startswith("&&") or tok == ";":
                    stop = True
                    break
                if tok.startswith(("-", "/", "$")) or "=" in tok:
                    continue
                pkgs.add(tok)
            if stop or (i > 0 and not line.rstrip().endswith("\\") and not line.strip().startswith("#")):
                break
print(" ".join(sorted(pkgs - SKIP)))
