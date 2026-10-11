#!/usr/bin/env bash
set -euo pipefail

pkg="${1:?usage: termux-fetch.sh <package> <output dir>}"
out="${2:?usage: termux-fetch.sh <package> <output dir>}"
base="https://packages.termux.dev/apt/termux-main"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

curl -fsSL "$base/dists/stable/main/binary-aarch64/Packages" -o "$work/Packages"
awk -v RS= -v pkg="$pkg" '$0 ~ ("(^|\n)Package: " pkg "\n") { print; exit }' "$work/Packages" > "$work/stanza"
if [ ! -s "$work/stanza" ]; then
    echo "package $pkg not found in the Termux index" >&2
    exit 1
fi
cat "$work/stanza" >&2

filename="$(sed -n 's/^Filename: //p' "$work/stanza")"
sha="$(sed -n 's/^SHA256: //p' "$work/stanza")"
version="$(sed -n 's/^Version: //p' "$work/stanza" | sed 's/^[0-9]*://; s/-[0-9]*$//' | tr -c 'A-Za-z0-9._+\n-' '_')"
if [ -z "$filename" ] || [ -z "$sha" ] || [ -z "$version" ]; then
    echo "incomplete package entry for $pkg" >&2
    exit 1
fi

curl -fsSL "$base/$filename" -o "$work/pkg.deb"
echo "$sha  $work/pkg.deb" | sha256sum -c - >&2
mkdir -p "$out"
dpkg-deb -x "$work/pkg.deb" "$out"
echo "$version"
