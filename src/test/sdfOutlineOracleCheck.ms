import "../void2d/textSdfSwitch";
import "../void2d/textOutlineSwitch";
import { loadFace, glyphIndex, pageTexel } from "../void2d/face";
import {
	GlyphAtlas,
	GlyphKey,
	GlyphTile,
	PageKind,
	acquireOutline,
	acquireSdf,
	acquireSdfOutline,
} from "../void2d/glyphAtlas";
import { SDF_EM, sdfCoverage, sampleField } from "../void2d/textSdf";

const BASE_PX: float32 = 16.0;
const SUPERSAMPLE: int32 = 4;
const PI: float32 = 3.14159265;
const OUTLINE_LOCAL: float32 = 1.5;
const SDF_LANE: int32 = 24;

struct Measure {
	mae: float32;
	p99: float32;
	ink: float32;
	pixels: int32;
}

struct Subject {
	face: int32;
	glyph: int32;
}

let subjects: Vec<Subject> = new Array(0);
const fields: GlyphAtlas = GlyphAtlas.create(1024, 3);
const references: GlyphAtlas = GlyphAtlas.create(1024, 3);

function pickSubjects(): Vec<Subject> {
	if ((subjects.length as int32) == 0) {
		const latin = try loadFace("assets/font.ttf") catch -1;
		const cjk = try loadFace("tests/fonts/NotoSansSC-subset.ttf") catch -1;
		for (const c of [65, 87, 103, 64, 56, 82, 97, 101, 115, 107, 77, 81, 106, 90, 116, 66]) {
			subjects.push({ face: latin, glyph: glyphIndex(latin, c as int32) });
		}
		let found: int32 = 0;
		for (let cp = 0x4e00; cp < 0xa000 && found < 4; cp = cp + 97) {
			const glyph: int32 = glyphIndex(cjk, cp);
			if (glyph != 0) {
				subjects.push({ face: cjk, glyph: glyph });
				found = found + 1;
			}
		}
	}
	return subjects;
}

function fieldBytes(t: GlyphTile): Vec<uint8> {
	let bytes: Vec<uint8> = new Array(0);
	const handle = fields.pageHandle(t.page);
	for (let row = 0; row < t.height; row++) {
		for (let col = 0; col < t.width; col++) {
			bytes.push(pageTexel(handle, t.x + col, t.y + row) as uint8);
		}
	}
	return bytes;
}

function measure(zoom: float32, degrees: float32): Measure {
	return measureField(zoom, degrees, false);
}

