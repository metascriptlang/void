import { KB_SHAPE_TABLE_NAMES, kbShapeValues, kbShapeDigest } from "./kbShapeTablesDigest";

const KB_SHAPE_PINS: string[] = [
	"scriptTags 3905311479 170",
	"scriptShapers 2432235388 170",
	"indicVirama 419854194 170",
	"indicBlwfPostOnly 2920628053 170",
	"indicRephPosition 1096159038 170",
	"indicRephEncoding 3294056724 170",
	"indicRightMatra 519161084 170",
	"indicAboveMatra 3489129501 170",
	"indicBelowMatra 1202546650 170",
	"indicTransition 2827478064 820",
	"myanmarTransition 3569675236 1147",
	"khmerTransition 2813541574 621",
	"useTransition 1046306154 1764",
	"opListDefault 1280823433 25",
	"opListHangul 2055017884 26",
	"opListArabicRclt 521889415 93",
	"opListArabicNoRclt 3823137885 99",
	"opListIndic 1268164039 107",
	"opListKhmer 707396363 41",
	"opListMyanmar 3109585199 65",
	"opListTibetan 2580931479 30",
	"opListUse 1590426959 66",
	"shaperOpLists 759323792 478",
	"syllableFeatureSet 2866344347 4",
	"invalidIndicCluster 1014537151 2499",
	"scriptTagToScript 1794899878 2512",
];

function differs(name: string, digest: uint32, count: int32, pin: string[]): void {
	console.log(`DIFFERS ${name}: ${digest} of ${count} vs ${pin[1]} of ${pin[2]}`);
}

test "the generated kb shaping tables reproduce the digests recorded from the C" {
	assert KB_SHAPE_PINS.length == KB_SHAPE_TABLE_NAMES.length;
	let bad: int32 = 0;
	for (let table: int32 = 0; table < KB_SHAPE_PINS.length; table++) {
		const pin = KB_SHAPE_PINS[table].split(" ");
		assert pin[0] == KB_SHAPE_TABLE_NAMES[table];
		const values = kbShapeValues(table);
		const digest = kbShapeDigest(values);
		if (`${digest}` != pin[1] || `${values.length}` != pin[2]) {
			bad++;
			differs(pin[0], digest, values.length as int32, pin);
		}
	}
	assert bad == 0;
}
