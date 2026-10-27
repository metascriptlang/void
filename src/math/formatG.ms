// %g of a double, as printf prints it: six significant digits, trailing zeros dropped.
export function formatG(x: float64): string {
	if (x != x) { return "nan"; }
	if (x > 1.7976931348623157e308) { return "inf"; }
	if (x < -1.7976931348623157e308) { return "-inf"; }
	if (x == 0) { return 1 / x < 0 ? "-0" : "0"; }
	const negative = x < 0;
	const a = negative ? -x : x;
	let e = Math.floor(Math.log10(a)) as int32;
	let scaled = e >= 0 ? a / Math.pow(10.0, e as float64) : a * Math.pow(10.0, (-e) as float64);
	if (scaled < 1.0) {
		e -= 1;
		scaled = e >= 0 ? a / Math.pow(10.0, e as float64) : a * Math.pow(10.0, (-e) as float64);
	} else if (scaled >= 10.0) {
		e += 1;
		scaled = e >= 0 ? a / Math.pow(10.0, e as float64) : a * Math.pow(10.0, (-e) as float64);
	}
	const product = scaled * 100000.0;
	const below = Math.floor(product);
	let digits = product - below == 0.5 ? (below % 2 == 0 ? below : below + 1.0) : Math.round(product);
	if (digits >= 1000000.0) {
		digits = digits / 10.0;
		e += 1;
	}
	let text = `${digits as int64}`;
	let out = "";
	if (e < -4 || e >= 6) {
		let tail = text.byteSlice(1, 6);
		while (tail.byteLength() > 0 && tail.byteAt(tail.byteLength() - 1) == 48) {
			tail = tail.byteSlice(0, tail.byteLength() - 1);
		}
		out = text.byteSlice(0, 1) + (tail.byteLength() > 0 ? "." + tail : "");
		const magnitude = e < 0 ? -e : e;
		out += (e < 0 ? "e-" : "e+") + (magnitude < 10 ? "0" : "") + `${magnitude}`;
	} else if (e >= 0) {
		const whole = text.byteSlice(0, e + 1);
		let fraction = text.byteSlice(e + 1, 6);
		while (fraction.byteLength() > 0 && fraction.byteAt(fraction.byteLength() - 1) == 48) {
			fraction = fraction.byteSlice(0, fraction.byteLength() - 1);
		}
		out = whole + (fraction.byteLength() > 0 ? "." + fraction : "");
	} else {
		let zeros = "";
		for (let i: int32 = 0; i < -e - 1; i++) { zeros += "0"; }
		let fraction = zeros + text;
		while (fraction.byteAt(fraction.byteLength() - 1) == 48) {
			fraction = fraction.byteSlice(0, fraction.byteLength() - 1);
		}
		out = "0." + fraction;
	}
	return negative ? "-" + out : out;
}
