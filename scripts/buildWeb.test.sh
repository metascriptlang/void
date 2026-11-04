#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/scripts" "$tmp/bin" "$tmp/sdk/upstream/emscripten"
cp scripts/build-web.sh "$tmp/scripts/"
cp .emscripten-version "$tmp/"
cat > "$tmp/bin/msc" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$CALLS"
output=; wasm=0
for arg do
	case "$arg" in
		--output=*) output=${arg#--output=} ;;
		--os=emcc) wasm=1 ;;
	esac
done
[ -n "$output" ]
mkdir -p "$(dirname "$output")"
printf 'void 0;\n' > "$output"
[ "$wasm" -eq 0 ] || printf 'wasm' > "${output%.js}.wasm"
echo Built
EOF
cat > "$tmp/bin/uname" <<'EOF'
#!/bin/sh
printf 'Linux\n'
EOF
cat > "$tmp/scripts/jsMinify.sh" <<'EOF'
#!/bin/sh
set -eu
cp "$1" "$2"
EOF
printf ': > "$SDK_USED"\n' > "$tmp/sdk/emsdk_env.sh"
cp .emscripten-version "$tmp/sdk/upstream/emscripten/emscripten-version.txt"
chmod +x "$tmp/bin/msc" "$tmp/bin/uname"
export CALLS="$tmp/calls" SDK_USED="$tmp/sdkUsed"
check() {
	name=$1; want=$2; backends=$3; sdk=$4
	: > "$CALLS"
	rm -f "$SDK_USED"
	rm -rf "$tmp/web" "$tmp/out"
	if (cd "$tmp" && PATH="$tmp/bin:$PATH" MSC="$tmp/bin/msc" EMSDK_DIR="$sdk" \
		VOID_WEB_BACKENDS="$backends" VOID_WEB_PRELOAD= VOID_WEB_JS_ASSETS= \
		VOID_WEB_LOGDIR="$tmp/logs" sh scripts/build-web.sh) > "$tmp/$name.log" 2>&1; then
		got=0
	else
		got=$?
	fi
	[ "$got" -eq "$want" ] || {
		echo "FAIL build-web $name: exit $got, expected $want"
		tail -3 "$tmp/$name.log"
		exit 1
	}
}
check jsOnly 0 'js-wgpu js-gl' "$tmp/missing-sdk"
[ -f "$tmp/web/js-wgpu/main2dWeb.js" ] && [ -f "$tmp/web/js-gl/main2dWeb.js" ] && \
	[ ! -e "$SDK_USED" ] && [ "$(grep -c -- '--target=js' "$CALLS")" -eq 2 ] || {
	echo 'FAIL build-web jsOnly: expected two JS artifacts without SDK setup'; exit 1;
}
check glOnly 0 'gl' "$tmp/sdk"
[ -f "$SDK_USED" ] && [ -f "$tmp/web/gl/main2d.wasm" ] && \
	[ "$(grep -c -- '--os=emcc' "$CALLS")" -eq 1 ] && [ "$(wc -l < "$CALLS")" -eq 1 ] || {
	echo 'FAIL build-web glOnly: expected SDK setup and one emcc build'; exit 1;
}
check mixed 0 'wgpu gl js-wgpu js-gl' "$tmp/sdk"
[ -f "$SDK_USED" ] && [ -f "$tmp/web/wgpu/main2d.wasm" ] && [ -f "$tmp/web/gl/main2d.wasm" ] && \
	[ "$(grep -c -- '--os=emcc' "$CALLS")" -eq 2 ] && [ "$(wc -l < "$CALLS")" -eq 4 ] || {
	echo 'FAIL build-web mixed: expected SDK setup and four builds'; exit 1;
}
printf 'wrong-version\n' > "$tmp/sdk/upstream/emscripten/emscripten-version.txt"
check wrongWasmPin 1 'wgpu js-gl' "$tmp/sdk"
[ ! -s "$CALLS" ] && grep -q '.emscripten-version pins' "$tmp/wrongWasmPin.log" || {
	echo 'FAIL build-web wrongWasmPin: expected refusal before any build'; exit 1;
}
echo 'PASS build-web setup: 4 cases (JS-only without SDK, GL-only, mixed backends, wrong wasm pin); stub builds, Unix setup branch'
