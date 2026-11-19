#!/bin/sh

set -eu
version="${1:?Usage: create_release.sh vMAJOR.MINOR.PATCH OUTPUT_DIRECTORY [GIT_REF]}"
output="${2:?Supply an output directory}"
ref="${3:-HEAD}"
printf '%s\n' "$version" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'
mkdir -p "$output"
output="$(CDPATH='' cd -- "$output" && pwd)"
root="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
git -C "$root" archive "$ref" kindlefetch > "$stage/release.tar"
tar -xf "$stage/release.tar" -C "$stage"
git -C "$root" show "$ref:LICENSE" > "$stage/kindlefetch/LICENSE"
printf '%s\n' "$version" > "$stage/kindlefetch/bin/.version"
(cd "$stage" && COPYFILE_DISABLE=1 zip -q -r release.zip kindlefetch)
mv "$stage/release.zip" "$output/kindlefetch.zip"
