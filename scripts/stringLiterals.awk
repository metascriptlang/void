{
	sub(/\r$/, "")
	line = $0
	gsub(/`[^`]*`/, "", line)
	rest = line
	while (match(rest, /"(\\.|[^"\\])*"/)) {
		literal = substr(rest, RSTART, RLENGTH)
		if (index(literal, "\t") > 0 || index(literal, "\r") > 0) {
			printf "%s:%d: raw tab or CR inside a string literal\n", FILENAME, FNR
			bad++
		}
		rest = substr(rest, 1, RSTART - 1) substr(rest, RSTART + RLENGTH)
	}
	comment = index(rest, "//")
	if (comment > 0) { rest = substr(rest, 1, comment - 1) }
	if (index(rest, "\"") > 0) {
		printf "%s:%d: a string literal runs past the end of its line\n", FILENAME, FNR
		bad++
	}
}
END { exit bad > 0 }
