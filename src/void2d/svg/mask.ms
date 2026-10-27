import {
	CAP_BUTT,
	CAP_ROUND,
	CAP_SQUARE,
	FILLRULE_NONZERO,
	JOIN_ROUND,
	PAINT_COLOR,
	PAINT_NONE,
	Paint,
	Path,
	Shape,
	SvgImage,
} from "./image";
import { nsvgParse } from "./parse";
import { rasterize } from "./rasterize";
import {
	SVG_BAD_HANDLE,
	SVG_NO_MEMORY,
	SVG_NO_SIZE,
	SVG_REFUSED,
	SVG_TOO_LARGE,
	scanSource,
} from "./scan";
import { formatG } from "../../math/formatG";

const MAX_SOURCE_BYTES: int32 = 16 * 1024 * 1024;
const MAX_PARSED_SIDE: float32 = 1000000.0;
const DOT_POINTS: int32 = 13;
const TINY_PATH_OF_STROKE: float32 = 0.05;
const DOT_KAPPA: float32 = 0.5522847498;
const MAX_SLOTS: int32 = 0xffff;
const MAX_GENERATION: int32 = 0x7fff;
const DPI: float32 = 96.0;

let reason: string = "";
let slotImages: (SvgImage | null)[] = [];
let slotGenerations: int32[] = [];
let capacity: int32 = 0;
let parsedCount: int32 = 0;
let releasedCount: int32 = 0;

export function maskReason(): string {
	return reason;
}

function dotPath(x: float32, y: float32, radius: float32, round: boolean): Path {
	const k: float32 = DOT_KAPPA * radius;
	const r = radius;
	const path = new Path();
	if (round) {
		path.pts = [
			x + r, y,
			x + r, y + k, x + k, y + r, x, y + r,
			x - k, y + r, x - r, y + k, x - r, y,
			x - r, y - k, x - k, y - r, x, y - r,
			x + k, y - r, x + r, y - k, x + r, y,
		];
	} else {
		path.pts = [
			x - r, y - r,
			x - r, y - r, x + r, y - r, x + r, y - r,
			x + r, y - r, x + r, y + r, x + r, y + r,
			x + r, y + r, x - r, y + r, x - r, y + r,
			x - r, y + r, x - r, y - r, x - r, y - r,
		];
	}
	path.npts = DOT_POINTS;
	path.closed = true;
	path.bounds = [x - r, y - r, x + r, y + r];
	return path;
}

function extentOf(path: Path): float32 {
	const width: float32 = path.bounds[2] - path.bounds[0];
	const height: float32 = path.bounds[3] - path.bounds[1];
	return width > height ? width : height;
}

function copyPaint(source: Paint): Paint {
	const copy = new Paint();
	copy.kind = source.kind;
	copy.alpha = source.alpha;
	copy.gradient = source.gradient;
	return copy;
}

function dotShape(shape: Shape, cap: Path): Shape {
	const dot = new Shape();
	dot.fill = copyPaint(shape.stroke);
	dot.stroke = new Paint();
	dot.opacity = shape.opacity;
	dot.strokeWidth = shape.strokeWidth;
	dot.strokeDashOffset = shape.strokeDashOffset;
	dot.strokeDashArray = [...shape.strokeDashArray];
	dot.strokeDashCount = shape.strokeDashCount;
	dot.strokeLineJoin = shape.strokeLineJoin;
	dot.strokeLineCap = shape.strokeLineCap;
	dot.miterLimit = shape.miterLimit;
	dot.fillRule = FILLRULE_NONZERO;
	dot.paintOrder = shape.paintOrder;
	dot.visible = shape.visible;
	dot.bounds = [...cap.bounds];
	dot.fillGradient = shape.fillGradient;
	dot.strokeGradient = shape.strokeGradient;
	dot.xform = [...shape.xform];
	dot.paths = [cap];
	return dot;
}

// A path far smaller than its stroke is a dot that nanosvg's stroker drops: draw it as a shape.
function drawTinyPaths(image: SvgImage): int32 {
	for (let s: int32 = 0; s < (image.shapes.length as int32); s++) {
		const shape = image.shapes[s];
		const stroked = shape.stroke.kind != PAINT_NONE && shape.strokeWidth > 0.0 && shape.visible;
		if (!stroked) { continue; }
		let p: int32 = 0;
		while (p < (shape.paths.length as int32)) {
			const path = shape.paths[p];
			const extent = extentOf(path);
			const limit: float32 = shape.strokeWidth * TINY_PATH_OF_STROKE;
			const tiny = extent <= limit;
			const round = path.closed
				? shape.strokeLineJoin == JOIN_ROUND
				: shape.strokeLineCap == CAP_ROUND;
			const square = !path.closed && shape.strokeLineCap == CAP_SQUARE;
			const butt = !path.closed && shape.strokeLineCap == CAP_BUTT;
			if (!tiny || butt) {
				p += 1;
				continue;
			}
			if (!round && !square) {
				reason = "a stroked path much smaller than its stroke width without round joins";
				return SVG_REFUSED;
			}
			if (shape.stroke.kind != PAINT_COLOR) {
				reason = "a tiny stroked path with a gradient stroke";
				return SVG_REFUSED;
			}
			if (shape.strokeDashCount > 0) {
				reason = "a tiny stroked path with a dash array";
				return SVG_REFUSED;
			}
			const cx: float32 = (path.bounds[0] + path.bounds[2]) * 0.5;
			const cy: float32 = (path.bounds[1] + path.bounds[3]) * 0.5;
			const radius: float32 = shape.strokeWidth * 0.5;
			const cap = dotPath(cx, cy, radius, round);
			image.shapes.splice(s + 1, 0, dotShape(shape, cap));
			shape.paths.splice(p, 1);
		}
	}
	return 0;
}

