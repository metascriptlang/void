import { Bounds2D, Filter, FilterChain, FilterKind, Vec2 } from "./types";

function deviceRound(v: float32): float32 {
	return Math.round(v as float64) as float32;
}

export function targetRect(
	b: Bounds2D, shift: Vec2, vw: float32, vh: float32, dpi: float32, scoped: boolean,
): Bounds2D {
	let x0: float32 = Math.floor((b.xMin * dpi) as float64) as float32;
	let y0: float32 = Math.floor((b.yMin * dpi) as float64) as float32;
	let x1: float32 = Math.ceil((b.xMax * dpi) as float64) as float32;
	let y1: float32 = Math.ceil((b.yMax * dpi) as float64) as float32;
	if (!scoped) {
		const sx: float32 = deviceRound(shift.x * dpi);
		const sy: float32 = deviceRound(shift.y * dpi);
		const right: float32 = deviceRound(vw * dpi) - sx;
		const bottom: float32 = deviceRound(vh * dpi) - sy;
		if (x0 < 0.0 - sx) { x0 = 0.0 - sx; }
		if (y0 < 0.0 - sy) { y0 = 0.0 - sy; }
		if (x1 > right) { x1 = right; }
		if (y1 > bottom) { y1 = bottom; }
	}
	return { xMin: x0, yMin: y0, xMax: x1, yMax: y1 };
}

export struct FilterPlan {
	padded: Bounds2D;
	device: Bounds2D;
	scale: float32;
	width: int32;
	height: int32;
}

function stopOn(what: string): void {
	console.log(`void2d filter: ${what}`);
	unreachable;
}

// A chain renders its subtree once, so its steps share one resolution scale.
export function resolutionScale(this c: FilterChain): float32 {
	return c.steps.length > 0 ? c.steps[0].resolutionScale : 1.0;
}

export function checkFilterChain(c: FilterChain): void {
	for (let k: int32 = 0; k < (c.steps.length as int32); k++) {
		const f: Filter = c.steps[k];
		if (f.kind === FilterKind.None) {
			stopOn(`step ${k} is FilterKind.None; leave it out of the chain`);
		}
		if (!(f.resolutionScale > 0.0)) {
			stopOn(`step ${k} (${f.kind.toString()}) has resolutionScale ${f.resolutionScale}; it must be above 0`);
		}
		if (!(f.radius >= 0.0)) {
			stopOn(`step ${k} (${f.kind.toString()}) has radius ${f.radius}; it must be 0 or more`);
		}
		if (f.kind === FilterKind.Outline && f.samples < 1) {
			stopOn(`step ${k} (Outline) has ${f.samples} samples; it needs at least 1`);
		}
		if (f.kind === FilterKind.Mask && f.mask < 0) {
			stopOn(`step ${k} (Mask) names no mask node; build it with NodeRef.asMaskFilter`);
		}
		if (f.resolutionScale != c.steps[0].resolutionScale) {
			stopOn(`step ${k} (${f.kind.toString()}) has resolutionScale ${f.resolutionScale} and step 0 has ${c.steps[0].resolutionScale}; a chain renders its subtree once, so its steps share one scale`);
		}
	}
}

// The bounds the chain needs: each step can reach past the one before it.
export function paddedBounds(b: Bounds2D, c: FilterChain): Bounds2D {
	let out: Bounds2D = b;
	for (let k: int32 = 0; k < (c.steps.length as int32); k++) {
		const f: Filter = c.steps[k];
		out = {
			xMin: out.xMin - f.radius, yMin: out.yMin - f.radius,
			xMax: out.xMax + f.radius, yMax: out.yMax + f.radius,
		};
		if (f.kind !== FilterKind.DropShadow) { continue; }
		if (f.offsetX < 0.0) { out = { ...out, xMin: out.xMin + f.offsetX }; }
		else { out = { ...out, xMax: out.xMax + f.offsetX }; }
		if (f.offsetY < 0.0) { out = { ...out, yMin: out.yMin + f.offsetY }; }
		else { out = { ...out, yMax: out.yMax + f.offsetY }; }
	}
	return out;
}

export function planFilter(
	b: Bounds2D, c: FilterChain, shift: Vec2, vw: float32, vh: float32, dpi: float32,
	scoped: boolean,
): FilterPlan {
	const padded: Bounds2D = paddedBounds(b, c);
	const scale: float32 = dpi * c.resolutionScale();
	const device: Bounds2D = targetRect(padded, shift, vw, vh, scale, scoped);
	return {
		padded: padded, device: device, scale: scale,
		width: (device.xMax - device.xMin) as int32, height: (device.yMax - device.yMin) as int32,
	};
}
