import {
	CAP_BUTT,
	CAP_ROUND,
	CAP_SQUARE,
	FILLRULE_EVENODD,
	FILLRULE_NONZERO,
	JOIN_BEVEL,
	JOIN_MITER,
	JOIN_ROUND,
	MAX_DASHES,
	PAINT_COLOR,
	PAINT_LINEAR_GRADIENT,
	PAINT_NONE,
	PAINT_ORDER_FILL,
	PAINT_ORDER_MARKERS,
	PAINT_ORDER_STROKE,
	PAINT_RADIAL_GRADIENT,
	PAINT_UNDEF,
	Gradient,
	GradientStop,
	Path,
	Shape,
	SvgImage,
} from "./image";
import {
	Str,
	atofFloat,
	ch,
	contains,
	eq,
	floatToByte,
	floatToInt,
	isDigit,
	isSpace,
	numberEnd,
	numberItem,
	same,
	startsWith,
	sub,
} from "./text";
import {
	NSVG_KAPPA90,
	absf,
	NSVG_PI,
	curveBounds,
	maxf,
	minf,
	sqrtf,
	xformIdentity,
	xformInverse,
	xformMultiply,
	xformPointX,
	xformPointY,
	xformPremultiply,
	xformSetRotation,
	xformSetScale,
	xformSetSkewX,
	xformSetSkewY,
	xformSetTranslation,
} from "./xform";

const MAX_ATTR: int32 = 128;
const XML_MAX_ATTRIBS: int32 = 256;
const MAX_CLASSES: int32 = 32;
const MAX_STYLE_DEPTH: int32 = 64;
const ID_BYTES: int32 = 63;
const NAME_VALUE_BYTES: int32 = 511;

const UNITS_USER: int32 = 0;
const UNITS_PX: int32 = 1;
const UNITS_PT: int32 = 2;
const UNITS_PC: int32 = 3;
const UNITS_MM: int32 = 4;
const UNITS_CM: int32 = 5;
const UNITS_IN: int32 = 6;
const UNITS_PERCENT: int32 = 7;
const UNITS_EM: int32 = 8;
const UNITS_EX: int32 = 9;

const USER_SPACE: int32 = 0;
const OBJECT_SPACE: int32 = 1;

const ALIGN_MIN: int32 = 0;
const ALIGN_MID: int32 = 1;
const ALIGN_MAX: int32 = 2;
const ALIGN_NONE: int32 = 0;
const ALIGN_MEET: int32 = 1;
const ALIGN_SLICE: int32 = 2;

const COORD_SLOTS: int32 = 5;

struct Attr {
	name: Str;
	value: Str;
}

class Attrib {
	xform: float32[] = [1, 0, 0, 1, 0, 0];
	opacity: float32 = 1.0;
	fillOpacity: float32 = 1.0;
	strokeOpacity: float32 = 1.0;
	fillGradient: uint8[] = [];
	strokeGradient: uint8[] = [];
	strokeWidth: float32 = 1.0;
	strokeDashOffset: float32 = 0.0;
	strokeDashArray: float32[] = [0, 0, 0, 0, 0, 0, 0, 0];
	strokeDashCount: int32 = 0;
	strokeLineJoin: int32 = JOIN_MITER;
	strokeLineCap: int32 = CAP_BUTT;
	miterLimit: float32 = 4.0;
	fillRule: int32 = FILLRULE_NONZERO;
	fontSize: float32 = 0.0;
	stopOpacity: float32 = 1.0;
	stopOffset: float32 = 0.0;
	hasFill: int32 = 1;
	hasStroke: int32 = 0;
	visible: boolean = true;
	paintOrder: int32 = 0;
}

function copyFloats(source: float32[]): float32[] {
	const copy: float32[] = [];
	for (let i: int32 = 0; i < (source.length as int32); i++) { copy.push(source[i]); }
	return copy;
}

function cloneAttrib(source: Attrib): Attrib {
	const a = new Attrib();
	a.xform = copyFloats(source.xform);
	a.opacity = source.opacity;
	a.fillOpacity = source.fillOpacity;
	a.strokeOpacity = source.strokeOpacity;
	a.fillGradient = source.fillGradient;
	a.strokeGradient = source.strokeGradient;
	a.strokeWidth = source.strokeWidth;
	a.strokeDashOffset = source.strokeDashOffset;
	a.strokeDashArray = copyFloats(source.strokeDashArray);
	a.strokeDashCount = source.strokeDashCount;
	a.strokeLineJoin = source.strokeLineJoin;
	a.strokeLineCap = source.strokeLineCap;
	a.miterLimit = source.miterLimit;
	a.fillRule = source.fillRule;
	a.fontSize = source.fontSize;
	a.stopOpacity = source.stopOpacity;
	a.stopOffset = source.stopOffset;
	a.hasFill = source.hasFill;
	a.hasStroke = source.hasStroke;
	a.visible = source.visible;
	a.paintOrder = source.paintOrder;
	return a;
}

function encodePaintOrder(a: int32, b: int32, c: int32): int32 {
	return (a & 3) | ((b & 3) << 2) | ((c & 3) << 4);
}

struct Coord {
	value: float32;
	units: int32;
}

class GradientData {
	id: uint8[] = [];
	ref: uint8[] = [];
	kind: int32 = PAINT_NONE;
	coords: Coord[] = [];
	units: int32 = OBJECT_SPACE;
	xform: float32[] = [1, 0, 0, 1, 0, 0];
	stops: GradientStop[] = [];
}

struct StyleDecl {
	className: Str;
	properties: Str;
}

class Pen {
	cpx: float32 = 0.0;
	cpy: float32 = 0.0;
	cpx2: float32 = 0.0;
	cpy2: float32 = 0.0;
}

class Item {
	from: int32 = 0;
	to: int32 = 0;
}

class Parser {
	attrs: Attrib[] = [];
	head: int32 = 0;
	pts: float32[] = [];
	npts: int32 = 0;
	plist: Path[] = [];
	shapes: Shape[] = [];
	styles: StyleDecl[] = [];
	gradients: GradientData[] = [];
	imageWidth: float32 = 0.0;
	imageHeight: float32 = 0.0;
	viewMinx: float32 = 0.0;
	viewMiny: float32 = 0.0;
	viewWidth: float32 = 0.0;
	viewHeight: float32 = 0.0;
	alignX: int32 = 0;
	alignY: int32 = 0;
	alignType: int32 = 0;
	dpi: float32 = 0.0;
	pathFlag: boolean = false;
	defsFlag: boolean = false;
	styleFlag: boolean = false;
	styleDepth: int32 = 0;
	source: uint8[] = [];
}

function createParser(source: uint8[], dpi: float32): Parser {
	const p = new Parser();
	p.source = source;
	p.dpi = dpi;
	const first = new Attrib();
	first.paintOrder = encodePaintOrder(PAINT_ORDER_FILL, PAINT_ORDER_STROKE, PAINT_ORDER_MARKERS);
	p.attrs.push(first);
	return p;
}

function curAttr(p: Parser): Attrib {
	return p.attrs[p.head];
}

function pushAttr(p: Parser): void {
	if (p.head < MAX_ATTR - 1) {
		const copy = cloneAttrib(p.attrs[p.head]);
		p.head += 1;
		if (p.head < (p.attrs.length as int32)) {
			p.attrs[p.head] = copy;
		} else {
			p.attrs.push(copy);
		}
	}
}

function popAttr(p: Parser): void {
	if (p.head > 0) { p.head -= 1; }
}

function resetPath(p: Parser): void {
	p.npts = 0;
}

function addPoint(p: Parser, x: float32, y: float32): void {
	const k = p.npts * 2;
	if (k + 2 > (p.pts.length as int32)) {
		p.pts.push(x);
		p.pts.push(y);
	} else {
		p.pts[k] = x;
		p.pts[k + 1] = y;
	}
	p.npts += 1;
}

function moveTo(p: Parser, x: float32, y: float32): void {
	if (p.npts > 0) {
		p.pts[(p.npts - 1) * 2] = x;
		p.pts[(p.npts - 1) * 2 + 1] = y;
	} else {
		addPoint(p, x, y);
	}
}

function lineTo(p: Parser, x: float32, y: float32): void {
	if (p.npts > 0) {
		const px = p.pts[(p.npts - 1) * 2];
		const py = p.pts[(p.npts - 1) * 2 + 1];
		const dx: float32 = x - px;
		const dy: float32 = y - py;
		const ax: float32 = px + dx / 3.0;
		const ay: float32 = py + dy / 3.0;
		const bx: float32 = x - dx / 3.0;
		const by: float32 = y - dy / 3.0;
		addPoint(p, ax, ay);
		addPoint(p, bx, by);
		addPoint(p, x, y);
	}
}

function cubicBezTo(
	p: Parser,
	cpx1: float32,
	cpy1: float32,
	cpx2: float32,
	cpy2: float32,
	x: float32,
	y: float32,
): void {
	if (p.npts > 0) {
		addPoint(p, cpx1, cpy1);
		addPoint(p, cpx2, cpy2);
		addPoint(p, x, y);
	}
}

function actualLength(p: Parser): float32 {
	const w = p.viewWidth;
	const h = p.viewHeight;
	const sum: float32 = w * w + h * h;
	return sqrtf(sum) / sqrtf(2.0);
}

function convertToPixels(
	p: Parser,
	value: float32,
	units: int32,
	orig: float32,
	length: float32,
): float32 {
	const attr = curAttr(p);
	const result: float32 = match (units) {
		UNITS_USER => value,
		UNITS_PX => value,
		UNITS_PT => value / 72.0 * p.dpi,
		UNITS_PC => value / 6.0 * p.dpi,
		UNITS_MM => value / 25.4 * p.dpi,
		UNITS_CM => value / 2.54 * p.dpi,
		UNITS_IN => value * p.dpi,
		UNITS_EM => value * attr.fontSize,
		UNITS_EX => value * attr.fontSize * 0.52,
		UNITS_PERCENT => orig + value / 100.0 * length,
		_ => value,
	};
	return result;
}

function bytesEqual(a: uint8[], b: uint8[]): boolean {
	if (a.length != b.length) { return false; }
	for (let i: int32 = 0; i < (a.length as int32); i++) {
		if (a[i] != b[i]) { return false; }
	}
	return true;
}

