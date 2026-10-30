#!/bin/sh
# A/B of the tests/bench rows, main (sokol) against this tree (gpu-ms), per backend. The end-game
# clause is docs/GPU-MS.md "End-game done when"; the commands are its section "A/B against main".
#
#   sh scripts/abBench.sh build [linux|web]  CPU only: worktree of main, both sides, every backend, or
#                                            both sides under WSL (linux), or both sides for the
#                                            browser (web-wgpu, web-gl: emscripten wasm per scene)
#   sh scripts/abBench.sh run [reps]         opens windows and uses the GPU: only inside a granted GO
#   sh scripts/abBench.sh clean              delete the exes and the main worktree
#
# Environment: AB_MAIN_SHA (default: the merge base of HEAD and main, so a delta is the GPU layer
# and not newer void2d on main; main's tip is `AB_MAIN_SHA=main`), AB_BACKENDS (default "d3d11 gl"; add vulkan,
# which main lacks and so runs on B alone, linux, web-wgpu, web-gl; `build web` alone defaults it to
# "web-wgpu web-gl"), AB_LINUX_DRIVER (d3d12 default, or llvmpipe),
# AB_SCENES (default "Ui Sprites Text Editor Scroll Campfire"), AB_TOL percent of slack on a .ms row
# (default 3), AB_LOAD_LIMIT percent CPU load that voids a run (default 25), AB_OUT, MSC.
# Run `build` as `bash ~/metascript/.wt/nim-audit/buildslot.sh sh scripts/abBench.sh build`.
set -eu
cd "$(dirname "$0")/.."
B="$(pwd)"
MSC="${MSC:-msc}"
SCENES="${AB_SCENES:-Ui Sprites Text Editor Scroll Campfire}"
BACKENDS="${AB_BACKENDS:-d3d11 gl}"
TOL="${AB_TOL:-3}"
LIMIT="${AB_LOAD_LIMIT:-25}"
OUT="${AB_OUT:-${TEMP:-/tmp}/voidAB}"
MAIN_REPO="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"
A="$(dirname "$B")/void-ab-main"
export MSC_NO_GLOBAL_CACHE=1

# $2 is the side: main's golden runner defines SOKOL_GLCORE, this branch's defines VOID_GLCORE.
backendFlags() {
	case "$1" in
		d3d11) echo "" ;;
		gl) if [ "$2" = A ]; then echo "-d:voidGlCore --passC=-DSOKOL_GLCORE"; else echo "-d:voidGlCore --passC=-DVOID_GLCORE"; fi ;;
		vulkan) echo "-d:voidVulkan" ;;
		*) echo "abBench.sh: backend '$1' is not built on this machine (d3d11, gl, vulkan)" >&2; exit 2 ;;
	esac
}

winPath() { cygpath -w "$1"; }

# A tree with uncommitted tracked edits builds what no sha names, so env.txt says so.
dirtyOf() {
	n=$(git -C "$1" status --porcelain --untracked-files=no | wc -l | tr -d ' ')
	[ "$n" = 0 ] || echo " +dirty ($n tracked files differ)"
}

provision() {
	sha="${AB_MAIN_SHA:-$(git merge-base HEAD main)}"
	mkdir -p "$OUT"
	if [ ! -d "$A" ]; then
		git worktree add --detach "$A" "$sha"
		MSYS_NO_PATHCONV=1 cmd /c "mklink /J $(winPath "$A")\\deps $(winPath "$MAIN_REPO")\\deps" > /dev/null
	elif [ "$(git -C "$A" rev-parse HEAD)" != "$(git rev-parse "$sha")" ]; then
		git -C "$A" checkout --detach "$sha"
	fi
	# An entry sits above void2d and void3d, so a scene main has no entry for runs B's entry on A.
	for scene in $SCENES; do
		entry="tests/bench/bench$scene.ms"
		if ! git -C "$A" cat-file -e "HEAD:$entry" 2>/dev/null; then
			if [ -d "$A/src/host" ]; then cp "$B/$entry" "$A/$entry"; else sed 's#src/host/#src/sokol/#' "$B/$entry" > "$A/$entry"; fi
			echo "ENTRY $scene: A runs B's $entry"
		fi
	done
	{
		echo "A main-side $(git -C "$A" rev-parse HEAD)$(dirtyOf "$A") (main tip $(git rev-parse main))"
		echo "B gpu-ms $(git rev-parse HEAD)$(dirtyOf "$B")"
		echo "msc $("$MSC" --version | sed 's/\x1b\[[0-9;]*m//g' | head -1)"
		echo "BUILD $(head -1 "$(dirname "$(command -v "$MSC")")/../BUILD")"
	} | tee "$OUT/env.txt"
}