function measureField(zoom: float32, degrees: float32, plain: boolean): Measure {
	const s: float32 = BASE_PX * zoom;
	const theta: float32 = degrees * PI / (180.0 as float32);
	const cs: float32 = Math.cos(theta) as float32;
	const sn: float32 = Math.sin(theta) as float32;
	const perPixel: float32 = SDF_EM / s;
	const exact: boolean = degrees == 0.0;
	const fine: float32 = exact ? 1.0 : SUPERSAMPLE as float32;
	const refSize: float32 = s * fine;
	const refLane: int32 = Math.floor(OUTLINE_LOCAL * refSize / BASE_PX * 4.0 + 0.5) as int32;
	const n: int32 = exact ? 1 : SUPERSAMPLE;
	let histogram: Vec<int32> = new Array(256);
	for (let b = 0; b < 256; b++) { histogram[b] = 0; }
	let sumError: float32 = 0.0;
	let counted: int32 = 0;
	let sdfInk: float32 = 0.0;
	let refInk: float32 = 0.0;
	for (const subject of pickSubjects()) {
		const acquired = plain
			? fields.acquireSdf(subject.face, subject.glyph)
			: fields.acquireSdfOutline(subject.face, subject.glyph, SDF_LANE);
		if (!acquired.ok) {
			console.log(`sdfOutlineOracle: glyph ${subject.glyph} was refused`);
			unreachable;
		}
		const t: GlyphTile = fields.tile(acquired.value);
		fields.release(acquired.value);
		if (t.width == 0) { continue; }
		const bytes: Vec<uint8> = fieldBytes(t);
		const key: GlyphKey = {
			kind: PageKind.Coverage, face: subject.face, glyph: subject.glyph, sizePx: refSize,
			variant: 0, outline: refLane,
		};
		const reference = references.acquireOutline(key);
		if (!reference.ok) {
			console.log(`sdfOutlineOracle: reference tile of glyph ${subject.glyph} was refused`);
			unreachable;
		}
		const rt: GlyphTile = references.tile(reference.value);
		references.release(reference.value);
		const refLeft: int32 = rt.left;
		const refTop: int32 = rt.top;
		const refW: int32 = rt.width;
		const refH: int32 = rt.height;
		const refHandle = references.pageHandle(rt.page);
		const toDevice: float32 = s / SDF_EM;
		const gx0: float32 = (t.left as float32) * toDevice;
		const gx1: float32 = ((t.left + t.width) as float32) * toDevice;
		const gy0: float32 = (t.top as float32) * toDevice;
		const gy1: float32 = ((t.top + t.height) as float32) * toDevice;
		let minX: float32 = 1.0e9;
		let maxX: float32 = -1.0e9;
		let minY: float32 = 1.0e9;
		let maxY: float32 = -1.0e9;
		for (const gx of [gx0, gx1]) {
			for (const gy of [gy0, gy1]) {
				const dx: float32 = (cs * gx - sn * gy) as float32;
				const dy: float32 = (sn * gx + cs * gy) as float32;
				if (dx < minX) { minX = dx; }
				if (dx > maxX) { maxX = dx; }
				if (dy < minY) { minY = dy; }
				if (dy > maxY) { maxY = dy; }
			}
		}
		const i0: int32 = (Math.floor(minX) as int32) - 1;
		const i1: int32 = (Math.ceil(maxX) as int32) + 1;
		const j0: int32 = (Math.floor(minY) as int32) - 1;
		const j1: int32 = (Math.ceil(maxY) as int32) + 1;
		for (let j = j0; j < j1; j++) {
			for (let i = i0; i < i1; i++) {
				const cx: float32 = (i as float32) + 0.5;
				const cy: float32 = (j as float32) + 0.5;
				const u: float32 = ((cs * cx + sn * cy) as float32) * perPixel;
				const v: float32 = ((cs * cy - sn * cx) as float32) * perPixel;
				const field: float32 = sampleField(bytes, t.width, t.width, t.height,
					u - (t.left as float32), v - (t.top as float32));
				const got: float32 = sdfCoverage(field, perPixel);
				let want: float32 = 0.0;
				const step: float32 = 1.0 / (n as float32);
				let total: float32 = 0.0;
				for (let b = 0; b < n; b++) {
					for (let a = 0; a < n; a++) {
						const sx: float32 = (i as float32) + ((a as float32) + 0.5) * step;
						const sy: float32 = (j as float32) + ((b as float32) + 0.5) * step;
						const hx: float32 = ((cs * sx + sn * sy) as float32) * fine;
						const hy: float32 = ((cs * sy - sn * sx) as float32) * fine;
						const col: int32 = (Math.floor(hx) as int32) - refLeft;
						const row: int32 = (Math.floor(hy) as int32) - refTop;
						if (col >= 0 && row >= 0 && col < refW && row < refH) {
							const texel: int32 = pageTexel(refHandle, rt.x + col, rt.y + row);
							total = total + (texel as float32) / 255.0;
						}
					}
				}
				want = total * step * step;
				sdfInk = sdfInk + got;
				refInk = refInk + want;
				if (got == 0.0 && want == 0.0) { continue; }
				let error: float32 = got - want;
				if (error < 0.0) { error = -error; }
				sumError = sumError + error;
				counted = counted + 1;
				const bin: int32 = Math.floor(error * 255.0 + 0.5) as int32;
				histogram[bin] = histogram[bin] + 1;
			}
		}
	}
	let seen: int32 = 0;
	let p99: float32 = 1.0;
	for (let b = 0; b < 256; b++) {
		seen = seen + histogram[b];
		if ((seen as float32) >= (counted as float32) * 0.99) {
			p99 = (b as float32) / 255.0;
			break;
		}
	}
	return {
		mae: sumError / (counted as float32),
		p99: p99,
		ink: sdfInk / refInk,
		pixels: counted,
	};
}

test "one 32 px outline field reads as the coverage outline within the measured bounds" {
	for (const zoom of [0.5, 1.0, 2.0, 3.0, 4.0]) {
		for (const degrees of [0.0, 17.0, 45.0, 90.0]) {
			const m = measure(zoom as float32, degrees as float32);
			console.log(
				`sdfOutlineOracle zoom ${zoom} rot ${degrees}: ` +
				`mae ${m.mae} p99 ${m.p99} ink ${m.ink} px ${m.pixels}`,
			);
			assert m.pixels > 400;
			assert m.ink > 0.96 && m.ink < 1.02;
			if (zoom < 1.0) {
				assert m.mae < 0.04;
				assert m.p99 < 0.30;
			} else {
				assert m.mae < 0.016;
				assert m.p99 < 0.14;
			}
		}
	}
}

test "the control: the field without its outline bias fails the same bounds" {
	for (const degrees of [0.0, 17.0, 45.0]) {
		const m = measureField(2.0, degrees as float32, true);
		console.log(`sdfOutlineOracle control rot ${degrees}: mae ${m.mae} ink ${m.ink}`);
		assert m.mae > 0.05;
		assert m.ink < 0.8;
	}
}