function findGradientData(p: Parser, id: uint8[]): GradientData | null {
	if (id.length == 0) { return null; }
	for (let i = (p.gradients.length as int32) - 1; i >= 0; i--) {
		if (bytesEqual(p.gradients[i].id, id)) { return p.gradients[i]; }
	}
	return null;
}

function createGradient(
	p: Parser,
	id: uint8[],
	localBounds: float32[],
	xform: float32[],
): Gradient | null {
	const data = findGradientData(p, id);
	if (data == null) { return null; }
	let ref: GradientData | null = data;
	let stops: GradientStop[] | null = null;
	let refIter: int32 = 0;
	while (ref != null) {
		if (stops == null && ref.stops.length > 0) {
			stops = ref.stops;
			break;
		}
		const nextRef = findGradientData(p, ref.ref);
		if (nextRef == ref) { break; }
		ref = nextRef;
		refIter += 1;
		if (refIter > 32) { break; }
	}
	if (stops == null) { return null; }

	let ox: float32 = 0.0;
	let oy: float32 = 0.0;
	let sw: float32 = 0.0;
	let sh: float32 = 0.0;
	if (data.units == OBJECT_SPACE) {
		ox = localBounds[0];
		oy = localBounds[1];
		sw = localBounds[2] - localBounds[0];
		sh = localBounds[3] - localBounds[1];
	} else {
		ox = p.viewMinx;
		oy = p.viewMiny;
		sw = p.viewWidth;
		sh = p.viewHeight;
	}
	const sumSq: float32 = sw * sw + sh * sh;
	const sl: float32 = sqrtf(sumSq) / sqrtf(2.0);

	const grad = new Gradient();
	const c = data.coords;
	if (data.kind == PAINT_LINEAR_GRADIENT) {
		const x1 = convertToPixels(p, c[0].value, c[0].units, ox, sw);
		const y1 = convertToPixels(p, c[1].value, c[1].units, oy, sh);
		const x2 = convertToPixels(p, c[2].value, c[2].units, ox, sw);
		const y2 = convertToPixels(p, c[3].value, c[3].units, oy, sh);
		const dx: float32 = x2 - x1;
		const dy: float32 = y2 - y1;
		grad.xform[0] = dy;
		grad.xform[1] = -dx;
		grad.xform[2] = dx;
		grad.xform[3] = dy;
		grad.xform[4] = x1;
		grad.xform[5] = y1;
	} else {
		const cx = convertToPixels(p, c[0].value, c[0].units, ox, sw);
		const cy = convertToPixels(p, c[1].value, c[1].units, oy, sh);
		const r = convertToPixels(p, c[2].value, c[2].units, 0.0, sl);
		grad.xform[0] = r;
		grad.xform[1] = 0.0;
		grad.xform[2] = 0.0;
		grad.xform[3] = r;
		grad.xform[4] = cx;
		grad.xform[5] = cy;
	}
	xformMultiply(grad.xform, data.xform);
	xformMultiply(grad.xform, xform);
	for (let i: int32 = 0; i < (stops.length as int32); i++) {
		const stop = new GradientStop();
		stop.alpha = stops[i].alpha;
		stop.offset = stops[i].offset;
		grad.stops.push(stop);
	}
	return grad;
}

function getAverageScale(t: float32[]): float32 {
	const sxSq: float32 = t[0] * t[0] + t[2] * t[2];
	const sySq: float32 = t[1] * t[1] + t[3] * t[3];
	const sx: float32 = sqrtf(sxSq);
	const sy: float32 = sqrtf(sySq);
	const average: float32 = (sx + sy) * 0.5;
	return average;
}

// nsvg__getLocalBounds: false when the shape has no curve, as the untouched bounds are then unset.
function getLocalBounds(bounds: float32[], shape: Shape, xform: float32[]): void {
	const curve: float32[] = [0, 0, 0, 0, 0, 0, 0, 0];
	const box: float32[] = [0, 0, 0, 0];
	let first = true;
	for (let k: int32 = 0; k < (shape.paths.length as int32); k++) {
		const path = shape.paths[k];
		curve[0] = xformPointX(path.pts[0], path.pts[1], xform);
		curve[1] = xformPointY(path.pts[0], path.pts[1], xform);
		for (let i: int32 = 0; i < path.npts - 1; i += 3) {
			const a = path.pts[(i + 1) * 2];
			const b = path.pts[(i + 1) * 2 + 1];
			curve[2] = xformPointX(a, b, xform);
			curve[3] = xformPointY(a, b, xform);
			const c = path.pts[(i + 2) * 2];
			const d = path.pts[(i + 2) * 2 + 1];
			curve[4] = xformPointX(c, d, xform);
			curve[5] = xformPointY(c, d, xform);
			const e = path.pts[(i + 3) * 2];
			const f = path.pts[(i + 3) * 2 + 1];
			curve[6] = xformPointX(e, f, xform);
			curve[7] = xformPointY(e, f, xform);
			curveBounds(box, curve, 0);
			if (first) {
				bounds[0] = box[0];
				bounds[1] = box[1];
				bounds[2] = box[2];
				bounds[3] = box[3];
				first = false;
			} else {
				bounds[0] = minf(bounds[0], box[0]);
				bounds[1] = minf(bounds[1], box[1]);
				bounds[2] = maxf(bounds[2], box[2]);
				bounds[3] = maxf(bounds[3], box[3]);
			}
			curve[0] = curve[6];
			curve[1] = curve[7];
		}
	}
}

function addShape(p: Parser): void {
	const attr = curAttr(p);
	if (p.plist.length == 0) { return; }
	const shape = new Shape();
	shape.fillGradient = attr.fillGradient;
	shape.strokeGradient = attr.strokeGradient;
	shape.xform = copyFloats(attr.xform);
	const scale = getAverageScale(attr.xform);
	shape.strokeWidth = attr.strokeWidth * scale;
	shape.strokeDashOffset = attr.strokeDashOffset * scale;
	shape.strokeDashCount = attr.strokeDashCount;
	for (let i: int32 = 0; i < attr.strokeDashCount; i++) {
		shape.strokeDashArray[i] = attr.strokeDashArray[i] * scale;
	}
	shape.strokeLineJoin = attr.strokeLineJoin;
	shape.strokeLineCap = attr.strokeLineCap;
	shape.miterLimit = attr.miterLimit;
	shape.fillRule = attr.fillRule;
	shape.opacity = attr.opacity;
	shape.paintOrder = attr.paintOrder;

	for (let i = (p.plist.length as int32) - 1; i >= 0; i--) { shape.paths.push(p.plist[i]); }
	p.plist = [];

	const first = shape.paths[0];
	shape.bounds[0] = first.bounds[0];
	shape.bounds[1] = first.bounds[1];
	shape.bounds[2] = first.bounds[2];
	shape.bounds[3] = first.bounds[3];
	for (let i: int32 = 1; i < (shape.paths.length as int32); i++) {
		const path = shape.paths[i];
		shape.bounds[0] = minf(shape.bounds[0], path.bounds[0]);
		shape.bounds[1] = minf(shape.bounds[1], path.bounds[1]);
		shape.bounds[2] = maxf(shape.bounds[2], path.bounds[2]);
		shape.bounds[3] = maxf(shape.bounds[3], path.bounds[3]);
	}

	if (attr.hasFill == 0) {
		shape.fill.kind = PAINT_NONE;
	} else if (attr.hasFill == 1) {
		shape.fill.kind = PAINT_COLOR;
		const scaled: float32 = attr.fillOpacity * 255;
		shape.fill.alpha = floatToByte(scaled);
	} else if (attr.hasFill == 2) {
		shape.fill.kind = PAINT_UNDEF;
	}
	if (attr.hasStroke == 0) {
		shape.stroke.kind = PAINT_NONE;
	} else if (attr.hasStroke == 1) {
		shape.stroke.kind = PAINT_COLOR;
		const scaled: float32 = attr.strokeOpacity * 255;
		shape.stroke.alpha = floatToByte(scaled);
	} else if (attr.hasStroke == 2) {
		shape.stroke.kind = PAINT_UNDEF;
	}
	shape.visible = attr.visible;
	p.shapes.push(shape);
}

function addPath(p: Parser, closed: boolean): void {
	const attr = curAttr(p);
	if (p.npts < 4) { return; }
	if (closed) { lineTo(p, p.pts[0], p.pts[1]); }
	if ((p.npts % 3) != 1) { return; }

	const path = new Path();
	path.closed = closed;
	path.npts = p.npts;
	for (let i: int32 = 0; i < p.npts; i++) {
		path.pts.push(xformPointX(p.pts[i * 2], p.pts[i * 2 + 1], attr.xform));
		path.pts.push(xformPointY(p.pts[i * 2], p.pts[i * 2 + 1], attr.xform));
	}
	const box: float32[] = [0, 0, 0, 0];
	for (let i: int32 = 0; i < path.npts - 1; i += 3) {
		curveBounds(box, path.pts, i * 2);
		if (i == 0) {
			path.bounds[0] = box[0];
			path.bounds[1] = box[1];
			path.bounds[2] = box[2];
			path.bounds[3] = box[3];
		} else {
			path.bounds[0] = minf(path.bounds[0], box[0]);
			path.bounds[1] = minf(path.bounds[1], box[1]);
			path.bounds[2] = maxf(path.bounds[2], box[2]);
			path.bounds[3] = maxf(path.bounds[3], box[3]);
		}
	}
	p.plist.push(path);
}

function parseOpacity(value: Str): float32 {
	let val: float32 = atofFloat(value);
	if (val < 0.0) { val = 0.0; }
	if (val > 1.0) { val = 1.0; }
	return val;
}

function parseMiterLimit(value: Str): float32 {
	let val: float32 = atofFloat(value);
	if (val < 0.0) { val = 0.0; }
	return val;
}

function parseUnits(x: Str, at: int32): int32 {
	const a = x.ch(at);
	const b = x.ch(at + 1);
	if (a == 112 && b == 120) { return UNITS_PX; }
	if (a == 112 && b == 116) { return UNITS_PT; }
	if (a == 112 && b == 99) { return UNITS_PC; }
	if (a == 109 && b == 109) { return UNITS_MM; }
	if (a == 99 && b == 109) { return UNITS_CM; }
	if (a == 105 && b == 110) { return UNITS_IN; }
	if (a == 37) { return UNITS_PERCENT; }
	if (a == 101 && b == 109) { return UNITS_EM; }
	if (a == 101 && b == 120) { return UNITS_EX; }
	return UNITS_USER;
}