# Both sides build with build-web.sh, each its own (identical today), into $OUT/web/<side>/<wgpu|gl>/.
# Chrome is the only consumer of these, so a build is judged by the .js and .wasm it leaves.
buildWeb() {
	for side in A B; do
		tree="$A"; [ "$side" = B ] && tree="$B"
		for scene in $SCENES; do
			for backend in $BACKENDS; do
				case "$backend" in web-*) ;; *) continue ;; esac
				dir="${backend#web-}"
				rm -f "$OUT/web/$side/$dir/bench$scene".*
				mkdir -p "$OUT/web/$side/logs"
				(cd "$tree" && VOID_WEB_MSCFLAGS="--release" VOID_WEB_ENTRY="tests/bench/bench$scene.ms" VOID_WEB_DEST="$OUT/web/$side" 					VOID_WEB_BACKENDS="$dir" VOID_WEB_LOGDIR="$OUT/web/$side/logs" MSC="$MSC" 					VOID_WEB_PRELOAD="--preload-file assets --preload-file tests/fonts" 					sh scripts/build-web.sh) > "$OUT/web/$side/build$scene-$dir.log" 2>&1 || true
				if [ -f "$OUT/web/$side/$dir/bench$scene.js" ] && [ -f "$OUT/web/$side/$dir/bench$scene.wasm" ]; then
					echo "BUILD ok   $backend $side $scene"
				else
					echo "BUILD FAIL $backend $side $scene (see $OUT/web/$side/build$scene-$dir.log)"
					failed=1
				fi
			done
		done
	done
	[ -z "${failed:-}" ]
}

build() {
	if [ "${1:-}" = web ] && [ -z "${AB_BACKENDS:-}" ]; then BACKENDS="web-wgpu web-gl"; fi
	provision
	if [ "${1:-}" = linux ]; then buildLinux; return; fi
	for backend in $BACKENDS; do
		case "$backend" in web-*) continue ;; esac
		for side in A B; do
			if [ "$backend" = vulkan ] && [ "$side" = A ]; then echo "SKIP       vulkan A (main has no Vulkan backend)"; continue; fi
			flags="$(backendFlags "$backend" "$side")"
			tree="$A"; [ "$side" = B ] && tree="$B"
			mkdir -p "$OUT/$backend/$side"
			for scene in $SCENES; do
				exe="$OUT/$backend/$side/bench$scene.exe"
				rm -f "$exe"
				# shellcheck disable=SC2086
				if (cd "$tree" && "$MSC" build $flags "tests/bench/bench$scene.ms" --release --output="$exe") \
						> "$OUT/$backend/$side/build$scene.log" 2>&1 && [ -x "$exe" ]; then
					echo "BUILD ok   $backend $side $scene"
				else
					echo "BUILD FAIL $backend $side $scene (see $OUT/$backend/$side/build$scene.log)"
					failed=1
				fi
			done
		done
	done
	case " $BACKENDS " in *" web-"*) buildWeb || failed=1 ;; esac
	[ -z "${failed:-}" ]
}

