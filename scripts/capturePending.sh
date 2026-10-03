capture_pending_verdict() {
	awk -F '|' -v key="$2" -v expected="$3" -v got="$4" '
		function clean(value) {
			gsub(/`/, "", value)
			gsub(/^[ \t]+|[ \t\r]+$/, "", value)
			return value
		}
		function hash(value) { return length(value) == 64 && value !~ /[^0-9a-f]/ }
		BEGIN {
			base = key
			sub(/_[0-9]+[.]ppm$/, "", base)
			id = "capture-" base
		}
		{
			cell = clean($2)
			if (cell == id) listed++
			if (cell == key) {
				rows++
				old = clean($3)
				held = clean($4)
			}
		}
		END {
			if (listed == 0 && rows == 0) { print "normal"; exit }
			if (listed != 1 || rows != 1 || !hash(old) || !hash(held) ||
				old != expected || old == held) { print "invalid"; exit }
			if (got == "") { print "listed"; exit }
			if (got == old) { print "stale"; exit }
			if (got == held) { print "held"; exit }
			print "mismatch"
		}
	' "$1"
}

capture_pending_keys() {
	awk -F '|' '{
		cell = $2
		gsub(/[` \t\r]/, "", cell)
		if (cell ~ /^[a-z0-9]+_[0-9]+[.]ppm$/) print cell
	}' "$1"
}