function isCoordinate(x: Str): boolean {
	let at: int32 = 0;
	const c = x.ch(0);
	if (c == 45 || c == 43) { at = 1; }
	return isDigit(x.ch(at)) || x.ch(at) == 46;
}

function parseCoordinateRaw(x: Str): Coord {
	const end = numberEnd(x, 0);
	const units = parseUnits(x, end);
	const value = atofFloat(numberItem(x, 0, end));
	return { value: value, units: units };
}

function parseCoordinate(p: Parser, x: Str, orig: float32, length: float32): float32 {
	const coord = parseCoordinateRaw(x);
	return convertToPixels(p, coord.value, coord.units, orig, length);
}

// nsvg__parseTransformArgs: the argument count lands in na[0]; the result is the C's length.
function parseTransformArgs(x: Str, args: float32[], maxNa: int32, na: int32[]): int32 {
	na[0] = 0;
	let ptr: int32 = 0;
	while (x.ch(ptr) != 0 && x.ch(ptr) != 40) { ptr += 1; }
	if (x.ch(ptr) == 0) { return 1; }
	let end = ptr;
	while (x.ch(end) != 0 && x.ch(end) != 41) { end += 1; }
	if (x.ch(end) == 0) { return 1; }
	while (ptr < end) {
		const c = x.ch(ptr);
		if (c == 45 || c == 43 || c == 46 || isDigit(c)) {
			if (na[0] >= maxNa) { return 0; }
			const stop = numberEnd(x, ptr);
			args[na[0]] = atofFloat(numberItem(x, ptr, stop));
			na[0] += 1;
			ptr = stop;
		} else {
			ptr += 1;
		}
	}
	return end;
}

function copySix(target: float32[], source: float32[]): void {
	for (let i: int32 = 0; i < 6; i++) { target[i] = source[i]; }
}

function parseMatrix(xform: float32[], x: Str): int32 {
	const t: float32[] = [0, 0, 0, 0, 0, 0];
	const na: int32[] = [0];
	const len = parseTransformArgs(x, t, 6, na);
	if (na[0] != 6) { return len; }
	copySix(xform, t);
	return len;
}

function parseTranslate(xform: float32[], x: Str): int32 {
	const args: float32[] = [0, 0];
	const t: float32[] = [0, 0, 0, 0, 0, 0];
	const na: int32[] = [0];
	const len = parseTransformArgs(x, args, 2, na);
	if (na[0] == 1) { args[1] = 0.0; }
	xformSetTranslation(t, args[0], args[1]);
	copySix(xform, t);
	return len;
}

function parseScale(xform: float32[], x: Str): int32 {
	const args: float32[] = [0, 0];
	const t: float32[] = [0, 0, 0, 0, 0, 0];
	const na: int32[] = [0];
	const len = parseTransformArgs(x, args, 2, na);
	if (na[0] == 1) { args[1] = args[0]; }
	xformSetScale(t, args[0], args[1]);
	copySix(xform, t);
	return len;
}

function parseSkewX(xform: float32[], x: Str): int32 {
	const args: float32[] = [0];
	const t: float32[] = [0, 0, 0, 0, 0, 0];
	const na: int32[] = [0];
	const len = parseTransformArgs(x, args, 1, na);
	const angle: float32 = args[0] / 180.0 * NSVG_PI;
	xformSetSkewX(t, angle);
	copySix(xform, t);
	return len;
}

function parseSkewY(xform: float32[], x: Str): int32 {
	const args: float32[] = [0];
	const t: float32[] = [0, 0, 0, 0, 0, 0];
	const na: int32[] = [0];
	const len = parseTransformArgs(x, args, 1, na);
	const angle: float32 = args[0] / 180.0 * NSVG_PI;
	xformSetSkewY(t, angle);
	copySix(xform, t);
	return len;
}

function parseRotate(xform: float32[], x: Str): int32 {
	const args: float32[] = [0, 0, 0];
	const m: float32[] = [0, 0, 0, 0, 0, 0];
	const t: float32[] = [0, 0, 0, 0, 0, 0];
	const na: int32[] = [0];
	const len = parseTransformArgs(x, args, 3, na);
	if (na[0] == 1) {
		args[1] = 0.0;
		args[2] = 0.0;
	}
	xformIdentity(m);
	if (na[0] > 1) {
		xformSetTranslation(t, -args[1], -args[2]);
		xformMultiply(m, t);
	}
	const angle: float32 = args[0] / 180.0 * NSVG_PI;
	xformSetRotation(t, angle);
	xformMultiply(m, t);
	if (na[0] > 1) {
		xformSetTranslation(t, args[1], args[2]);
		xformMultiply(m, t);
	}
	copySix(xform, m);
	return len;
}

// The C leaves `t` unset when matrix() has other than six numbers and reads whatever the last
// transform left there; t starts as the identity here and persists the same way.
function parseTransform(xform: float32[], x: Str): void {
	const t: float32[] = [1, 0, 0, 1, 0, 0];
	xformIdentity(xform);
	let at: int32 = 0;
	while (x.ch(at) != 0) {
		const rest = x.sub(at, x.e - x.s);
		let len: int32 = 0;
		if (rest.startsWith("matrix")) {
			len = parseMatrix(t, rest);
		} else if (rest.startsWith("translate")) {
			len = parseTranslate(t, rest);
		} else if (rest.startsWith("scale")) {
			len = parseScale(t, rest);
		} else if (rest.startsWith("rotate")) {
			len = parseRotate(t, rest);
		} else if (rest.startsWith("skewX")) {
			len = parseSkewX(t, rest);
		} else if (rest.startsWith("skewY")) {
			len = parseSkewY(t, rest);
		} else {
			at += 1;
			continue;
		}
		if (len != 0) {
			at += len;
		} else {
			at += 1;
			continue;
		}
		xformPremultiply(xform, t);
	}
}

function parseUrl(x: Str): uint8[] {
	const id: uint8[] = [];
	let i: int32 = 4;
	if (x.ch(i) == 35) { i += 1; }
	while (id.length < ID_BYTES && x.ch(i) != 0 && x.ch(i) != 41) {
		id.push(x.ch(i) as uint8);
		i += 1;
	}
	return id;
}

function bytesOf(x: Str, limit: int32): uint8[] {
	const out: uint8[] = [];
	let i: int32 = 0;
	while (i < limit && x.ch(i) != 0) {
		out.push(x.ch(i) as uint8);
		i += 1;
	}
	return out;
}

function parseLineCap(x: Str): int32 {
	if (x.eq("butt")) { return CAP_BUTT; }
	if (x.eq("round")) { return CAP_ROUND; }
	if (x.eq("square")) { return CAP_SQUARE; }
	return CAP_BUTT;
}

function parseLineJoin(x: Str): int32 {
	if (x.eq("miter")) { return JOIN_MITER; }
	if (x.eq("round")) { return JOIN_ROUND; }
	if (x.eq("bevel")) { return JOIN_BEVEL; }
	return JOIN_MITER;
}

function parseFillRule(x: Str): int32 {
	if (x.eq("nonzero")) { return FILLRULE_NONZERO; }
	if (x.eq("evenodd")) { return FILLRULE_EVENODD; }
	return FILLRULE_NONZERO;
}

function parsePaintOrder(x: Str): int32 {
	if (x.eq("normal") || x.eq("fill stroke markers")) {
		return encodePaintOrder(PAINT_ORDER_FILL, PAINT_ORDER_STROKE, PAINT_ORDER_MARKERS);
	}
	if (x.eq("fill markers stroke")) {
		return encodePaintOrder(PAINT_ORDER_FILL, PAINT_ORDER_MARKERS, PAINT_ORDER_STROKE);
	}
	if (x.eq("markers fill stroke")) {
		return encodePaintOrder(PAINT_ORDER_MARKERS, PAINT_ORDER_FILL, PAINT_ORDER_STROKE);
	}
	if (x.eq("markers stroke fill")) {
		return encodePaintOrder(PAINT_ORDER_MARKERS, PAINT_ORDER_STROKE, PAINT_ORDER_FILL);
	}
	if (x.eq("stroke fill markers")) {
		return encodePaintOrder(PAINT_ORDER_STROKE, PAINT_ORDER_FILL, PAINT_ORDER_MARKERS);
	}
	if (x.eq("stroke markers fill")) {
		return encodePaintOrder(PAINT_ORDER_STROKE, PAINT_ORDER_MARKERS, PAINT_ORDER_FILL);
	}
	return encodePaintOrder(PAINT_ORDER_FILL, PAINT_ORDER_STROKE, PAINT_ORDER_MARKERS);
}

// nsvg__getNextDashItem: the item's end; the item runs from the returned start.
function nextDashItem(x: Str, from: int32, item: Item): int32 {
	let s = from;
	while (x.ch(s) != 0 && (isSpace(x.ch(s)) || x.ch(s) == 44)) { s += 1; }
	item.from = s;
	let n: int32 = 0;
	while (x.ch(s) != 0 && !isSpace(x.ch(s)) && x.ch(s) != 44) {
		n += 1;
		s += 1;
	}
	item.to = item.from + Math.min(n, 63);
	return s;
}

function parseStrokeDashArray(p: Parser, x: Str, dashes: float32[]): int32 {
	if (x.ch(0) == 110) { return 0; }
	let count: int32 = 0;
	const item = new Item();
	let s: int32 = 0;
	while (x.ch(s) != 0) {
		s = nextDashItem(x, s, item);
		if (item.to == item.from) { break; }
		if (count < MAX_DASHES) {
			const coordinate = parseCoordinate(p, x.sub(item.from, item.to), 0.0, actualLength(p));
			dashes[count] = absf(coordinate);
			count += 1;
		}
	}
	let sum: float32 = 0.0;
	for (let i: int32 = 0; i < count; i++) { sum = sum + dashes[i]; }
	if (sum <= 0.000001) { count = 0; }
	return count;
}

