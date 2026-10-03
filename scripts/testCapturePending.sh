set -eu
. scripts/capturePending.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
old=$(printf '%064d' 1)
held=$(printf '%064d' 2)
other=$(printf '%064d' 3)
file="$work/PENDING3D.md"
key=m14forward_1.ppm
row='| `capture-m14forward` | unresolved | doc | card |'
checks=0
check() {
	actual=$(capture_pending_verdict "$file" "$key" "$2" "$3")
	if [ "$actual" != "$1" ]; then
		echo "FAIL capture pending: expected $1, got $actual"
		exit 1
	fi
	checks=$((checks + 1))
}
record() {
	printf '%s\n| `%s` | `%s` | `%s` |\n' "$row" "$key" "$old" "$held" > "$file"
}
: > "$file"
check normal "$old" "$other"
record
check listed "$old" ''
check held "$old" "$held"
check stale "$old" "$old"
check mismatch "$old" "$other"
check invalid "$other" "$held"
printf '%s\n' "$row" > "$file"
check invalid "$old" "$held"
printf '| `%s` | `%s` | `%s` |\n' "$key" "$old" "$held" > "$file"
check invalid "$old" "$held"
record
printf '| `%s` | `%s` | `%s` |\n' "$key" "$old" "$held" >> "$file"
check invalid "$old" "$held"
printf '%s\n| `%s` | `%s` | `%s` |\n' "$row" "$key" "$old" "$old" > "$file"
check invalid "$old" "$held"
printf '%s\r\n| `%s` | `%s` | `%s` |\r\n' "$row" "$key" "$old" "$held" > "$file"
check held "$old" "$held"
printf '%s\n| `%s` | `%s` | `bad` |\n' "$row" "$key" "$old" > "$file"
check invalid "$old" "$held"
key=m14forward_99.ppm
record
found=$(capture_pending_keys "$file")
if [ "$found" != "$key" ]; then
	echo "FAIL capture pending: an unexpected frame was hidden by the row reader"
	exit 1
fi
check invalid '' "$held"
echo "PASS capture pending: $checks controls, exact held hashes, changed bytes and stale rows"
