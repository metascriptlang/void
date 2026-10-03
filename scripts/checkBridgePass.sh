set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
zig=""
if [ -z "${CC:-}" ]; then
	if [ -x "$HOME/.metascript/zig/zig.exe" ]; then
		zig="$HOME/.metascript/zig/zig.exe"
	elif [ -x "$HOME/.metascript/zig/zig" ]; then
		zig="$HOME/.metascript/zig/zig"
	fi
fi
compile() {
	rm -f "$work/probe.o"
	if [ -n "$zig" ]; then
		"$zig" cc -std=c11 -c -Isrc/sokol -Isrc/gpu "$@" tests/compile/bridgePass.c \
			-o "$work/probe.o"
	else
		${CC:-cc} -std=c11 -c -Isrc/sokol -Isrc/gpu "$@" tests/compile/bridgePass.c \
			-o "$work/probe.o"
	fi
}
if ! compile -DPROBE_DOOR > "$work/door.log" 2>&1; then
	cat "$work/door.log"
	echo "FAIL public C pass: the door consumer does not compile"
	exit 1
fi
for mode in BEGIN COMMIT; do
	name=voidBeginPass
	[ "$mode" != COMMIT ] || name=voidCommit
	if compile "-DPROBE_$mode" > "$work/$mode.log" 2>&1; then
		echo "FAIL public C pass: $name is still reachable through bridge.h"
		exit 1
	fi
	if ! grep -q "$name" "$work/$mode.log" ||
		! grep -qiE 'undeclared|not declared|undefined' "$work/$mode.log"; then
		cat "$work/$mode.log"
		echo "FAIL public C pass: rejection did not name the absent $name"
		exit 1
	fi
done
echo "PASS public C pass: door consumer compiles; bridge begin/commit consumers are rejected"