function applyClassStyles(p: Parser, value: Str): void {
	let cur: int32 = 0;
	while (value.ch(cur) != 0) {
		while (value.ch(cur) != 0 && isSpace(value.ch(cur))) { cur += 1; }
		if (value.ch(cur) == 0) { break; }
		const classStart = cur;
		while (value.ch(cur) != 0 && !isSpace(value.ch(cur))) { cur += 1; }
		const token = value.sub(classStart, cur);
		for (let i = (p.styles.length as int32) - 1; i >= 0; i--) {
			if (p.styles[i].className.same(token)) { parseStyle(p, p.styles[i].properties); }
		}
	}
}

function parseAttr(p: Parser, name: Str, value: Str): boolean {
	const attr = curAttr(p);
	if (name.eq("style")) {
		parseStyle(p, value);
	} else if (name.eq("display")) {
		if (value.eq("none")) { attr.visible = false; }
	} else if (name.eq("fill")) {
		if (value.eq("none")) {
			attr.hasFill = 0;
		} else if (value.startsWith("url(")) {
			attr.hasFill = 2;
			attr.fillGradient = parseUrl(value);
		} else {
			attr.hasFill = 1;
		}
	} else if (name.eq("opacity")) {
		attr.opacity = parseOpacity(value);
	} else if (name.eq("fill-opacity")) {
		attr.fillOpacity = parseOpacity(value);
	} else if (name.eq("stroke")) {
		if (value.eq("none")) {
			attr.hasStroke = 0;
		} else if (value.startsWith("url(")) {
			attr.hasStroke = 2;
			attr.strokeGradient = parseUrl(value);
		} else {
			attr.hasStroke = 1;
		}
	} else if (name.eq("stroke-width")) {
		attr.strokeWidth = parseCoordinate(p, value, 0.0, actualLength(p));
	} else if (name.eq("stroke-dasharray")) {
		attr.strokeDashCount = parseStrokeDashArray(p, value, attr.strokeDashArray);
	} else if (name.eq("stroke-dashoffset")) {
		attr.strokeDashOffset = parseCoordinate(p, value, 0.0, actualLength(p));
	} else if (name.eq("stroke-opacity")) {
		attr.strokeOpacity = parseOpacity(value);
	} else if (name.eq("stroke-linecap")) {
		attr.strokeLineCap = parseLineCap(value);
	} else if (name.eq("stroke-linejoin")) {
		attr.strokeLineJoin = parseLineJoin(value);
	} else if (name.eq("stroke-miterlimit")) {
		attr.miterLimit = parseMiterLimit(value);
	} else if (name.eq("fill-rule")) {
		attr.fillRule = parseFillRule(value);
	} else if (name.eq("font-size")) {
		attr.fontSize = parseCoordinate(p, value, 0.0, actualLength(p));
	} else if (name.eq("transform")) {
		const xform: float32[] = [0, 0, 0, 0, 0, 0];
		parseTransform(xform, value);
		xformPremultiply(attr.xform, xform);
	} else if (name.eq("stop-color")) {
		return true;
	} else if (name.eq("stop-opacity")) {
		attr.stopOpacity = parseOpacity(value);
	} else if (name.eq("offset")) {
		attr.stopOffset = parseCoordinate(p, value, 0.0, 1.0);
	} else if (name.eq("paint-order")) {
		attr.paintOrder = parsePaintOrder(value);
	} else if (name.eq("id")) {
		return true;
	} else if (name.eq("class")) {
		applyClassStyles(p, value);
	} else {
		return false;
	}
	return true;
}

function parseNameValue(p: Parser, str: Str, start: int32, end: int32): boolean {
	let at = start;
	while (at < end && str.ch(at) != 58) { at += 1; }
	let val = at;
	while (at > start && (str.ch(at) == 58 || isSpace(str.ch(at)))) { at -= 1; }
	at += 1;
	const nameLength = Math.min(at - start, NAME_VALUE_BYTES);
	const name = str.sub(start, start + nameLength);
	while (val < end && (str.ch(val) == 58 || isSpace(str.ch(val)))) { val += 1; }
	const valueLength = Math.min(end - val, NAME_VALUE_BYTES);
	const value = str.sub(val, val + valueLength);
	return parseAttr(p, name, value);
}

function parseStyle(p: Parser, str: Str): void {
	if (p.styleDepth >= MAX_STYLE_DEPTH) {
		throw new Error("void2d svg: style rules nest deeper than 64 levels, a class names itself");
	}
	p.styleDepth += 1;
	let at: int32 = 0;
	while (str.ch(at) != 0) {
		while (str.ch(at) != 0 && isSpace(str.ch(at))) { at += 1; }
		const start = at;
		while (str.ch(at) != 0 && str.ch(at) != 59) { at += 1; }
		let end = at;
		while (end > start && (str.ch(end) == 59 || isSpace(str.ch(end)))) { end -= 1; }
		end += 1;
		parseNameValue(p, str, start, end);
		if (str.ch(at) != 0) { at += 1; }
	}
	p.styleDepth -= 1;
}

function parseAttribs(p: Parser, attrs: Attr[]): void {
	for (let i: int32 = 0; i < (attrs.length as int32); i++) {
		if (attrs[i].name.eq("style")) {
			parseStyle(p, attrs[i].value);
		} else {
			parseAttr(p, attrs[i].name, attrs[i].value);
		}
	}
}

function argsPerElement(cmd: int32): int32 {
	return match (cmd) {
		118 => 1,
		86 => 1,
		104 => 1,
		72 => 1,
		109 => 2,
		77 => 2,
		108 => 2,
		76 => 2,
		116 => 2,
		84 => 2,
		113 => 4,
		81 => 4,
		115 => 4,
		83 => 4,
		99 => 6,
		67 => 6,
		97 => 7,
		65 => 7,
		122 => 0,
		90 => 0,
		_ => -1,
	};
}

function pathMoveTo(p: Parser, pen: Pen, args: float32[], rel: boolean): void {
	if (rel) {
		pen.cpx = pen.cpx + args[0];
		pen.cpy = pen.cpy + args[1];
	} else {
		pen.cpx = args[0];
		pen.cpy = args[1];
	}
	moveTo(p, pen.cpx, pen.cpy);
}

function pathLineTo(p: Parser, pen: Pen, args: float32[], rel: boolean): void {
	if (rel) {
		pen.cpx = pen.cpx + args[0];
		pen.cpy = pen.cpy + args[1];
	} else {
		pen.cpx = args[0];
		pen.cpy = args[1];
	}
	lineTo(p, pen.cpx, pen.cpy);
}

function pathHLineTo(p: Parser, pen: Pen, args: float32[], rel: boolean): void {
	if (rel) {
		pen.cpx = pen.cpx + args[0];
	} else {
		pen.cpx = args[0];
	}
	lineTo(p, pen.cpx, pen.cpy);
}

function pathVLineTo(p: Parser, pen: Pen, args: float32[], rel: boolean): void {
	if (rel) {
		pen.cpy = pen.cpy + args[0];
	} else {
		pen.cpy = args[0];
	}
	lineTo(p, pen.cpx, pen.cpy);
}

function pathCubicBezTo(p: Parser, pen: Pen, args: float32[], rel: boolean): void {
	let x2: float32 = 0.0;
	let y2: float32 = 0.0;
	let cx1: float32 = 0.0;
	let cy1: float32 = 0.0;
	let cx2: float32 = 0.0;
	let cy2: float32 = 0.0;
	if (rel) {
		cx1 = pen.cpx + args[0];
		cy1 = pen.cpy + args[1];
		cx2 = pen.cpx + args[2];
		cy2 = pen.cpy + args[3];
		x2 = pen.cpx + args[4];
		y2 = pen.cpy + args[5];
	} else {
		cx1 = args[0];
		cy1 = args[1];
		cx2 = args[2];
		cy2 = args[3];
		x2 = args[4];
		y2 = args[5];
	}
	cubicBezTo(p, cx1, cy1, cx2, cy2, x2, y2);
	pen.cpx2 = cx2;
	pen.cpy2 = cy2;
	pen.cpx = x2;
	pen.cpy = y2;
}

function pathCubicBezShortTo(p: Parser, pen: Pen, args: float32[], rel: boolean): void {
	const x1 = pen.cpx;
	const y1 = pen.cpy;
	let x2: float32 = 0.0;
	let y2: float32 = 0.0;
	let cx2: float32 = 0.0;
	let cy2: float32 = 0.0;
	if (rel) {
		cx2 = pen.cpx + args[0];
		cy2 = pen.cpy + args[1];
		x2 = pen.cpx + args[2];
		y2 = pen.cpy + args[3];
	} else {
		cx2 = args[0];
		cy2 = args[1];
		x2 = args[2];
		y2 = args[3];
	}
	const cx1: float32 = 2 * x1 - pen.cpx2;
	const cy1: float32 = 2 * y1 - pen.cpy2;
	cubicBezTo(p, cx1, cy1, cx2, cy2, x2, y2);
	pen.cpx2 = cx2;
	pen.cpy2 = cy2;
	pen.cpx = x2;
	pen.cpy = y2;
}

function quadToCubic(
	p: Parser,
	x1: float32,
	y1: float32,
	cx: float32,
	cy: float32,
	x2: float32,
	y2: float32,
): void {
	const cx1: float32 = x1 + 2.0 / 3.0 * (cx - x1);
	const cy1: float32 = y1 + 2.0 / 3.0 * (cy - y1);
	const cx2: float32 = x2 + 2.0 / 3.0 * (cx - x2);
	const cy2: float32 = y2 + 2.0 / 3.0 * (cy - y2);
	cubicBezTo(p, cx1, cy1, cx2, cy2, x2, y2);
}

function pathQuadBezTo(p: Parser, pen: Pen, args: float32[], rel: boolean): void {
	const x1 = pen.cpx;
	const y1 = pen.cpy;
	let cx: float32 = 0.0;
	let cy: float32 = 0.0;
	let x2: float32 = 0.0;
	let y2: float32 = 0.0;
	if (rel) {
		cx = pen.cpx + args[0];
		cy = pen.cpy + args[1];
		x2 = pen.cpx + args[2];
		y2 = pen.cpy + args[3];
	} else {
		cx = args[0];
		cy = args[1];
		x2 = args[2];
		y2 = args[3];
	}
	quadToCubic(p, x1, y1, cx, cy, x2, y2);
	pen.cpx2 = cx;
	pen.cpy2 = cy;
	pen.cpx = x2;
	pen.cpy = y2;
}

