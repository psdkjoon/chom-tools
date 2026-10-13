#!/usr/bin/env bash
set -euo pipefail

pkg="${1:?usage: termux-deps.sh <package> <output dir>}"
out="${2:?usage: termux-deps.sh <package> <output dir>}"
base="https://packages.termux.dev/apt/termux-main"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

curl -fsSL "$base/dists/stable/main/binary-aarch64/Packages" -o "$work/Packages"

python3 - "$work/Packages" "$pkg" > "$work/list" <<'PY'
import re
import sys

index = {}
for block in open(sys.argv[1], encoding="utf-8").read().split("\n\n"):
    fields = {}
    for line in block.split("\n"):
        if line and not line.startswith(" ") and ": " in line:
            key, value = line.split(": ", 1)
            fields[key] = value
    name = fields.get("Package")
    if name:
        index[name] = fields
        for provided in fields.get("Provides", "").split(","):
            provided = re.sub(r"\s*\(.*\)", "", provided).strip()
            if provided and provided not in index:
                index[provided] = fields

skip = re.compile(r"^(termux-.*|dpkg|apt|bash|coreutils|busybox|dash|findutils|grep|sed|gawk|tar|gzip|less|nano|procps|util-linux|command-not-found|ed|debianutils|diffutils|libandroid-glob)$")
seen = set()
queue = [sys.argv[2]]
while queue:
    name = queue.pop()
    entry = index.get(name)
    if entry is None or entry["Package"] in seen:
        continue
    seen.add(entry["Package"])
    for dep in entry.get("Depends", "").split(","):
        first = dep.split("|")[0]
        first = re.sub(r"\s*\(.*\)", "", first).strip()
        if first and not skip.match(first):
            queue.append(first)

for name in sorted(seen):
    if name == sys.argv[2]:
        continue
    entry = index[name]
    print(entry["Filename"], entry["SHA256"], name)
PY

mkdir -p "$out/lib"
while read -r filename sha name; do
    [ -n "$filename" ] || continue
    echo "dependency: $name" >&2
    curl -fsSL "$base/$filename" -o "$work/pkg.deb"
    echo "$sha  $work/pkg.deb" | sha256sum -c - >&2
    rm -rf "$work/x"
    mkdir -p "$work/x"
    dpkg-deb -x "$work/pkg.deb" "$work/x"
    find "$work/x" \( -type f -o -type l \) -name '*.so*' | while read -r lib; do
        cp -L "$lib" "$out/lib/$(basename "$lib")" 2>/dev/null || true
    done
done < "$work/list"
ls "$out/lib" >&2
