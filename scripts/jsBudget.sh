#!/bin/sh
# The JS twin of tests/bench/wasmBudget.txt: the size of the --target=js bundle of each JS entry with every
# module flag off, and with each module flag on alone, raw and gzip -9, plus the off bundle split by source
# directory. Two columns per entry: the msc bundle (raw and gzip, which keeps the compiler gap visible) and the
# shipped one after scripts/jsMinify.sh (shipRaw and shipGzip). The rule is scripts/experiment-modulesWeb.sh's: the off column equals the record, an on column
# stays within its recorded value.
#
#   sh scripts/jsBudget.sh            build, measure, compare with tests/bench/jsBudget.txt
#   sh scripts/jsBudget.sh --record   build, measure, rewrite tests/bench/jsBudget.txt
#
# mainSokol2d.ms does not build for JS yet (inbox card js-element-address-as-pointer-argument), so the entries
# are the two harness entries; neither reaches src/void2d, and an on column equal to off says its flag reaches no JS.
set -eu
cd "$(dirname "$0")/.."

MSC="${MSC:-msc}"
RECORD=tests/bench/jsBudget.txt
OUT=out/jsBudget
entries="windowJsEntry viewsJsEntry"
modules="shaper sdf bidi colour sprites outline"
mode=check
[ "${1:-}" = --record ] && mode=record

flagOf() {
	case "$1" in
		shaper) echo "-d:voidShaper" ;;
		sdf) echo "-d:voidSdfText" ;;
		bidi) echo "-d:voidBidi" ;;
		colour) echo "-d:voidColourEmoji" ;;
		sprites) echo "-d:voidSprites" ;;
		outline) echo "-d:voidTextOutline" ;;
		*) echo "unknown module $1" >&2; exit 2 ;;
	esac
}

rm -rf "$OUT"
mkdir -p "$OUT"
rows="$OUT/rows.txt"
: > "$rows"
status=0

build() {
	entry="$1"; label="$2"; flag="$3"
	"$MSC" build --target=js $flag "src/examples/$entry.jms" --output="$OUT/$entry-$label.js" > "$OUT/$entry-$label.log" 2>&1 \
		|| { echo "FAIL js budget: $entry $label did not build — see $OUT/$entry-$label.log"; exit 1; }
	sh scripts/jsMinify.sh "$OUT/$entry-$label.js" "$OUT/$entry-$label.min.js" > "$OUT/$entry-$label.min.log" 2>&1 		|| { echo "FAIL js budget: jsMinify of $entry $label — see $OUT/$entry-$label.min.log"; exit 1; }
}

for entry in $entries; do
	build "$entry" off ""
	set -- $(node scripts/jsBudgetMeasure.mjs size "$OUT/$entry-off.js")
	offRaw=$1; offGzip=$2
	set -- $(node scripts/jsBudgetMeasure.mjs size "$OUT/$entry-off.min.js")
	offShipRaw=$1; offShipGzip=$2
	node scripts/jsBudgetMeasure.mjs split "$OUT/$entry-off.js" > "$OUT/$entry-split.txt"
	echo "JS $entry off shipped: $offShipRaw B raw, $offShipGzip B gzip"
	echo "JS $entry off: $offRaw B raw, $offGzip B gzip; gzip share by source directory:"
	sed 's/^/      /' "$OUT/$entry-split.txt"
	for module in $modules; do
		build "$entry" "$module" "$(flagOf "$module")"
		set -- $(node scripts/jsBudgetMeasure.mjs size "$OUT/$entry-$module.js")
		echo "$entry-$module raw off $offRaw on $1" >> "$rows"
		echo "$entry-$module gzip off $offGzip on $2" >> "$rows"
		echo "JS $entry $module: raw off $offRaw on $1 delta $(($1 - offRaw)), gzip off $offGzip on $2 delta $(($2 - offGzip))"
		set -- $(node scripts/jsBudgetMeasure.mjs size "$OUT/$entry-$module.min.js")
		echo "$entry-$module shipRaw off $offShipRaw on $1" >> "$rows"
		echo "$entry-$module shipGzip off $offShipGzip on $2" >> "$rows"
	done
done

if [ "$mode" = record ]; then
	{
		echo "profile scripts/jsBudget.sh --target=js entries $entries; rows are <entry>-<module> raw|gzip|shipRaw|shipGzip off <bytes> on <bytes>, gzip -9"
		echo "measured BUILD $(sed -n 's/^binary \([0-9a-f]*\).*/\1/p' "$HOME/.metascript/BUILD" | head -n 1) $(date +%Y-%m-%d) tree $(git rev-parse HEAD)"
		cat "$rows"
	} > "$RECORD"
	echo "recorded $(wc -l < "$rows" | tr -d ' ') rows in $RECORD"
	exit 0
fi

[ -f "$RECORD" ] || { echo "FAIL js budget: $RECORD does not exist; run sh scripts/jsBudget.sh --record"; exit 1; }
while read -r key kind offTag off onTag on; do
	recorded=$(grep -E "^$key $kind off [0-9]+ on [0-9]+\$" "$RECORD" | tr -d '\r' | head -n 1 || true)
	if [ -z "$recorded" ]; then
		echo "FAIL js budget $key $kind: no row in $RECORD"
		status=1
		continue
	fi
	budgetOff=$(echo "$recorded" | awk '{ print $4 }')
	budgetOn=$(echo "$recorded" | awk '{ print $6 }')
	if [ "$off" -ne "$budgetOff" ]; then
		echo "FAIL js budget $key $kind: module off is $off B, recorded $budgetOff B"
		status=1
	elif [ "$on" -gt "$budgetOn" ]; then
		echo "FAIL js budget $key $kind: module on is $on B, over the recorded $budgetOn B"
		status=1
	else
		echo "PASS js budget $key $kind: off $off, on $on (record $budgetOn)"
	fi
done < "$rows"
exit "$status"
