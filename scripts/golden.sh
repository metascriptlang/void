#!/bin/sh
# Capture the golden scenes and compare them to tests/golden/ (docs/TESTING.md "T2").
#
#   sh scripts/golden.sh                 capture every scene, then compare
#   sh scripts/golden.sh --capture       capture only
#   sh scripts/golden.sh --compare       compare what is already in out/golden/
#   sh scripts/golden.sh --update        capture, then copy out/golden -> tests/golden
#   sh scripts/golden.sh prim/ snap/x    only the rows whose name starts with one of these
#
# --update is never automatic. A golden changes only inside a commit that says why, and the
# PNG diff — out/golden/<backend>/<name>.diff.png, written by the comparator — is the review
# artifact that commit is judged on.
#
# One process per scene: sokol's default resource pools hold 128 objects and today every
# Label and Graphics owns an sg_buffer, so several Label-heavy scenes in one process would
# capture a scene with nodes missing (VOID2D.md "Known defects", closed at P1).
set -e
cd "$(dirname "$0")/.."

MSC="${MSC:-msc}"
BACKEND_DIR=d3d11
RUNNER=out/goldenRunner.exe
COMPARE=out/goldenCompare.exe

mode=all
filters=""
for arg in "$@"; do
	case "$arg" in
		--capture) mode=capture ;;
		--compare) mode=compare ;;
		--update)  mode=update ;;
		-*) echo "golden.sh: unknown flag $arg" >&2; exit 2 ;;
		*) filters="$filters $arg" ;;
	esac
done

# The object cache is keyed on the .c and not on the headers it includes, and --force does
# not bypass it, so a changed capture.c or shader header would otherwise link stale objects
# (~/metascript/.inbox/compiler/2026-09-20-object-cache-ignores-headers.md).
evict() {
	rm -f "$RUNNER" "$COMPARE"
	rm -rf out/debug/.cache out/release/.cache
	rm -rf "$HOME/.metascript/cache/objects"
}

build() {
	evict
	# Release, for two reasons. VOID2D.md's baseline and tests/bench/ are release, so one
	# build mode covers both; and sokol's validation layer, which a debug build links,
	# aborts the process on two of the defects this suite exists to record —
	# regress/vertexCap panics on the sg_append_buffer overflow, and every filter row trips
	# `!_sg.cur_pass.valid`. A golden records what the renderer draws; the validation layer
	# is a separate check, and tests/PENDING.md carries what it says.
	"$MSC" build tests/golden/runner.ms --release --output="$RUNNER" >/dev/null
	"$MSC" build tests/golden/compare.ms --output="$COMPARE" >/dev/null
}

matches() {
	[ -z "$filters" ] && return 0
	for f in $filters; do
		case "$1" in "$f"*) return 0 ;; esac
	done
	return 1
}

capture() {
	VOID_SCENE_LIST=1 "$RUNNER" > out/golden/table.tsv
	rm -rf "out/golden/$BACKEND_DIR"
	index=0
	failures=0
	while IFS="$(printf '\t')" read -r name phase width height dpi steps; do
		if matches "$name"; then
			mkdir -p "out/golden/$BACKEND_DIR/$(dirname "$name")"
			if ! VOID_SCENE="$index" "$RUNNER" 2>/dev/null | grep -E '^(CAPTURED|FAIL|SKIP)'; then
				echo "FAIL $name produced no verdict"
				failures=$((failures + 1))
			fi
		fi
		index=$((index + 1))
	done < out/golden/table.tsv
	[ "$failures" -eq 0 ]
}

case "$mode" in
	compare) ;;
	*) build ;;
esac

status=0
case "$mode" in
	capture)
		capture || status=1
		;;
	compare)
		"$COMPARE" || status=1
		;;
	all)
		capture || status=1
		"$COMPARE" || status=1
		;;
	update)
		capture || status=1
		if [ "$status" -eq 0 ]; then
			mkdir -p "tests/golden/$BACKEND_DIR"
			# harness/mustFail's golden is deliberately wrong and is never regenerated; it is
			# what proves the comparator can fail at all (docs/TESTING.md).
			keep="tests/golden/$BACKEND_DIR/harness/mustFail.png"
			[ -f "$keep" ] && cp "$keep" out/golden/mustFail.keep.png
			cp -r "out/golden/$BACKEND_DIR/." "tests/golden/$BACKEND_DIR/"
			[ -f out/golden/mustFail.keep.png ] && mv out/golden/mustFail.keep.png "$keep"
			echo "goldens updated from out/golden/$BACKEND_DIR — review the diff before committing"
		else
			echo "goldens NOT updated: capture failed"
		fi
		;;
esac

exit "$status"