function pathQuadBezShortTo(p: Parser, pen: Pen, args: float32[], rel: boolean): void {
	const x1 = pen.cpx;
	const y1 = pen.cpy;
	let x2: float32 = 0.0;
	let y2: float32 = 0.0;
	if (rel) {
		x2 = pen.cpx + args[0];
		y2 = pen.cpy + args[1];
	} else {
		x2 = args[0];
		y2 = args[1];
	}
	const cx: float32 = 2 * x1 - pen.cpx2;
	const cy: float32 = 2 * y1 - pen.cpy2;
	quadToCubic(p, x1, y1, cx, cy, x2, y2);
	pen.cpx2 = cx;
	pen.cpy2 = cy;
	pen.cpx = x2;
	pen.cpy = y2;
}

function sqr(x: float32): float32 {
	const r: float32 = x * x;
	return r;
}

function vmag(x: float32, y: float32): float32 {
	const sum: float32 = x * x + y * y;
	return sqrtf(sum);
}

function vecrat(ux: float32, uy: float32, vx: float32, vy: float32): float32 {
	const dot: float32 = ux * vx + uy * vy;
	const magnitude: float32 = vmag(ux, uy) * vmag(vx, vy);
	const r: float32 = dot / magnitude;
	return r;
}

function vecang(ux: float32, uy: float32, vx: float32, vy: float32): float32 {
	let r = vecrat(ux, uy, vx, vy);
	if (r < -1.0) { r = -1.0; }
	if (r > 1.0) { r = 1.0; }
	const left: float32 = ux * vy;
	const right: float32 = uy * vx;
	const sign: float32 = left < right ? -1.0 : 1.0;
	const angle: float32 = Math.acos(r as float64) as float32;
	const result: float32 = sign * angle;
	return result;
}

function pathArcTo(p: Parser, pen: Pen, args: float32[], rel: boolean): void {
	let rx: float32 = absf(args[0]);
	let ry: float32 = absf(args[1]);
	const rotx: float32 = args[2] / 180.0 * NSVG_PI;
	const fa: int32 = (absf(args[3]) as float64) > 1e-6 ? 1 : 0;
	const fs: int32 = (absf(args[4]) as float64) > 1e-6 ? 1 : 0;
	const x1 = pen.cpx;
	const y1 = pen.cpy;
	let x2: float32 = 0.0;
	let y2: float32 = 0.0;
	if (rel) {
		x2 = pen.cpx + args[5];
		y2 = pen.cpy + args[6];
	} else {
		x2 = args[5];
		y2 = args[6];
	}

	let dx: float32 = x1 - x2;
	let dy: float32 = y1 - y2;
	let d: float32 = sqrtf(dx * dx + dy * dy);
	if (d < 0.000001 || rx < 0.000001 || ry < 0.000001) {
		lineTo(p, x2, y2);
		pen.cpx = x2;
		pen.cpy = y2;
		return;
	}

	const sinrx: float32 = Math.sin(rotx as float64) as float32;
	const cosrx: float32 = Math.cos(rotx as float64) as float32;

	const x1p: float32 = cosrx * dx / 2.0 + sinrx * dy / 2.0;
	const y1p: float32 = -sinrx * dx / 2.0 + cosrx * dy / 2.0;
	d = sqr(x1p) / sqr(rx) + sqr(y1p) / sqr(ry);
	if (d > 1) {
		d = sqrtf(d);
		rx = rx * d;
		ry = ry * d;
	}
	let s: float32 = 0.0;
	let sa: float32 = sqr(rx) * sqr(ry) - sqr(rx) * sqr(y1p) - sqr(ry) * sqr(x1p);
	const sb: float32 = sqr(rx) * sqr(y1p) + sqr(ry) * sqr(x1p);
	if (sa < 0.0) { sa = 0.0; }
	if (sb > 0.0) {
		const ratio: float32 = sa / sb;
		s = sqrtf(ratio);
	}
	if (fa == fs) { s = -s; }
	const cxp: float32 = s * rx * y1p / ry;
	const cyp: float32 = s * -ry * x1p / rx;

	const cx: float32 = (x1 + x2) / 2.0 + cosrx * cxp - sinrx * cyp;
	const cy: float32 = (y1 + y2) / 2.0 + sinrx * cxp + cosrx * cyp;

	const ux: float32 = (x1p - cxp) / rx;
	const uy: float32 = (y1p - cyp) / ry;
	const vx: float32 = (-x1p - cxp) / rx;
	const vy: float32 = (-y1p - cyp) / ry;
	const a1: float32 = vecang(1.0, 0.0, ux, uy);
	let da: float32 = vecang(ux, uy, vx, vy);

	if (fs == 0 && da > 0) {
		da = da - 2 * NSVG_PI;
	} else if (fs == 1 && da < 0) {
		da = da + 2 * NSVG_PI;
	}

	const t: float32[] = [cosrx, sinrx, -sinrx, cosrx, cx, cy];

	const divs: float32 = absf(da) / (NSVG_PI * 0.5) + 1.0;
	const ndivs: int32 = floatToInt(divs);
	let hda: float32 = (da / (ndivs as float32)) / 2.0;
	if (hda < 0.001 && hda > -0.001) {
		hda = hda * 0.5;
	} else {
		const cosHda: float32 = Math.cos(hda as float64) as float32;
		const sinHda: float32 = Math.sin(hda as float64) as float32;
		hda = (1.0 - cosHda) / sinHda;
	}
	let kappa: float32 = absf(4.0 / 3.0 * hda);
	if (da < 0.0) { kappa = -kappa; }

	let px: float32 = 0.0;
	let py: float32 = 0.0;
	let ptanx: float32 = 0.0;
	let ptany: float32 = 0.0;
	for (let i: int32 = 0; i <= ndivs; i++) {
		const fraction: float32 = (i as float32) / (ndivs as float32);
		const a: float32 = a1 + da * fraction;
		dx = Math.cos(a as float64) as float32;
		dy = Math.sin(a as float64) as float32;
		const ex: float32 = dx * rx;
		const ey: float32 = dy * ry;
		const x: float32 = ex * t[0] + ey * t[2] + t[4];
		const y: float32 = ex * t[1] + ey * t[3] + t[5];
		const tx0: float32 = -dy * rx * kappa;
		const ty0: float32 = dx * ry * kappa;
		const tanx: float32 = tx0 * t[0] + ty0 * t[2];
		const tany: float32 = tx0 * t[1] + ty0 * t[3];
		if (i > 0) { cubicBezTo(p, px + ptanx, py + ptany, x - tanx, y - tany, x, y); }
		px = x;
		py = y;
		ptanx = tanx;
		ptany = tany;
	}
	pen.cpx = x2;
	pen.cpy = y2;
}

// nsvg__getNextPathItemWhenArcFlag
function nextArcFlagItem(x: Str, from: int32, item: Item): int32 {
	item.from = from;
	item.to = from;
	let s = from;
	while (x.ch(s) != 0 && (isSpace(x.ch(s)) || x.ch(s) == 44)) { s += 1; }
	if (x.ch(s) == 0) { return s; }
	if (x.ch(s) == 48 || x.ch(s) == 49) {
		item.from = s;
		item.to = s + 1;
		return s + 1;
	}
	return s;
}

// nsvg__getNextPathItem
function nextPathItem(x: Str, from: int32, item: Item): int32 {
	let s = from;
	item.from = from;
	item.to = from;
	while (x.ch(s) != 0 && (isSpace(x.ch(s)) || x.ch(s) == 44)) { s += 1; }
	if (x.ch(s) == 0) { return s; }
	const c = x.ch(s);
	if (c == 45 || c == 43 || c == 46 || isDigit(c)) {
		const end = numberEnd(x, s);
		item.from = s;
		item.to = s + Math.min(end - s, 63);
		return end;
	}
	item.from = s;
	item.to = s + 1;
	return s + 1;
}

function itemStr(x: Str, item: Item): Str {
	return x.sub(item.from, item.to);
}

