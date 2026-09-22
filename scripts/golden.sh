#!/bin/sh
# Capture the golden scenes and compare them to tests/golden/ (docs/TESTING.md "T2").
#
#   sh scripts/golden.sh                 capture every scene, then compare
#   sh scripts/golden.sh --capture       capture only
#   sh scripts/golden.sh --compare       compare what is already in out/golden/
#   sh scripts/golden.sh --self-check    prove the verdict decision against known inputs
#   sh scripts/golden.sh --update        capture, then copy out/golden -> tests/golden
#   sh scripts/golden.sh prim/ snap/x    only the rows whose name starts with one of these
#
# --update is never automatic. A golden changes only inside a commit that says why, and the
# PNG diff — out/golden/<backend>/<name>.diff.png, written by the comparator — is the review
# artifact that commit is judged on.
#
# One process per scene isolates GPU-resource and atlas state. A capture cannot inherit pooled
# targets from another row or hide a leak behind resources that row already allocated.
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
		--self-check) mode=selfcheck ;;
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

# Whether a scene's verdict block means the scene was captured. One function, because a
# decision that is only ever exercised by real runs is a decision whose failure mode is a
# wrong golden. `sh scripts/golden.sh --self-check` proves it against known inputs.
verdictOk() {
	# Every line has to be a CAPTURED, not just the first. `case "$1" in CAPTURED*)` read as
	# if it tested that, but a verdict block is grep output over the whole scene log and a
	# shell glob's `*` spans newlines - so `CAPTURED a` followed by `FAIL b` was counted as a
	# capture, and `--update` would then take that scene's output as its golden.
	[ -n "$1" ] || return 1
	printf '%s
' "$1" | grep -qvE '^CAPTURED' && return 1
	return 0
}

# The inputs the decision has to get right. A verdict block is grep output over the scene
# log, so it can hold more than one line.
selfCheck() {
	bad=0
	check() {  # check <expected 0|1> <label> <verdict block>
		if verdictOk "$3"; then got=0; else got=1; fi
		if [ "$got" -eq "$1" ]; then
			echo "PASS  verdict: $2"
		else
			echo "FAIL  verdict: $2 — expected $1, got $got"
			bad=$((bad + 1))
		fi
	}
	check 0 "a single CAPTURED line is a capture" "CAPTURED prim/rect 256x256 dpi 1 draws 1"
	check 1 "an empty block is not a capture" ""
	check 1 "a single FAIL line is not a capture" "FAIL prim/rect something went wrong"
	check 1 "a single SKIP line is not a capture" "SKIP this build has no readback path"
	check 1 "CAPTURED followed by FAIL is not a capture" "CAPTURED prim/rect 256x256
FAIL prim/rect the png writer refused"
	check 1 "CAPTURED followed by SKIP is not a capture" "CAPTURED prim/rect 256x256
SKIP the second grab was not taken"

	# The scene table the capture loop reads. An empty one means the runner never listed a
	# scene - it failed to start, or the build is broken - and a run that captures nothing
	# must not report success, whatever happens downstream.
	checkTable() {  # checkTable <expected 0|1> <label> <table contents>
		printf '%s' "$3" > out/golden/selfcheck.tsv
		if tableUsable out/golden/selfcheck.tsv; then got=0; else got=1; fi
		if [ "$got" -eq "$1" ]; then
			echo "PASS  table: $2"
		else
			echo "FAIL  table: $2 — expected $1, got $got"
			bad=$((bad + 1))
		fi
		rm -f out/golden/selfcheck.tsv
	}
	mkdir -p out/golden
	checkTable 0 "a table with rows is usable" "prim/rect	P0	256	256	1	0
prim/line	P0	256	256	1	0"
	checkTable 1 "an empty table is not usable" ""
	checkTable 1 "a table of only a newline is not usable" "
"
	[ "$bad" -eq 0 ]
}

# Whether the scene table the capture loop is about to read actually lists scenes. Nothing
# checked this: an empty table made the `while read` body run zero times, so `failures` stayed
# 0 and `capture()` returned success having captured nothing. Downstream caught it - `--update`
# died on `cp: cannot stat` and the comparator reported every scene missing, both exiting 1 -
# but a function that reports success for doing nothing is wrong at its own boundary, and the
# next caller need not be as lucky in what it does with that success.
tableUsable() {
	[ -s "$1" ] || return 1
	grep -qE '[^[:space:]]' "$1" || return 1
	return 0
}

matches() {
	[ -z "$filters" ] && return 0
	for f in $filters; do
		case "$1" in "$f"*) return 0 ;; esac
	done
	return 1
}

capture() {
	# out/ is gitignored, so on a clean clone nothing has created it yet.
	mkdir -p out/golden
	VOID_SCENE_LIST=1 "$RUNNER" > out/golden/table.tsv || true
	if ! tableUsable out/golden/table.tsv; then
		echo "FAIL the runner listed no scenes — out/golden/table.tsv is empty" >&2
		return 1
	fi
	rm -rf "out/golden/$BACKEND_DIR"
	index=0
	failures=0
	captured=0
	while IFS="$(printf '\t')" read -r name phase width height dpi steps; do
		if matches "$name"; then
			mkdir -p "out/golden/$BACKEND_DIR/$(dirname "$name")"
			# The runner's exit status, not grep's: grep matching the word FAIL is not the
			# same as the scene having been captured, and taking the pipeline's status would
			# make a run where every scene printed `SKIP this build has no readback path`
			# report success and then let --update overwrite the goldens with nothing.
			VOID_SCENE="$index" "$RUNNER" > out/golden/scene.log 2>&1 || true
			verdict="$(grep -E '^(CAPTURED|FAIL|SKIP)' out/golden/scene.log || true)"
			if [ -n "$verdict" ]; then
				echo "$verdict"
			else
				echo "FAIL $name produced no verdict"
			fi
			if verdictOk "$verdict"; then
				# A printed word is not a file. The runner could say CAPTURED and then die, or
				# write nothing at all, and `--update` would keep the stale golden while the run
				# reported success. The comment above is about the pipeline's exit status; this
				# is about the artefact.
				if [ ! -s "out/golden/$BACKEND_DIR/$name.png" ]; then
					echo "FAIL $name said CAPTURED and wrote no png"
					failures=$((failures + 1))
				fi
			else
				failures=$((failures + 1))
			fi
			captured=$((captured + 1))
		fi
		index=$((index + 1))
	done < out/golden/table.tsv
	rm -f out/golden/scene.log
	# A filter naming no scene is a typo, not an empty job. Reporting success for it is the
	# same defect as reporting success for an empty table, one layer up: measured before this
	# check existed, `--capture zzz/nothing` exited 0 having printed nothing at all.
	if [ "$captured" -eq 0 ]; then
		echo "FAIL no scene matched${filters:+ the filter}${filters} — nothing was captured" >&2
		return 1
	fi
	[ "$failures" -eq 0 ]
}

case "$mode" in
	compare|selfcheck) ;;
	*) build ;;
esac

status=0
case "$mode" in
	selfcheck)
		selfCheck || status=1
		;;
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