# Linux runs in WSL on the real GPU through Mesa's d3d12 driver (GALLIUM_DRIVER=d3d12), or on
# llvmpipe with AB_LINUX_DRIVER=llvmpipe. Exes live in a WSL-native dir, never under /mnt/c, so the
# load path is not a variable; each tree is read through /mnt/c.
# The WSL script comes on stdin; \$ is WSL's, $ is expanded here first.
wsl() { MSYS_NO_PATHCONV=1 wsl.exe -e bash -l -s; }
wslTree() { MSYS_NO_PATHCONV=1 wsl.exe -e wslpath -u "$(winPath "$1")" | tr -d '\r'; }
wslOut() { echo "$(echo 'echo $HOME' | wsl | tr -d '\r')/voidAB"; }

buildLinux() {
	out="$(wslOut)"
	wsl > "$OUT/linuxProvision.log" 2>&1 <<EOF || { echo "BUILD FAIL linux provision (see $OUT/linuxProvision.log)"; return 1; }
set -e
mkdir -p $out/A $out/B
for d in d3d12 llvmpipe; do
	printf '#!/bin/bash -l\nexport GALLIUM_DRIVER=%s DISPLAY=\${DISPLAY:-:0}\nexec "\$@"\n' \$d > $out/run.\$d.sh
	chmod +x $out/run.\$d.sh
done
EOF
	for side in A B; do
		tree="$A"; [ "$side" = B ] && tree="$B"; wtree="$(wslTree "$tree")"
		for scene in $SCENES; do
			if wsl > "$OUT/linux$side$scene.log" 2>&1 <<EOF
export MSC_NO_GLOBAL_CACHE=1
rm -f $out/$side/bench$scene.exe
cd '$wtree'
msc build --os=linux tests/bench/bench$scene.ms --release --output=$out/$side/bench$scene.exe
[ -x $out/$side/bench$scene.exe ]
EOF
			then
				echo "BUILD ok   linux $side $scene"
			else
				echo "BUILD FAIL linux $side $scene (see $OUT/linux$side$scene.log)"
				failed=1
			fi
		done
	done
	[ -z "${failed:-}" ]
}

# The GL renderer a driver setting yields, from glxinfo under the same wrapper the exes use.
linuxRenderer() { echo "$(wslOut)/run.$1.sh glxinfo -B" | wsl 2>/dev/null | tr -d '\r' | sed -n 's/^OpenGL renderer string: //p'; }

runLinux() {
	reps="$1"; want="${AB_LINUX_DRIVER:-d3d12}"; out="$(wslOut)"
	if [ -z "$(echo "ls $out/A/bench*.exe 2>/dev/null" | wsl)" ]; then
		echo "VOID linux: side A has no exe (main has no Linux window path), nothing to compare"; return 0
	fi
	renderer="$(linuxRenderer "$want")"
	case "$want:$renderer" in
		d3d12:*D3D12*|llvmpipe:*llvmpipe*) ;;
		*) echo "VOID linux/$want: the renderer is '${renderer:-none}', not the one requested; no rows"; return 0 ;;
	esac
	echo "=== linux/$want, GL renderer: $renderer"
	AB_RUN="wsl.exe -e $out/run.$want.sh" MSYS_NO_PATHCONV=1 AB_DIR_A="$out/A" AB_DIR_B="$out/B" \
		AB_RAW="$OUT/raw-linux-$want.tsv" AB_LABEL="linux/$want" \
		AB_TOL="$TOL" AB_LOAD_LIMIT="$LIMIT" sh scripts/bench-ab.sh "$A" "$B" "$reps" $SCENES
}

# Headless Chrome runs each scene through scripts/webBench.mjs, this tree's driver for both sides, as
# the AB_RUN of the exe path bench-ab.sh builds; node needs Windows paths.
runWeb() {
	dir="${1#web-}"
	echo "=== $1"
	AB_RUN="node $(cygpath -m "$B")/scripts/webBench.mjs $dir" 		AB_DIR_A="$(cygpath -m "$OUT")/web/A/$dir" AB_DIR_B="$(cygpath -m "$OUT")/web/B/$dir" 		AB_RAW="$OUT/raw-$1.tsv" AB_LABEL="$1" AB_TOL="$TOL" AB_LOAD_LIMIT="$LIMIT" 		sh scripts/bench-ab.sh "$A" "$B" "$2" $SCENES
}