function parsePath(p: Parser, attrs: Attr[]): void {
	let d: Str = { b: [], s: 0, e: 0 };
	let hasD = false;
	for (let i: int32 = 0; i < (attrs.length as int32); i++) {
		if (attrs[i].name.eq("d")) {
			d = attrs[i].value;
			hasD = true;
		} else {
			const one: Attr[] = [attrs[i]];
			parseAttribs(p, one);
		}
	}

	if (hasD) {
		resetPath(p);
		const pen = new Pen();
		let cmd: int32 = 0;
		const args: float32[] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
		let nargs: int32 = 0;
		let rargs: int32 = 0;
		let initPoint = false;
		let closedFlag = false;
		const item = new Item();
		let s: int32 = 0;

		while (d.ch(s) != 0) {
			item.from = s;
			item.to = s;
			if ((cmd == 65 || cmd == 97) && (nargs == 3 || nargs == 4)) {
				s = nextArcFlagItem(d, s, item);
			}
			if (item.to == item.from) { s = nextPathItem(d, s, item); }
			if (item.to == item.from) { break; }
			const text = itemStr(d, item);
			if (cmd != 0 && isCoordinate(text)) {
				if (nargs < 10) {
					args[nargs] = atofFloat(text);
					nargs += 1;
				}
				if (nargs >= rargs) {
					
						if (cmd == 109 || cmd == 77) {
							pathMoveTo(p, pen, args, cmd == 109);
							cmd = cmd == 109 ? 108 : 76;
							rargs = argsPerElement(cmd);
							pen.cpx2 = pen.cpx;
							pen.cpy2 = pen.cpy;
							initPoint = true;
						} else if (cmd == 108 || cmd == 76) {
							pathLineTo(p, pen, args, cmd == 108);
							pen.cpx2 = pen.cpx;
							pen.cpy2 = pen.cpy;
						} else if (cmd == 72 || cmd == 104) {
							pathHLineTo(p, pen, args, cmd == 104);
							pen.cpx2 = pen.cpx;
							pen.cpy2 = pen.cpy;
						} else if (cmd == 86 || cmd == 118) {
							pathVLineTo(p, pen, args, cmd == 118);
							pen.cpx2 = pen.cpx;
							pen.cpy2 = pen.cpy;
						} else if (cmd == 67 || cmd == 99) {
							pathCubicBezTo(p, pen, args, cmd == 99);
						} else if (cmd == 83 || cmd == 115) {
							pathCubicBezShortTo(p, pen, args, cmd == 115);
						} else if (cmd == 81 || cmd == 113) {
							pathQuadBezTo(p, pen, args, cmd == 113);
						} else if (cmd == 84 || cmd == 116) {
							pathQuadBezShortTo(p, pen, args, cmd == 116);
						} else if (cmd == 65 || cmd == 97) {
							pathArcTo(p, pen, args, cmd == 97);
							pen.cpx2 = pen.cpx;
							pen.cpy2 = pen.cpy;
						} else {
							if (nargs >= 2) {
								pen.cpx = args[nargs - 2];
								pen.cpy = args[nargs - 1];
								pen.cpx2 = pen.cpx;
								pen.cpy2 = pen.cpy;
							}
					}
					nargs = 0;
				}
			} else {
				cmd = text.ch(0);
				if (cmd == 77 || cmd == 109) {
					if (p.npts > 0) { addPath(p, closedFlag); }
					resetPath(p);
					closedFlag = false;
					nargs = 0;
				} else if (!initPoint) {
					cmd = 0;
				}
				if (cmd == 90 || cmd == 122) {
					closedFlag = true;
					if (p.npts > 0) {
						pen.cpx = p.pts[0];
						pen.cpy = p.pts[1];
						pen.cpx2 = pen.cpx;
						pen.cpy2 = pen.cpy;
						addPath(p, closedFlag);
					}
					resetPath(p);
					moveTo(p, pen.cpx, pen.cpy);
					closedFlag = false;
					nargs = 0;
				}
				rargs = argsPerElement(cmd);
				if (rargs == -1) {
					cmd = 0;
					rargs = 0;
				}
			}
		}
		if (p.npts != 0) { addPath(p, closedFlag); }
	}
	addShape(p);
}

function parseRect(p: Parser, attrs: Attr[]): void {
	let x: float32 = 0.0;
	let y: float32 = 0.0;
	let w: float32 = 0.0;
	let h: float32 = 0.0;
	let rx: float32 = -1.0;
	let ry: float32 = -1.0;
	for (let i: int32 = 0; i < (attrs.length as int32); i++) {
		const name = attrs[i].name;
		const value = attrs[i].value;
		if (!parseAttr(p, name, value)) {
			if (name.eq("x")) { x = parseCoordinate(p, value, p.viewMinx, p.viewWidth); }
			if (name.eq("y")) { y = parseCoordinate(p, value, p.viewMiny, p.viewHeight); }
			if (name.eq("width")) { w = parseCoordinate(p, value, 0.0, p.viewWidth); }
			if (name.eq("height")) { h = parseCoordinate(p, value, 0.0, p.viewHeight); }
			if (name.eq("rx")) { rx = absf(parseCoordinate(p, value, 0.0, p.viewWidth)); }
			if (name.eq("ry")) { ry = absf(parseCoordinate(p, value, 0.0, p.viewHeight)); }
		}
	}

	if (rx < 0.0 && ry > 0.0) { rx = ry; }
	if (ry < 0.0 && rx > 0.0) { ry = rx; }
	if (rx < 0.0) { rx = 0.0; }
	if (ry < 0.0) { ry = 0.0; }
	if (rx > w / 2.0) { rx = w / 2.0; }
	if (ry > h / 2.0) { ry = h / 2.0; }

	if (w != 0.0 && h != 0.0) {
		resetPath(p);
		if (rx < 0.00001 || ry < 0.0001) {
			moveTo(p, x, y);
			lineTo(p, x + w, y);
			lineTo(p, x + w, y + h);
			lineTo(p, x, y + h);
		} else {
			const kx: float32 = rx * (1 - NSVG_KAPPA90);
			const ky: float32 = ry * (1 - NSVG_KAPPA90);
			moveTo(p, x + rx, y);
			lineTo(p, x + w - rx, y);
			cubicBezTo(p, x + w - kx, y, x + w, y + ky, x + w, y + ry);
			lineTo(p, x + w, y + h - ry);
			cubicBezTo(p, x + w, y + h - ky, x + w - kx, y + h, x + w - rx, y + h);
			lineTo(p, x + rx, y + h);
			cubicBezTo(p, x + kx, y + h, x, y + h - ky, x, y + h - ry);
			lineTo(p, x, y + ry);
			cubicBezTo(p, x, y + ky, x + kx, y, x + rx, y);
		}
		addPath(p, true);
		addShape(p);
	}
}

function parseCircle(p: Parser, attrs: Attr[]): void {
	let cx: float32 = 0.0;
	let cy: float32 = 0.0;
	let r: float32 = 0.0;
	for (let i: int32 = 0; i < (attrs.length as int32); i++) {
		const name = attrs[i].name;
		const value = attrs[i].value;
		if (!parseAttr(p, name, value)) {
			if (name.eq("cx")) { cx = parseCoordinate(p, value, p.viewMinx, p.viewWidth); }
			if (name.eq("cy")) { cy = parseCoordinate(p, value, p.viewMiny, p.viewHeight); }
			if (name.eq("r")) { r = absf(parseCoordinate(p, value, 0.0, actualLength(p))); }
		}
	}
	if (r > 0.0) {
		resetPath(p);
		moveTo(p, cx + r, cy);
		cubicBezTo(p, cx + r, cy + r * NSVG_KAPPA90, cx + r * NSVG_KAPPA90, cy + r, cx, cy + r);
		cubicBezTo(p, cx - r * NSVG_KAPPA90, cy + r, cx - r, cy + r * NSVG_KAPPA90, cx - r, cy);
		cubicBezTo(p, cx - r, cy - r * NSVG_KAPPA90, cx - r * NSVG_KAPPA90, cy - r, cx, cy - r);
		cubicBezTo(p, cx + r * NSVG_KAPPA90, cy - r, cx + r, cy - r * NSVG_KAPPA90, cx + r, cy);
		addPath(p, true);
		addShape(p);
	}
}

function parseEllipse(p: Parser, attrs: Attr[]): void {
	let cx: float32 = 0.0;
	let cy: float32 = 0.0;
	let rx: float32 = 0.0;
	let ry: float32 = 0.0;
	for (let i: int32 = 0; i < (attrs.length as int32); i++) {
		const name = attrs[i].name;
		const value = attrs[i].value;
		if (!parseAttr(p, name, value)) {
			if (name.eq("cx")) { cx = parseCoordinate(p, value, p.viewMinx, p.viewWidth); }
			if (name.eq("cy")) { cy = parseCoordinate(p, value, p.viewMiny, p.viewHeight); }
			if (name.eq("rx")) { rx = absf(parseCoordinate(p, value, 0.0, p.viewWidth)); }
			if (name.eq("ry")) { ry = absf(parseCoordinate(p, value, 0.0, p.viewHeight)); }
		}
	}
	if (rx > 0.0 && ry > 0.0) {
		resetPath(p);
		moveTo(p, cx + rx, cy);
		cubicBezTo(p, cx + rx, cy + ry * NSVG_KAPPA90, cx + rx * NSVG_KAPPA90, cy + ry, cx, cy + ry);
		cubicBezTo(p, cx - rx * NSVG_KAPPA90, cy + ry, cx - rx, cy + ry * NSVG_KAPPA90, cx - rx, cy);
		cubicBezTo(p, cx - rx, cy - ry * NSVG_KAPPA90, cx - rx * NSVG_KAPPA90, cy - ry, cx, cy - ry);
		cubicBezTo(p, cx + rx * NSVG_KAPPA90, cy - ry, cx + rx, cy - ry * NSVG_KAPPA90, cx + rx, cy);
		addPath(p, true);
		addShape(p);
	}
}

function parseLine(p: Parser, attrs: Attr[]): void {
	let x1: float32 = 0.0;
	let y1: float32 = 0.0;
	let x2: float32 = 0.0;
	let y2: float32 = 0.0;
	for (let i: int32 = 0; i < (attrs.length as int32); i++) {
		const name = attrs[i].name;
		const value = attrs[i].value;
		if (!parseAttr(p, name, value)) {
			if (name.eq("x1")) { x1 = parseCoordinate(p, value, p.viewMinx, p.viewWidth); }
			if (name.eq("y1")) { y1 = parseCoordinate(p, value, p.viewMiny, p.viewHeight); }
			if (name.eq("x2")) { x2 = parseCoordinate(p, value, p.viewMinx, p.viewWidth); }
			if (name.eq("y2")) { y2 = parseCoordinate(p, value, p.viewMiny, p.viewHeight); }
		}
	}
	resetPath(p);
	moveTo(p, x1, y1);
	lineTo(p, x2, y2);
	addPath(p, false);
	addShape(p);
}

function parsePoly(p: Parser, attrs: Attr[], closeFlag: boolean): void {
	const args: float32[] = [0, 0];
	let npts: int32 = 0;
	const item = new Item();
	resetPath(p);
	for (let i: int32 = 0; i < (attrs.length as int32); i++) {
		const name = attrs[i].name;
		const value = attrs[i].value;
		if (!parseAttr(p, name, value)) {
			if (name.eq("points")) {
				let s: int32 = 0;
				let nargs: int32 = 0;
				while (value.ch(s) != 0) {
					s = nextPathItem(value, s, item);
					args[nargs] = atofFloat(itemStr(value, item));
					nargs += 1;
					if (nargs >= 2) {
						if (npts == 0) {
							moveTo(p, args[0], args[1]);
						} else {
							lineTo(p, args[0], args[1]);
						}
						nargs = 0;
						npts += 1;
					}
				}
			}
		}
	}
	addPath(p, closeFlag);
	addShape(p);
}

