#!/bin/sh
# Fetch Void's C dependencies into deps/ at pinned commits.
#
# The pins are the versions Void is built and tested against. sokol moves its
# API often (its CHANGELOG.md gives a migration recipe per break). Bump a pin
# only together with the code change it needs.
#
# msc caches C objects globally (~/.metascript/cache/objects) keyed by the .c
# file, not the headers it includes, and --force does not bypass it: after a
# pin bump, delete the cached objects that include deps/sokol, or the build
# silently links code compiled against the old headers.
#
# The BiDi conformance files (BidiTest.txt, BidiCharacterTest.txt, Unicode 18.0.0) are fetched into
# deps/ucd and pinned by sha256 in tests/oracle/ucd/bidiConformance.sha256, which the oracle test
# reads too. They are not vendored: 14.8 MB against the 0.6 MB of UAX #14 rows under
# tests/oracle/ucd (docs/TESTING.md, "Why the BiDi rows are fetched").
#
# Also needed, as a sibling checkout: ../yoga (github.com/metascriptlang/yoga),
# with libyoga.a built for the target (see its scripts/build-yoga.sh).
set -e
cd "$(dirname "$0")"

SOKOL_REV="2e75443dbd4940b5aa8d76a8e479f8e4b270b9a3"            # 2026-09-14
STB_REV="2c980bb59875b0d32144a71867fbdebb2f77cd20"
KB_REV="cc63806775f615908ec9562653af4726d8b895d5"                  # v2.28e, 2026-10-02, zlib
NANOSVG_REV="239e102ec2c691f2902e20ace2ed36ee4a35cfe6"            # 2026-07-10, zlib

fetch() {
	name="$1"; repo="$2"; rev="$3"
	dest="deps/$name"
	if [ ! -d "$dest/.git" ]; then
		echo "cloning $repo"
		git clone -q "https://github.com/$repo.git" "$dest"
	fi
	if [ "$(git -C "$dest" rev-parse HEAD)" != "$rev" ]; then
		git -C "$dest" fetch -q origin
		git -C "$dest" checkout -q "$rev"
	fi
	echo "$name @ $(git -C "$dest" rev-parse --short HEAD)"
}

UCD_VERSION="18.0.0"
UCD_PINS="tests/oracle/ucd/bidiConformance.sha256"

sha256_of() {
	if command -v sha256sum > /dev/null 2>&1; then
		sha256sum "$1" | cut -d ' ' -f 1
	else
		shasum -a 256 "$1" | cut -d ' ' -f 1
	fi
}

fetch_ucd() {
	file="$1"
	want="$(awk -v f="$file" '$2 == f { print $1 }' "$UCD_PINS" | tr -d '\r')"
	[ -n "$want" ] || { echo "ucd $file: $UCD_PINS holds no sha256 for it"; exit 1; }
	dest="deps/ucd/$file"
	if [ ! -f "$dest" ] || [ "$(sha256_of "$dest")" != "$want" ]; then
		echo "fetching $file"
		curl -fsSL "https://www.unicode.org/Public/$UCD_VERSION/ucd/$file" -o "$dest.part"
		got="$(sha256_of "$dest.part")"
		if [ "$got" != "$want" ]; then
			rm -f "$dest.part"
			echo "ucd $file: sha256 is $got, the pin is $want"
			exit 1
		fi
		mv "$dest.part" "$dest"
	fi
	echo "ucd $file @ $(echo "$want" | cut -c 1-8)"
}

mkdir -p deps
fetch sokol           floooh/sokol           "$SOKOL_REV"
fetch stb             nothings/stb           "$STB_REV"
fetch kb              JimmyLefevre/kb        "$KB_REV"
fetch nanosvg         memononen/nanosvg      "$NANOSVG_REV"

mkdir -p deps/ucd
fetch_ucd BidiTest.txt
fetch_ucd BidiCharacterTest.txt

echo "--- Setup complete ---"