# Main has no Vulkan backend, so its rows are B's alone: the median, low and high of the runs.
runAlone() {
	raw="$OUT/raw-$1.tsv"
	echo "=== $1 (B only, absolute: main has no $1 backend)"
	for scene in $SCENES; do
		rep=1
		while [ "$rep" -le "$2" ]; do
			(cd "$B" && "$OUT/$1/B/bench$scene.exe" 2>/dev/null) | tr -d '\r' | awk -v l="$1" -v s="$scene" -v r="$rep" \
				'/^[A-Za-z0-9]+\.[A-Za-z0-9.]+ -?[0-9.eE+-]+$/ { print l "\t" s "\t" r "\t" $1 "\t" $2 }' >> "$raw"
			rep=$((rep + 1))
		done
	done
	awk -F'\t' -f scripts/benchFlow.awk -e '
		{ key = $2 SUBSEP $4; if (!(key in cnt)) keys[++nk] = key; val[key, ++cnt[key]] = $5 }
		END {
			printf "%-7s %-8s %-34s %14s %14s %14s %5s\n", "label", "flow", "metric", "B median", "low", "high", "runs"
			for (i = 1; i <= nk; i++) {
				key = keys[i]; split(key, q, SUBSEP); n = cnt[key]
				for (j = 1; j <= n; j++) v[j] = val[key, j]
				for (j = 2; j <= n; j++) { x = v[j]; k = j - 1; while (k >= 1 && v[k] > x) { v[k + 1] = v[k]; k-- } v[k + 1] = x }
				printf "%-7s %-8s %-34s %14.4g %14.4g %14.4g %5d\n", label, flow(q[2]), q[2], n % 2 ? v[(n + 1) / 2] : (v[n / 2] + v[n / 2 + 1]) / 2, v[1], v[n], n
			}
		}' label="$1" "$raw"
}

# The protocol (interleaving, load sampling, NOISY, AB_MIN_CLEAN, the all-row table) is
# scripts/bench-ab.sh's; this only points it at each backend's exes.
run() {
	reps="${1:-5}"
	[ -f "$OUT/env.txt" ] || { echo "abBench.sh: no build under $OUT, run build first" >&2; exit 1; }
	rm -f "$OUT"/raw-*.tsv
	cat "$OUT/env.txt"
	for backend in $BACKENDS; do
		if [ "$backend" = linux ]; then runLinux "$reps"; continue; fi
		if [ "$backend" = vulkan ]; then runAlone vulkan "$reps"; continue; fi
		case "$backend" in web-*) runWeb "$backend" "$reps"; continue ;; esac
		echo "=== $backend"
		# shellcheck disable=SC2086
		AB_DIR_A="$OUT/$backend/A" AB_DIR_B="$OUT/$backend/B" AB_RAW="$OUT/raw-$backend.tsv" AB_LABEL="$backend" 			AB_TOL="$TOL" AB_LOAD_LIMIT="$LIMIT" sh scripts/bench-ab.sh "$A" "$B" "$reps" $SCENES
	done
	echo "raw rows: $OUT/raw-<backend>.tsv"
}

clean() {
	rm -rf "$OUT"
	if [ -d "$A" ]; then
		cmd /c "rmdir $(winPath "$A")\\deps" > /dev/null 2>&1 || true
		git worktree remove --force "$A"
	fi
}

case "${1:-}" in
	build) build "${2:-}" ;;
	run) run "${2:-5}" ;;
	clean) clean ;;
	*) echo "usage: sh scripts/abBench.sh build [linux|web] | run [reps] | clean" >&2; exit 2 ;;
esac