// Reads up to four numbers from a viewBox, stopping at the C's early return when it runs dry.
function parseViewBox(p: Parser, x: Str): void {
	let s: int32 = 0;
	let end = numberEnd(x, s);
	p.viewMinx = atofFloat(numberItem(x, s, end));
	s = end;
	while (x.ch(s) != 0 && (isSpace(x.ch(s)) || x.ch(s) == 37 || x.ch(s) == 44)) { s += 1; }
	if (x.ch(s) == 0) { return; }
	end = numberEnd(x, s);
	p.viewMiny = atofFloat(numberItem(x, s, end));
	s = end;
	while (x.ch(s) != 0 && (isSpace(x.ch(s)) || x.ch(s) == 37 || x.ch(s) == 44)) { s += 1; }
	if (x.ch(s) == 0) { return; }
	end = numberEnd(x, s);
	p.viewWidth = atofFloat(numberItem(x, s, end));
	s = end;
	while (x.ch(s) != 0 && (isSpace(x.ch(s)) || x.ch(s) == 37 || x.ch(s) == 44)) { s += 1; }
	if (x.ch(s) == 0) { return; }
	end = numberEnd(x, s);
	p.viewHeight = atofFloat(numberItem(x, s, end));
}

// nsvg__parseSVG: a viewBox that runs dry ends the whole attribute loop, as the C returns.
function parseSvg(p: Parser, attrs: Attr[]): void {
	for (let i: int32 = 0; i < (attrs.length as int32); i++) {
		const name = attrs[i].name;
		const value = attrs[i].value;
		if (!parseAttr(p, name, value)) {
			if (name.eq("width")) {
				p.imageWidth = parseCoordinate(p, value, 0.0, 0.0);
			} else if (name.eq("height")) {
				p.imageHeight = parseCoordinate(p, value, 0.0, 0.0);
			} else if (name.eq("viewBox")) {
				const before = p.viewHeight;
				const dryEnd = viewBoxRunsDry(value);
				parseViewBox(p, value);
				if (dryEnd) { return; }
				if (before != before) { return; }
			} else if (name.eq("preserveAspectRatio")) {
				if (value.contains("none")) {
					p.alignType = ALIGN_NONE;
				} else {
					if (value.contains("xMin")) {
						p.alignX = ALIGN_MIN;
					} else if (value.contains("xMid")) {
						p.alignX = ALIGN_MID;
					} else if (value.contains("xMax")) {
						p.alignX = ALIGN_MAX;
					}
					if (value.contains("yMin")) {
						p.alignY = ALIGN_MIN;
					} else if (value.contains("yMid")) {
						p.alignY = ALIGN_MID;
					} else if (value.contains("yMax")) {
						p.alignY = ALIGN_MAX;
					}
					p.alignType = ALIGN_MEET;
					if (value.contains("slice")) { p.alignType = ALIGN_SLICE; }
				}
			}
		}
	}
}

// Whether parseViewBox returns before its fourth number.
function viewBoxRunsDry(x: Str): boolean {
	let s: int32 = numberEnd(x, 0);
	for (let k: int32 = 0; k < 3; k++) {
		while (x.ch(s) != 0 && (isSpace(x.ch(s)) || x.ch(s) == 37 || x.ch(s) == 44)) { s += 1; }
		if (x.ch(s) == 0) { return true; }
		s = numberEnd(x, s);
	}
	return false;
}

function newGradient(p: Parser, attrs: Attr[], kind: int32): void {
	const grad = new GradientData();
	grad.kind = kind;
	for (let i: int32 = 0; i < COORD_SLOTS; i++) { grad.coords.push({ value: 0.0, units: UNITS_USER }); }
	if (kind == PAINT_LINEAR_GRADIENT) {
		grad.coords[0] = { value: 0.0, units: UNITS_PERCENT };
		grad.coords[1] = { value: 0.0, units: UNITS_PERCENT };
		grad.coords[2] = { value: 100.0, units: UNITS_PERCENT };
		grad.coords[3] = { value: 0.0, units: UNITS_PERCENT };
	} else if (kind == PAINT_RADIAL_GRADIENT) {
		grad.coords[0] = { value: 50.0, units: UNITS_PERCENT };
		grad.coords[1] = { value: 50.0, units: UNITS_PERCENT };
		grad.coords[2] = { value: 50.0, units: UNITS_PERCENT };
	}
	for (let i: int32 = 0; i < (attrs.length as int32); i++) {
		const name = attrs[i].name;
		const value = attrs[i].value;
		if (name.eq("id")) {
			grad.id = bytesOf(value, ID_BYTES);
		} else if (!parseAttr(p, name, value)) {
			if (name.eq("gradientUnits")) {
				grad.units = value.eq("objectBoundingBox") ? OBJECT_SPACE : USER_SPACE;
			} else if (name.eq("gradientTransform")) {
				parseTransform(grad.xform, value);
			} else if (name.eq("cx") || name.eq("x1")) {
				grad.coords[0] = parseCoordinateRaw(value);
			} else if (name.eq("cy") || name.eq("y1")) {
				grad.coords[1] = parseCoordinateRaw(value);
			} else if (name.eq("r") || name.eq("x2")) {
				grad.coords[2] = parseCoordinateRaw(value);
			} else if (name.eq("fx") || name.eq("y2")) {
				grad.coords[3] = parseCoordinateRaw(value);
			} else if (name.eq("fy")) {
				grad.coords[4] = parseCoordinateRaw(value);
			} else if (name.eq("xlink:href")) {
				grad.ref = bytesOf(value.sub(1, value.e - value.s), 62);
			}
		}
	}
	p.gradients.push(grad);
}

function parseGradientStop(p: Parser, attrs: Attr[]): void {
	const cur = curAttr(p);
	cur.stopOffset = 0.0;
	cur.stopOpacity = 1.0;
	for (let i: int32 = 0; i < (attrs.length as int32); i++) {
		parseAttr(p, attrs[i].name, attrs[i].value);
	}
	if (p.gradients.length == 0) { return; }
	const grad = p.gradients[(p.gradients.length as int32) - 1];
	const stop = new GradientStop();
	const scaled: float32 = cur.stopOpacity * 255;
	stop.alpha = floatToByte(scaled);
	stop.offset = cur.stopOffset;
	let idx = grad.stops.length as int32;
	for (let i: int32 = 0; i < (grad.stops.length as int32); i++) {
		if (cur.stopOffset < grad.stops[i].offset) {
			idx = i;
			break;
		}
	}
	grad.stops.splice(idx, 0, stop);
}

function startElement(p: Parser, el: Str, attrs: Attr[]): void {
	if (p.defsFlag) {
		if (el.eq("linearGradient")) {
			newGradient(p, attrs, PAINT_LINEAR_GRADIENT);
		} else if (el.eq("radialGradient")) {
			newGradient(p, attrs, PAINT_RADIAL_GRADIENT);
		} else if (el.eq("stop")) {
			parseGradientStop(p, attrs);
		} else if (el.eq("style")) {
			p.styleFlag = true;
		}
		return;
	}

	if (el.eq("g")) {
		pushAttr(p);
		parseAttribs(p, attrs);
	} else if (el.eq("path")) {
		if (p.pathFlag) { return; }
		pushAttr(p);
		parsePath(p, attrs);
		popAttr(p);
	} else if (el.eq("rect")) {
		pushAttr(p);
		parseRect(p, attrs);
		popAttr(p);
	} else if (el.eq("circle")) {
		pushAttr(p);
		parseCircle(p, attrs);
		popAttr(p);
	} else if (el.eq("ellipse")) {
		pushAttr(p);
		parseEllipse(p, attrs);
		popAttr(p);
	} else if (el.eq("line")) {
		pushAttr(p);
		parseLine(p, attrs);
		popAttr(p);
	} else if (el.eq("polyline")) {
		pushAttr(p);
		parsePoly(p, attrs, false);
		popAttr(p);
	} else if (el.eq("polygon")) {
		pushAttr(p);
		parsePoly(p, attrs, true);
		popAttr(p);
	} else if (el.eq("linearGradient")) {
		newGradient(p, attrs, PAINT_LINEAR_GRADIENT);
	} else if (el.eq("radialGradient")) {
		newGradient(p, attrs, PAINT_RADIAL_GRADIENT);
	} else if (el.eq("stop")) {
		parseGradientStop(p, attrs);
	} else if (el.eq("defs")) {
		p.defsFlag = true;
	} else if (el.eq("svg")) {
		parseSvg(p, attrs);
	} else if (el.eq("style")) {
		p.styleFlag = true;
	}
}

function endElement(p: Parser, el: Str): void {
	if (el.eq("g")) {
		popAttr(p);
	} else if (el.eq("path")) {
		p.pathFlag = false;
	} else if (el.eq("defs")) {
		p.defsFlag = false;
	} else if (el.eq("style")) {
		p.styleFlag = false;
	}
}

// nsvg__content: the selector lists and property blocks of a style element.
function content(p: Parser, s: Str): void {
	if (!p.styleFlag) { return; }
	let at: int32 = 0;
	while (s.ch(at) != 0) {
		const staged: StyleDecl[] = [];
		const selectors: Str[] = [];
		while (s.ch(at) != 0 && s.ch(at) != 123) {
			while (s.ch(at) != 0 && (isSpace(s.ch(at)) || s.ch(at) == 44)) { at += 1; }
			if (s.ch(at) == 0 || s.ch(at) == 123) { break; }
			const selStart = at;
			while (s.ch(at) != 0 && !isSpace(s.ch(at)) && s.ch(at) != 44 && s.ch(at) != 123) {
				at += 1;
			}
			const selEnd = at;
			if (s.ch(selStart) != 46 || (selectors.length as int32) >= MAX_CLASSES) { continue; }
			selectors.push(s.sub(selStart + 1, selEnd));
		}
		if (s.ch(at) == 0) { break; }
		at += 1;
		const propsStart = at;
		while (s.ch(at) != 0 && s.ch(at) != 125) { at += 1; }
		const properties = s.sub(propsStart, at);
		for (let i: int32 = 0; i < (selectors.length as int32); i++) {
			p.styles.push({ className: selectors[i], properties: properties });
		}
		if (s.ch(at) != 0) { at += 1; }
	}
}