function handleOf(slot: int32): int32 {
	return (slotGenerations[slot] << 16) | (slot + 1);
}

function takeSlot(image: SvgImage): int32 {
	for (let i: int32 = 0; i < capacity; i++) {
		if (slotImages[i] == null && slotGenerations[i] != 0) {
			slotImages[i] = image;
			return handleOf(i);
		}
	}
	if (capacity >= MAX_SLOTS) {
		reason = `more than ${MAX_SLOTS} SVGs alive or retired`;
		return 0;
	}
	let grown = capacity > 0 ? capacity * 2 : 16;
	if (grown > MAX_SLOTS) { grown = MAX_SLOTS; }
	for (let i = capacity; i < grown; i++) {
		slotImages.push(null);
		slotGenerations.push(1);
	}
	const slot = capacity;
	capacity = grown;
	slotImages[slot] = image;
	return handleOf(slot);
}

function slotOf(handle: int32): int32 {
	if (handle < 1) { return -1; }
	const slot = (handle & 0xffff) - 1;
	if (slot < 0 || slot >= capacity) { return -1; }
	if (slotImages[slot] == null || slotGenerations[slot] != (handle >> 16)) { return -1; }
	return slot;
}

export function maskImageOf(handle: int32): SvgImage | null {
	const slot = slotOf(handle);
	return slot < 0 ? null : slotImages[slot];
}

// void2dSvgMaskParse: a handle above zero, or a status below it with the reason in maskReason().
export function maskParse(source: string): int32 {
	reason = "";
	const bytes: uint8[] = [];
	const total = source.byteLength();
	for (let i: int32 = 0; i < total; i++) {
		const c = source.byteAt(i);
		if (c == 0) { break; }
		bytes.push(c as uint8);
	}
	const length = bytes.length as int32;
	if (length > MAX_SOURCE_BYTES) {
		reason = `source of ${length} bytes, over the ${MAX_SOURCE_BYTES} byte limit`;
		return SVG_TOO_LARGE;
	}
	const scanned = scanSource(source, bytes);
	if (scanned.code != 0) {
		reason = scanned.reason;
		return scanned.code;
	}
	const image = nsvgParse(bytes, DPI);
	parsedCount += 1;
	if (!(image.width > 0.0 && image.height > 0.0 && image.width < MAX_PARSED_SIDE
		&& image.height < MAX_PARSED_SIDE)) {
		reason = `size ${formatG(image.width as float64)}x${formatG(image.height as float64)}`;
		releasedCount += 1;
		return SVG_NO_SIZE;
	}
	const code = drawTinyPaths(image);
	if (code != 0) {
		releasedCount += 1;
		return code;
	}
	const handle = takeSlot(image);
	if (handle == 0) {
		releasedCount += 1;
		return SVG_NO_MEMORY;
	}
	return handle;
}

export function maskFree(handle: int32): int32 {
	const slot = slotOf(handle);
	if (slot < 0) { return SVG_BAD_HANDLE; }
	releasedCount += 1;
	slotImages[slot] = null;
	slotGenerations[slot] = slotGenerations[slot] >= MAX_GENERATION ? 0 : slotGenerations[slot] + 1;
	return 0;
}

export function maskLive(): int32 {
	let live: int32 = 0;
	for (let i: int32 = 0; i < capacity; i++) {
		if (slotImages[i] != null) { live += 1; }
	}
	return live;
}

export function maskParsed(): int32 {
	return parsedCount;
}

export function maskReleased(): int32 {
	return releasedCount;
}

// void2dSvgMaskRasterize: the image fitted into width x height, centred, as an alpha mask.
export function maskRasterize(image: SvgImage, width: int32, height: int32): Vec<uint8> {
	const scaleX: float32 = (width as float32) / image.width;
	const scaleY: float32 = (height as float32) / image.height;
	const scale: float32 = scaleX < scaleY ? scaleX : scaleY;
	const fittedX: float32 = image.width * scale;
	const fittedY: float32 = image.height * scale;
	const offsetX: float32 = ((width as float32) - fittedX) * 0.5;
	const offsetY: float32 = ((height as float32) - fittedY) * 0.5;
	return rasterize(image, offsetX, offsetY, scale, width, height);
}
