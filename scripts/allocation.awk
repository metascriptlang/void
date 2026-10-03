function keyOf(call,    i, name, module) {
	i = index(call, "__")
	name = substr(call, 1, i - 1)
	module = call
	sub(/^.*ZsrcZvoid2dZ/, "", module)
	sub(/Oms_u[0-9]+\($/, "", module)
	return module ":" name
}

function enqueue(key, rule, via) {
	if (key in queued) return
	queued[key] = 1
	tail++
	qkey[tail] = key
	qrule[tail] = rule
	qvia[tail] = via
}

BEGIN {
	nf = split(frame, list, " ")
	for (i = 1; i <= nf; i++) if (list[i] != "") enqueue(list[i], "frame", "")
	nc = split(copyOnly, list, " ")
	for (i = 1; i <= nc; i++) if (list[i] != "") enqueue(list[i], "copy", "")
	nn = split(named, list, " ")
	for (i = 1; i <= nn; i++) if (list[i] != "") isNamed[list[i]] = 1
	nb = split(forbidden, banned, " ")
	callRe = "[A-Za-z_][A-Za-z0-9_]*__M?[A-Za-z0-9]*ZsrcZvoid2dZ[A-Za-z0-9]+Oms_u[0-9]+\\("
	defRe = "^[A-Za-z_][A-Za-z0-9_ ]*[* ]+[A-Za-z_][A-Za-z0-9_]*__M?[A-Za-z0-9_]*\\(.*\\{[[:space:]]*$"
}

FNR == 1 {
	module = FILENAME
	sub(/^.*ZsrcZvoid2dZ/, "", module)
	sub(/Oms\.c$/, "", module)
	current = ""
}

current == "" && $0 ~ defRe {
	if (match($0, /[A-Za-z_][A-Za-z0-9_]*__M?[A-Za-z0-9_]*\(/)) {
		head = substr($0, RSTART, RLENGTH)
		current = module ":" substr(head, 1, index(head, "__") - 1)
		defined[current] = 1
	}
	next
}

current != "" {
	if ($0 ~ /^}/) { current = ""; next }
	if ($0 ~ /ArrayCopy\(|OmsCopy\(/) copies[current]++
	if ($0 ~ /msAllocTyped\(|[^a-z]calloc\(|[^a-z]malloc\(|ArrayPush\(&\(?T[0-9]+_/) allocs[current]++
	for (b = 1; b <= nb; b++) {
		if (banned[b] != "" && $0 ~ ("[^A-Za-z0-9_]" banned[b] "__")) bannedCall[current] = bannedCall[current] " " banned[b]
	}
	line = $0
	while (match(line, callRe)) {
		callee = keyOf(substr(line, RSTART, RLENGTH))
		if (callee != current) calls[current] = calls[current] " " callee
		line = substr(line, RSTART + RLENGTH)
	}
}

END {
	for (h = 1; h <= tail; h++) {
		key = qkey[h]; rule = qrule[h]; via = qvia[h]
		where = via == "" ? "" : " (via " via ")"
		if (!(key in defined)) { print "UNREACHABLE " key where; continue }
		if (!(key in isNamed)) followed++
		fn = key; sub(/^[^:]*:/, "", fn)
		if (copies[key] > 0) print "COPIED " fn "=" copies[key] where
		if (rule == "frame" && allocs[key] > 0) print "ALLOCATED " fn "=" allocs[key] where
		if (bannedCall[key] != "") {
			nbc = split(bannedCall[key], hits, " ")
			for (x = 1; x <= nbc; x++) if (hits[x] != "") print "COPIED " fn "->" hits[x] where
		}
		ncall = split(calls[key], callees, " ")
		for (x = 1; x <= ncall; x++) {
			c = callees[x]
			if (c == "" || (c in isNamed)) continue
			cfn = key; sub(/^[^:]*:/, "", cfn)
			enqueue(c, rule, via == "" ? cfn : via " > " cfn)
		}
	}
	print "FOLLOWED " followed + 0
}