function parseElement(p: Parser, text: Str): void {
	let at: int32 = 0;
	let start = false;
	let end = false;
	while (text.ch(at) != 0 && isSpace(text.ch(at))) { at += 1; }
	if (text.ch(at) == 47) {
		at += 1;
		end = true;
	} else {
		start = true;
	}
	if (text.ch(at) == 0 || text.ch(at) == 63 || text.ch(at) == 33) { return; }
	const nameStart = at;
	while (text.ch(at) != 0 && !isSpace(text.ch(at))) { at += 1; }
	const name = text.sub(nameStart, at);
	if (text.ch(at) != 0) { at += 1; }

	const attrs: Attr[] = [];
	let nattr: int32 = 0;
	while (!end && text.ch(at) != 0 && nattr < XML_MAX_ATTRIBS - 3) {
		while (text.ch(at) != 0 && isSpace(text.ch(at))) { at += 1; }
		if (text.ch(at) == 0) { break; }
		if (text.ch(at) == 47) {
			end = true;
			break;
		}
		const attrStart = at;
		while (text.ch(at) != 0 && !isSpace(text.ch(at)) && text.ch(at) != 61) { at += 1; }
		const attrName = text.sub(attrStart, at);
		if (text.ch(at) != 0) { at += 1; }
		while (text.ch(at) != 0 && text.ch(at) != 34 && text.ch(at) != 39) { at += 1; }
		if (text.ch(at) == 0) { break; }
		const quote = text.ch(at);
		at += 1;
		const valueStart = at;
		while (text.ch(at) != 0 && text.ch(at) != quote) { at += 1; }
		const value = text.sub(valueStart, at);
		if (text.ch(at) != 0) { at += 1; }
		attrs.push({ name: attrName, value: value });
		nattr += 2;
	}
	if (start) { startElement(p, name, attrs); }
	if (end) { endElement(p, name); }
}

function parseXml(p: Parser, length: int32): void {
	const input = p.source;
	let s: int32 = 0;
	let mark: int32 = 0;
	let inTag = false;
	while (s < length) {
		const c = input[s] as int32;
		if (c == 60 && !inTag) {
			let from = mark;
			while (from < s && isSpace(input[from] as int32)) { from += 1; }
			if (from < s) { content(p, { b: input, s: from, e: s }); }
			s += 1;
			mark = s;
			inTag = true;
		} else if (c == 62 && inTag) {
			parseElement(p, { b: input, s: mark, e: s });
			s += 1;
			mark = s;
			inTag = false;
		} else {
			s += 1;
		}
	}
}

function imageBounds(p: Parser, bounds: float32[]): void {
	if (p.shapes.length == 0) {
		bounds[0] = 0.0;
		bounds[1] = 0.0;
		bounds[2] = 0.0;
		bounds[3] = 0.0;
		return;
	}
	const first = p.shapes[0];
	bounds[0] = first.bounds[0];
	bounds[1] = first.bounds[1];
	bounds[2] = first.bounds[2];
	bounds[3] = first.bounds[3];
	for (let i: int32 = 1; i < (p.shapes.length as int32); i++) {
		const shape = p.shapes[i];
		bounds[0] = minf(bounds[0], shape.bounds[0]);
		bounds[1] = minf(bounds[1], shape.bounds[1]);
		bounds[2] = maxf(bounds[2], shape.bounds[2]);
		bounds[3] = maxf(bounds[3], shape.bounds[3]);
	}
}

function viewAlign(content: float32, container: float32, kind: int32): float32 {
	if (kind == ALIGN_MIN) { return 0.0; }
	if (kind == ALIGN_MAX) {
		const far: float32 = container - content;
		return far;
	}
	const mid: float32 = (container - content) * 0.5;
	return mid;
}

function scaleGradient(grad: Gradient, tx: float32, ty: float32, sx: float32, sy: float32): void {
	const t: float32[] = [0, 0, 0, 0, 0, 0];
	xformSetTranslation(t, tx, ty);
	xformMultiply(grad.xform, t);
	xformSetScale(t, sx, sy);
	xformMultiply(grad.xform, t);
}

function scaleToViewbox(p: Parser): void {
	const bounds: float32[] = [0, 0, 0, 0];
	imageBounds(p, bounds);

	if (p.viewWidth == 0) {
		if (p.imageWidth > 0) {
			p.viewWidth = p.imageWidth;
		} else {
			p.viewMinx = bounds[0];
			p.viewWidth = bounds[2] - bounds[0];
		}
	}
	if (p.viewHeight == 0) {
		if (p.imageHeight > 0) {
			p.viewHeight = p.imageHeight;
		} else {
			p.viewMiny = bounds[1];
			p.viewHeight = bounds[3] - bounds[1];
		}
	}
	if (p.imageWidth == 0) { p.imageWidth = p.viewWidth; }
	if (p.imageHeight == 0) { p.imageHeight = p.viewHeight; }

	let tx: float32 = -p.viewMinx;
	let ty: float32 = -p.viewMiny;
	let sx: float32 = 0.0;
	let sy: float32 = 0.0;
	if (p.viewWidth > 0) { sx = p.imageWidth / p.viewWidth; }
	if (p.viewHeight > 0) { sy = p.imageHeight / p.viewHeight; }
	const us: float32 = 1.0 / convertToPixels(p, 1.0, UNITS_PX, 0.0, 1.0);

	if (p.alignType == ALIGN_MEET) {
		sx = minf(sx, sy);
		sy = sx;
		tx = tx + viewAlign(p.viewWidth * sx, p.imageWidth, p.alignX) / sx;
		ty = ty + viewAlign(p.viewHeight * sy, p.imageHeight, p.alignY) / sy;
	} else if (p.alignType == ALIGN_SLICE) {
		sx = maxf(sx, sy);
		sy = sx;
		tx = tx + viewAlign(p.viewWidth * sx, p.imageWidth, p.alignX) / sx;
		ty = ty + viewAlign(p.viewHeight * sy, p.imageHeight, p.alignY) / sy;
	}

	sx = sx * us;
	sy = sy * us;
	const avgs: float32 = (sx + sy) / 2.0;
	const t: float32[] = [0, 0, 0, 0, 0, 0];
	for (let k: int32 = 0; k < (p.shapes.length as int32); k++) {
		const shape = p.shapes[k];
		shape.bounds[0] = (shape.bounds[0] + tx) * sx;
		shape.bounds[1] = (shape.bounds[1] + ty) * sy;
		shape.bounds[2] = (shape.bounds[2] + tx) * sx;
		shape.bounds[3] = (shape.bounds[3] + ty) * sy;
		for (let m: int32 = 0; m < (shape.paths.length as int32); m++) {
			const path = shape.paths[m];
			path.bounds[0] = (path.bounds[0] + tx) * sx;
			path.bounds[1] = (path.bounds[1] + ty) * sy;
			path.bounds[2] = (path.bounds[2] + tx) * sx;
			path.bounds[3] = (path.bounds[3] + ty) * sy;
			for (let i: int32 = 0; i < path.npts; i++) {
				path.pts[i * 2] = (path.pts[i * 2] + tx) * sx;
				path.pts[i * 2 + 1] = (path.pts[i * 2 + 1] + ty) * sy;
			}
		}

		const fillGradient = shape.fill.gradient;
		if (
			(shape.fill.kind == PAINT_LINEAR_GRADIENT || shape.fill.kind == PAINT_RADIAL_GRADIENT) &&
			fillGradient != null
		) {
			scaleGradient(fillGradient, tx, ty, sx, sy);
			copySix(t, fillGradient.xform);
			xformInverse(fillGradient.xform, t);
		}
		const strokeGradient = shape.stroke.gradient;
		if (
			(shape.stroke.kind == PAINT_LINEAR_GRADIENT ||
				shape.stroke.kind == PAINT_RADIAL_GRADIENT) &&
			strokeGradient != null
		) {
			scaleGradient(strokeGradient, tx, ty, sx, sy);
			copySix(t, strokeGradient.xform);
			xformInverse(strokeGradient.xform, t);
		}

		shape.strokeWidth = shape.strokeWidth * avgs;
		shape.strokeDashOffset = shape.strokeDashOffset * avgs;
		for (let i: int32 = 0; i < shape.strokeDashCount; i++) {
			shape.strokeDashArray[i] = shape.strokeDashArray[i] * avgs;
		}
	}
}

function createGradients(p: Parser): void {
	for (let k: int32 = 0; k < (p.shapes.length as int32); k++) {
		const shape = p.shapes[k];
		if (shape.fill.kind == PAINT_UNDEF) {
			if (shape.fillGradient.length > 0) {
				const inv: float32[] = [0, 0, 0, 0, 0, 0];
				const localBounds: float32[] = [0, 0, 0, 0];
				xformInverse(inv, shape.xform);
				getLocalBounds(localBounds, shape, inv);
				const grad = createGradient(p, shape.fillGradient, localBounds, shape.xform);
				if (grad != null) {
					shape.fill.gradient = grad;
					shape.fill.kind = gradientKindOf(p, shape.fillGradient);
				}
			}
			if (shape.fill.kind == PAINT_UNDEF) { shape.fill.kind = PAINT_NONE; }
		}
		if (shape.stroke.kind == PAINT_UNDEF) {
			if (shape.strokeGradient.length > 0) {
				const inv: float32[] = [0, 0, 0, 0, 0, 0];
				const localBounds: float32[] = [0, 0, 0, 0];
				xformInverse(inv, shape.xform);
				getLocalBounds(localBounds, shape, inv);
				const grad = createGradient(p, shape.strokeGradient, localBounds, shape.xform);
				if (grad != null) {
					shape.stroke.gradient = grad;
					shape.stroke.kind = gradientKindOf(p, shape.strokeGradient);
				}
			}
			if (shape.stroke.kind == PAINT_UNDEF) { shape.stroke.kind = PAINT_NONE; }
		}
	}
}

function gradientKindOf(p: Parser, id: uint8[]): int32 {
	const data = findGradientData(p, id);
	if (data == null) { throw new Error("void2d svg: a gradient was built for an id that names none"); }
	return data.kind;
}

// nsvgParse: the document in `source` (NUL-free bytes) as an image in px at 96 dpi.
export function nsvgParse(source: uint8[], dpi: float32): SvgImage {
	const p = createParser(source, dpi);
	parseXml(p, source.length as int32);
	createGradients(p);
	scaleToViewbox(p);
	const image = new SvgImage();
	image.width = p.imageWidth;
	image.height = p.imageHeight;
	image.shapes = p.shapes;
	return image;
}
