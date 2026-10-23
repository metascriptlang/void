// void2d's programs written as MetaScript shader functions. tools/irPrograms.ms prints them into
// shader2dModules.ms; src/test/shader2dCheck.ms runs them on the CPU.

import {
	Mat4x4f,
	Sampler,
	Texture2d,
	Vec2f,
	Vec3f,
	Vec4f,
	abs,
	atan2,
	binding,
	builtin,
	clamp,
	cos,
	discard,
	dot,
	dpdx,
	dpdy,
	exp,
	floor,
	fwidth,
	le,
	length,
	max,
	min,
	mix,
	pow,
	select,
	sign,
	sin,
	sqrt,
	step,
	textureDimensions,
	textureSample,
	vec2f,
	vec3f,
	vec4f,
} from "../shader/std";

export struct BlurAttributes {
	pos: Vec2f;
	uv0: Vec2f;
}

export struct BlurVaryings {
	uv: Vec2f;
	@builtin(position) clip: Vec4f;
}

export struct BlurInput {
	uv: Vec2f;
}

export struct BlurParams {
	dir: Vec4f;
}

export struct BlurBindings {
	@binding(0) srcTex: Texture2d;
	@binding(0) srcSmp: Sampler;
	@binding(0) blur_params: BlurParams;
}

export function blurVs(input: BlurAttributes): BlurVaryings {
	return { uv: input.uv0, clip: vec4f(input.pos, 0.0, 1.0) };
}

// Separable Gaussian blur (h2d.filter.Blur): `dir.xy` is the per-tap UV step, (radius/texW, 0) for
// the horizontal pass and (0, radius/texH) for the vertical; two passes make the 2D blur.
export function blurFs(input: BlurInput, b: BlurBindings): Vec4f {
	const step = b.blur_params.dir.xy;
	const o1 = step * 1.384615;
	const o2 = step * 3.230769;
	let sum = textureSample(b.srcTex, b.srcSmp, input.uv) * 0.227027;
	sum += textureSample(b.srcTex, b.srcSmp, input.uv + o1) * 0.316216;
	sum += textureSample(b.srcTex, b.srcSmp, input.uv - o1) * 0.316216;
	sum += textureSample(b.srcTex, b.srcSmp, input.uv + o2) * 0.070270;
	sum += textureSample(b.srcTex, b.srcSmp, input.uv - o2) * 0.070270;
	return sum;
}

// viewport.xy the framebuffer size in pixels, .z flipV, .w a source already premultiplied;
// clipU/clipV an edge axis in xy and its accepted projection interval in zw, off when w <= z.
export struct SpriteParams {
	viewport: Vec4f;
	clipU: Vec4f;
	clipV: Vec4f;
	shift: Vec4f;
}

export struct SpriteVertexBindings {
	@binding(0) sprite_params: SpriteParams;
}

// `corner` steps per vertex over the unit quad; the rest per instance: iAffine a,b,c,d,
// iOriginSize tx,ty,w,h, iUv u0,v0,u1,v1.
export struct SpriteAttributes {
	corner: Vec2f;
	iAffine: Vec4f;
	iOriginSize: Vec4f;
	iUv: Vec4f;
	iColor: Vec4f;
}

export struct SpriteVaryings {
	uv: Vec2f;
	color: Vec4f;
	srcPremult: float32;
	clipDistance: Vec4f;
	@builtin(position) clip: Vec4f;
}

export struct SpriteInput {
	uv: Vec2f;
	color: Vec4f;
	srcPremult: float32;
	clipDistance: Vec4f;
}

export struct SpriteBindings {
	@binding(0) spriteTex: Texture2d;
	@binding(0) spriteSmp: Sampler;
}

// The flat sprite pipeline (VOID2D.md "P2"): one 64-byte instance per quad and no SDF maths, so a
// sprite-only scene never pays for the UI pipeline. The affine rides per instance instead of being
// applied on the CPU, which keeps the instance bytes unchanged from frame to frame.
export function spriteVs(input: SpriteAttributes, b: SpriteVertexBindings): SpriteVaryings {
	const local = input.corner * input.iOriginSize.zw;
	const world = vec2f(
		input.iAffine.x * local.x + input.iAffine.z * local.y + input.iOriginSize.x,
		input.iAffine.y * local.x + input.iAffine.w * local.y + input.iOriginSize.y,
	);
	const viewport = b.sprite_params.viewport;
	const moved = world + b.sprite_params.shift.xy;
	const clipU = b.sprite_params.clipU;
	const clipV = b.sprite_params.clipV;
	let clipDistance = vec4f(1.0);
	if (clipU.w > clipU.z) {
		const cu = dot(world, clipU.xy);
		const cv = dot(world, clipV.xy);
		clipDistance = vec4f(cu - clipU.z, clipU.w - cu, cv - clipV.z, clipV.w - cv);
	}
	const ndc = vec2f(moved.x / viewport.x * 2.0 - 1.0, 1.0 - moved.y / viewport.y * 2.0);
	const t = mix(input.iUv.xy, input.iUv.zw, input.corner);
	return {
		uv: viewport.z > 0.5 ? vec2f(t.x, 1.0 - t.y) : t,
		color: input.iColor,
		srcPremult: viewport.w,
		clipDistance: clipDistance,
		clip: vec4f(ndc, 0.0, 1.0),
	};
}

export function spriteFs(input: SpriteInput, b: SpriteBindings): Vec4f {
	const d = input.clipDistance;
	if (min(min(d.x, d.y), min(d.z, d.w)) < 0.0) {
		discard();
	}
	const c = textureSample(b.spriteTex, b.spriteSmp, input.uv) * input.color;
	const straight = vec4f(mix(c.xyz, c.xyz * input.color.w, input.srcPremult), c.w);
	const premult = vec4f(straight.xyz * straight.w, straight.w);
	return mix(premult, straight, input.srcPremult);
}

export const PATTERN_TIE_BIAS: float32 = 1.0 / 64.0;
export const SDF_EDGE: float32 = 191.0 / 255.0;
export const SDF_RADIUS: float32 = 8.0;

// GLSL's mod, which floors where WGSL's % truncates.
export function floorMod(x: float32, y: float32): float32 {
	return x - y * floor(x / y);
}

// GPUI's apply_contrast_and_gamma_correction (crates/gpui_windows/src/alpha_correction.hlsl),
// itself from Windows Terminal's dwrite.hlsl, MIT. src/void2d/textGamma.ms is its T0 copy.
export function applyContrastAndGamma(
	coverage: float32,
	color: Vec3f,
	contrastFactor: float32,
	ratios: Vec4f,
): float32 {
	const brightness = dot(color, vec3f(0.30, 0.59, 0.11));
	const k = contrastFactor * clamp(4.0 * (0.75 - brightness), 0.0, 1.0);
	const a = coverage * (k + 1.0) / (coverage * k + 1.0);
	const correction = (ratios.x * brightness + ratios.y) * a + (ratios.z * brightness + ratios.w);
	return a + a * (1.0 - a) * correction;
}

export function sdfCoverage(sampled: float32, texelsPerPixel: float32): float32 {
	const texels = (sampled - SDF_EDGE) * SDF_RADIUS;
	return clamp(texels / texelsPerPixel + 0.5, 0.0, 1.0);
}

export function sdfTexelsPerPixel(uvDx: Vec2f, uvDy: Vec2f, pageSize: Vec2f): float32 {
	return max(0.5 * (length(uvDx * pageSize) + length(uvDy * pageSize)), 0.0001);
}

export function srgbToLinear(c: Vec3f): Vec3f {
	const lo = c / 12.92;
	const hi = pow((c + vec3f(0.055)) / 1.055, vec3f(2.4));
	return select(hi, lo, le(c, vec3f(0.04045)));
}

export function linearToSrgb(c: Vec3f): Vec3f {
	const lo = c * 12.92;
	const hi = vec3f(1.055) * pow(max(c, vec3f(0.0)), vec3f(1.0 / 2.4)) - vec3f(0.055);
	return select(hi, lo, le(c, vec3f(0.0031308)));
}

export function linearToOklab(c: Vec3f): Vec3f {
	let lms = vec3f(
		0.4122214708 * c.x + 0.5363325363 * c.y + 0.0514459929 * c.z,
		0.2119034982 * c.x + 0.6806995451 * c.y + 0.1073969566 * c.z,
		0.0883024619 * c.x + 0.2817188376 * c.y + 0.6299787005 * c.z,
	);
	lms = sign(lms) * pow(abs(lms), vec3f(1.0 / 3.0));
	return vec3f(
		0.2104542553 * lms.x + 0.7936177850 * lms.y - 0.0040720468 * lms.z,
		1.9779984951 * lms.x - 2.4285922050 * lms.y + 0.4505937099 * lms.z,
		0.0259040371 * lms.x + 0.7827717662 * lms.y - 0.8086757660 * lms.z,
	);
}

export function oklabToLinear(c: Vec3f): Vec3f {
	let lms = vec3f(
		c.x + 0.3963377774 * c.y + 0.2158037573 * c.z,
		c.x - 0.1055613458 * c.y - 0.0638541728 * c.z,
		c.x - 0.0894841775 * c.y - 1.2914855480 * c.z,
	);
	lms = lms * lms * lms;
	return vec3f(
		4.0767416621 * lms.x - 3.3077115913 * lms.y + 0.2309699292 * lms.z,
		-1.2684380046 * lms.x + 2.6097574011 * lms.y - 0.3413193965 * lms.z,
		-0.0041960863 * lms.x - 0.7034186147 * lms.y + 1.7076147010 * lms.z,
	);
}

export function mixColorSpace(a: Vec4f, b: Vec4f, t: float32, oklab: boolean): Vec4f {
	let rgb = vec3f(0.0);
	if (oklab) {
		const la = linearToOklab(srgbToLinear(a.xyz));
		const lb = linearToOklab(srgbToLinear(b.xyz));
		rgb = linearToSrgb(oklabToLinear(mix(la, lb, t)));
	} else {
		rgb = mix(a.xyz, b.xyz, t);
	}
	return vec4f(rgb, mix(a.w, b.w, t));
}

export function bayer4(pixel: Vec2f): float32 {
	const x = (floor(pixel.x) as int32) & 3;
	const y = (floor(pixel.y) as int32) & 3;
	if (y == 0) {
		if (x == 0) { return 0.0; }
		if (x == 1) { return 8.0; }
		if (x == 2) { return 2.0; }
		return 10.0;
	}
	if (y == 1) {
		if (x == 0) { return 12.0; }
		if (x == 1) { return 4.0; }
		if (x == 2) { return 14.0; }
		return 6.0;
	}
	if (y == 2) {
		if (x == 0) { return 3.0; }
		if (x == 1) { return 11.0; }
		if (x == 2) { return 1.0; }
		return 9.0;
	}
	if (x == 0) { return 15.0; }
	if (x == 1) { return 7.0; }
	if (x == 2) { return 13.0; }
	return 5.0;
}

export function ditherRgb(rgb: Vec3f, pixel: Vec2f): Vec3f {
	const noise = (bayer4(pixel) - 7.5) * (2.0 / (7.5 * 255.0));
	return clamp(rgb + vec3f(noise), vec3f(0.0), vec3f(1.0));
}

// viewport.xy the framebuffer size in pixels, .z flipV (1 when sampling a GL render target), .w
// a premultiplied source with no effect; model0 the 2D affine's linear part (a,b,c,d), model1.xy
// its translation, .z an R8 glyph-coverage texture, .w device pixels per unit; globalColor
// multiplies the per-vertex tint.
export struct BatchParams {
	viewport: Vec4f;
	model0: Vec4f;
	model1: Vec4f;
	globalColor: Vec4f;
	clipU: Vec4f;
	clipV: Vec4f;
	shift: Vec4f;
}

export struct BatchVertexBindings {
	@binding(0) void2d_params: BatchParams;
}

export struct BatchAttributes {
	pos: Vec2f;
	uv0: Vec2f;
	color0: Vec4f;
}

export struct BatchVaryings {
	uv: Vec2f;
	color: Vec4f;
	srcPremult: float32;
	coverageTexture: float32;
	clipDistance: Vec4f;
	pixel: Vec2f;
	@builtin(position) clip: Vec4f;
}

export struct BatchInput {
	uv: Vec2f;
	color: Vec4f;
	srcPremult: float32;
	coverageTexture: float32;
	clipDistance: Vec4f;
	pixel: Vec2f;
}

// h2d.Drawable's colour pipeline: the per-vertex tint, then colorMatrix, then colorAdd. The
// defaults (identity, zero) leave the pixel alone, so nodes with no effect batch together.
export struct BatchEffect {
	colorMatrix: Mat4x4f;
	colorAdd: Vec4f;
	colorKey: Vec4f;
	gradientMeta: Vec4f;
	gradientParams: Vec4f;
	gradientColor0: Vec4f;
	gradientColor1: Vec4f;
	gradientColor2: Vec4f;
	gammaRatios: Vec4f;
	textParams: Vec4f;
	sourceParams: Vec4f;
}

export struct BatchBindings {
	@binding(0) tex: Texture2d;
	@binding(0) smp: Sampler;
	@binding(1) void2d_fx: BatchEffect;
}

// The batcher's vertex: pos through the 2D affine to pixels, then NDC; the per-vertex colour
// times globalColor. The dynamic batch passes the identity and white (its vertices are already in
// pixels); a static buffer of local-space geometry passes its object matrix and alpha here.
export function vs(input: BatchAttributes, b: BatchVertexBindings): BatchVaryings {
	const model0 = b.void2d_params.model0;
	const model1 = b.void2d_params.model1;
	const viewport = b.void2d_params.viewport;
	const world = vec2f(
		model0.x * input.pos.x + model0.z * input.pos.y + model1.x,
		model0.y * input.pos.x + model0.w * input.pos.y + model1.y,
	);
	const moved = world + b.void2d_params.shift.xy;
	const clipU = b.void2d_params.clipU;
	const clipV = b.void2d_params.clipV;
	let clipDistance = vec4f(1.0);
	if (clipU.w > clipU.z) {
		const cu = dot(world, clipU.xy);
		const cv = dot(world, clipV.xy);
		clipDistance = vec4f(cu - clipU.z, clipU.w - cu, cv - clipV.z, clipV.w - cv);
	}
	const ndc = vec2f(moved.x / viewport.x * 2.0 - 1.0, 1.0 - moved.y / viewport.y * 2.0);
	return {
		uv: viewport.z > 0.5 ? vec2f(input.uv0.x, 1.0 - input.uv0.y) : input.uv0,
		color: input.color0 * b.void2d_params.globalColor,
		srcPremult: viewport.w,
		coverageTexture: model1.z,
		clipDistance: clipDistance,
		pixel: moved * model1.w,
		clip: vec4f(ndc, 0.0, 1.0),
	};
}

function mixGradient(b: BatchBindings, x: Vec4f, y: Vec4f, t: float32): Vec4f {
	return mixColorSpace(x, y, t, b.void2d_fx.gradientMeta.y > 0.5);
}

function gradientAt(b: BatchBindings, t: float32): Vec4f {
	const middle = b.void2d_fx.gradientMeta.w;
	const c0 = b.void2d_fx.gradientColor0;
	const c1 = b.void2d_fx.gradientColor1;
	if (middle > 0.0 && middle < 1.0) {
		if (t < middle) {
			return mixGradient(b, c0, c1, t / middle);
		}
		return mixGradient(b, c1, b.void2d_fx.gradientColor2, (t - middle) / (1.0 - middle));
	}
	return mixGradient(b, c0, c1, t);
}

export function fs(input: BatchInput, b: BatchBindings): Vec4f {
	const uvDx = dpdx(input.uv);
	const uvDy = dpdy(input.uv);
	const d = input.clipDistance;
	if (min(min(d.x, d.y), min(d.z, d.w)) < 0.0) {
		discard();
	}
	const meta = b.void2d_fx.gradientMeta;
	const params = b.void2d_fx.gradientParams;
	const gradientKind = (meta.x + 0.5) as int32;
	let texel = vec4f(0.0);
	if (gradientKind == 1 || gradientKind == 2) {
		const t = gradientKind == 1 ? clamp(input.uv.x, 0.0, 1.0) :
			clamp(length(input.uv), 0.0, 1.0);
		texel = gradientAt(b, t);
		if (meta.z > 0.5) {
			texel = vec4f(ditherRgb(texel.xyz, input.pixel), texel.w);
		}
	} else if (gradientKind == 3) {
		const spacing = max(params.x, 1.0);
		const width = clamp(params.y, 0.0, spacing);
		let diagonal = input.uv.x + input.uv.y;
		diagonal += fwidth(diagonal) * PATTERN_TIE_BIAS;
		texel = floorMod(diagonal, spacing) < width ? b.void2d_fx.gradientColor1 :
			b.void2d_fx.gradientColor0;
	} else if (gradientKind == 4) {
		const cell = max(params.x, 1.0);
		const at = input.uv + fwidth(input.uv) * PATTERN_TIE_BIAS;
		const parity = floorMod(floor(at.x / cell) + floor(at.y / cell), 2.0);
		texel = parity < 1.0 ? b.void2d_fx.gradientColor0 : b.void2d_fx.gradientColor1;
	} else {
		texel = textureSample(b.tex, b.smp, input.uv);
		if (b.void2d_fx.sourceParams.x > 0.5) {
			texel = vec4f(texel.w > 0.0 ? texel.xyz / texel.w : vec3f(0.0), texel.w);
		}
		if (input.coverageTexture > 0.5) {
			let coverage = texel.x;
			if (input.coverageTexture > 1.5) {
				const pageSize = vec2f(textureDimensions(b.tex, 0));
				coverage = sdfCoverage(coverage, sdfTexelsPerPixel(uvDx, uvDy, pageSize));
			}
			const gamma = applyContrastAndGamma(coverage, input.color.xyz,
				b.void2d_fx.textParams.x, b.void2d_fx.gammaRatios);
			texel = vec4f(1.0, 1.0, 1.0, gamma);
		}
	}
	const key = b.void2d_fx.colorKey;
	if (key.w > 0.5) {
		const kd = abs(texel.xyz - key.xyz);
		if (kd.x + kd.y + kd.z < 0.08) {
			texel.w = 0.0;
		}
	}
	let c = texel * input.color;
	// A premultiplied source (a render target the pass wrote through premultiplied blending)
	// already carries its coverage in rgb, so a tint alpha scales rgb as well; otherwise fading it
	// changes only the coverage, measured on filter/groupOpacity.
	c = vec4f(mix(c.xyz, c.xyz * input.color.w, input.srcPremult), c.w);
	c = b.void2d_fx.colorMatrix * c;
	c = c + b.void2d_fx.colorAdd;
	const premult = vec4f(c.xyz * c.w, c.w);
	return mix(premult, c, input.srcPremult);
}

// viewport.xy the logical size, .z flipV, .w physical pixels per logical pixel.
export struct UiParams {
	viewport: Vec4f;
	clipU: Vec4f;
	clipV: Vec4f;
	shift: Vec4f;
}

export struct UiVertexBindings {
	@binding(0) ui_params: UiParams;
}

// Per instance: iAffine a,b,c,d; iOriginSize tx,ty,w,h; iUvRadii an image's u0,v0,u1,v1 or a box's
// four corner radii TL TR BR BL; iBorders the side widths L T R B; iParams0.x the mode, then
// per-mode parameters; iParams1 gradient stops or a shadow's offset and spread.
export struct UiAttributes {
	corner: Vec2f;
	iAffine: Vec4f;
	iOriginSize: Vec4f;
	iUvRadii: Vec4f;
	iBorders: Vec4f;
	iParams0: Vec4f;
	iParams1: Vec4f;
	iColorFill: Vec4f;
	iColorBorder: Vec4f;
	iColorExtra: Vec4f;
}

// vLocalHalf.xy the point relative to the rect centre, .zw the half extents; vUvAa.xy the uv, .z
// one device pixel in local units, .w the mode.
export struct UiVaryings {
	vLocalHalf: Vec4f;
	vUvAa: Vec4f;
	vRadii: Vec4f;
	vBorders: Vec4f;
	vParams0: Vec3f;
	vParams1: Vec4f;
	vFill: Vec4f;
	vBorder: Vec4f;
	vExtra: Vec4f;
	clipDistance: Vec4f;
	vPixel: Vec2f;
	@builtin(position) clip: Vec4f;
}

export struct UiInput {
	vLocalHalf: Vec4f;
	vUvAa: Vec4f;
	vRadii: Vec4f;
	vBorders: Vec4f;
	vParams0: Vec3f;
	vParams1: Vec4f;
	vFill: Vec4f;
	vBorder: Vec4f;
	vExtra: Vec4f;
	clipDistance: Vec4f;
	vPixel: Vec2f;
}

export struct UiEffect {
	gammaRatios: Vec4f;
	textParams: Vec4f;
	colorMatrix: Mat4x4f;
	colorAdd: Vec4f;
	colorKey: Vec4f;
	effectParams: Vec4f;
}

export struct UiBindings {
	@binding(0) uiTex: Texture2d;
	@binding(0) uiSmp: Sampler;
	@binding(1) ui_fx: UiEffect;
}

function dilateStroke(width: float32, pixelsPerLocal: float32): float32 {
	if (width <= 0.0 || pixelsPerLocal <= 0.0) {
		return 0.0;
	}
	return max(width, 1.0 / pixelsPerLocal);
}

// The unified UI pipeline (VOID2D.md "P2"): one program, one 108-byte stride and a per-instance
// mode, so a card, its label and its image batch together. The SDF is evaluated in local space
// (GPUI.md:35-39), and the quad is inflated by one device pixel on every side before the affine,
// or the coverage ramp would be clipped by the geometry it softens. One device pixel across an
// edge is the geometric mean of the two affine-axis lengths times the target's pixel scale; a
// glyph keeps aa at zero, its atlas texel already antialiased, so its quad is the bitmap's rect.
export function uiVs(input: UiAttributes, b: UiVertexBindings): UiVaryings {
	const viewport = b.ui_params.viewport;
	const mode = input.iParams0.x;
	const sx = length(input.iAffine.xy) * viewport.w;
	const sy = length(input.iAffine.zw) * viewport.w;
	const s = sqrt(sx * sy);
	const aa: float32 = mode == 2.0 ? 0.0 : (s > 0.0 ? 1.0 / s : 0.0);
	const size = input.iOriginSize.zw;
	const inflate = mode == 5.0 ? vec2f(aa, 0.0) : vec2f(aa);
	const local = input.corner * (size + 2.0 * inflate) - inflate;
	const world = vec2f(
		input.iAffine.x * local.x + input.iAffine.z * local.y + input.iOriginSize.x,
		input.iAffine.y * local.x + input.iAffine.w * local.y + input.iOriginSize.y,
	);
	const moved = world + b.ui_params.shift.xy;
	const clipU = b.ui_params.clipU;
	const clipV = b.ui_params.clipV;
	let clipDistance = vec4f(1.0);
	if (clipU.w > clipU.z) {
		const cu = dot(world, clipU.xy);
		const cv = dot(world, clipV.xy);
		clipDistance = vec4f(cu - clipU.z, clipU.w - cu, cv - clipV.z, clipV.w - cv);
	}
	const ndc = vec2f(moved.x / viewport.x * 2.0 - 1.0, 1.0 - moved.y / viewport.y * 2.0);
	const clip = vec4f(ndc, 0.0, 1.0);
	const t = mix(input.iUvRadii.xy, input.iUvRadii.zw,
		size.x > 0.0 && size.y > 0.0 ? local / size : vec2f(0.0));
	const borders = input.iBorders;
	// An Oklab box gradient's two stops convert once per vertex, not per fragment, as GPUI's
	// prepare_gradient_color does: measured 42.4 -> 30.3 ms at 4000 full-screen layers.
	const oklabFill = mode == 0.0 && input.iParams0.z > 0.5 && input.iParams0.z < 1.5 &&
		floorMod(input.iParams0.w, 2.0) > 0.5;
	const fill = input.iColorFill;
	const extra = input.iColorExtra;
	return {
		vLocalHalf: vec4f(local - size * 0.5, size * 0.5),
		vUvAa: vec4f(viewport.z > 0.5 ? vec2f(t.x, 1.0 - t.y) : t, aa, mode),
		vRadii: mode == 2.0 ? vec4f(0.0) : input.iUvRadii,
		vBorders: mode == 0.0 ? vec4f(
			dilateStroke(borders.x, sx),
			dilateStroke(borders.y, sy),
			dilateStroke(borders.z, sx),
			dilateStroke(borders.w, sy),
		) : borders,
		vParams0: input.iParams0.yzw,
		vParams1: input.iParams1,
		vFill: oklabFill ? vec4f(linearToOklab(srgbToLinear(fill.xyz)), fill.w) : fill,
		vBorder: input.iColorBorder,
		vExtra: oklabFill ? vec4f(linearToOklab(srgbToLinear(extra.xyz)), extra.w) : extra,
		clipDistance: clipDistance,
		vPixel: moved * viewport.w,
		clip,
	};
}

function withEffect(b: UiBindings, p: Vec4f, keyTexel: Vec3f): Vec4f {
	if (b.ui_fx.effectParams.x < 0.5 || p.w <= 0.0) {
		return p;
	}
	let s = vec4f(p.xyz / p.w, p.w);
	const key = b.ui_fx.colorKey;
	if (key.w > 0.5) {
		const d = abs(keyTexel - key.xyz);
		if (d.x + d.y + d.z < 0.08) {
			s.w = 0.0;
		}
	}
	s = b.ui_fx.colorMatrix * s + b.ui_fx.colorAdd;
	return vec4f(s.xyz * s.w, s.w);
}

// Negative inside. `r` is clamped to the largest radius the box can hold, because a radius past
// that is not a rounded rect at all and silently produces a lens shape. src/void2d/sdf.ms holds
// the same arithmetic, which tests/oracle/coverage.ms judges against supersampled geometry.
export function roundedRectDistance(p: Vec2f, half: Vec2f, r: float32): float32 {
	const rr = clamp(r, 0.0, min(half.x, half.y));
	const q = abs(p) - (half - rr);
	return length(max(q, vec2f(0.0))) + min(max(q.x, q.y), 0.0) - rr;
}

export function smoothUnionDistance(a: float32, b: float32, k: float32): float32 {
	if (k <= 0.0) {
		return min(a, b);
	}
	const h = clamp(0.5 + 0.5 * (a - b) / k, 0.0, 1.0);
	return mix(a, b, h) - k * h * (1.0 - h);
}

export function cornerRadius(p: Vec2f, radii: Vec4f): float32 {
	return p.x < 0.0 ? (p.y < 0.0 ? radii.x : radii.w) : (p.y < 0.0 ? radii.y : radii.z);
}

// Linear, measured rather than inherited: a straight edge cuts a pixel's area linearly in its
// distance from the centre, where smoothstep overshoots by up to 0.094 (24 levels of 255);
// tests/oracle/coverage.ms convicted it and keeps the curve as a case that must fail.
export function coverageFromDistance(d: float32, aa: float32): float32 {
	if (aa <= 0.0) {
		return d <= 0.0 ? 1.0 : 0.0;
	}
	return clamp(0.5 - d / aa, 0.0, 1.0);
}

export function overCoverage(a: Vec4f, b: Vec4f, coverage: float32): Vec4f {
	const alpha = a.w * coverage + b.w * (1.0 - coverage);
	const rgb = a.xyz * (a.w * coverage) + b.xyz * (b.w * (1.0 - coverage));
	return vec4f(alpha > 0.0 ? rgb / alpha : vec3f(0.0), alpha);
}

// GPUI's gradient_color (shaders.wgsl:430-516) in local units: vParams0.y the fill kind (1 linear,
// 2 slash, 3 checker), vParams0.z the space plus 2 for dither, vFill and vExtra the two colours,
// already Oklab for an Oklab gradient (uiVs). Pattern edges ramp over aa, where GPUI's ramp is
// one device pixel.
function boxFillAt(input: UiInput, p: Vec2f, half: Vec2f, aa: float32): Vec4f {
	const kind = (input.vParams0.y + 0.5) as int32;
	const params = input.vParams1;
	const corner = p + half;
	if (kind == 1) {
		const angle = (floorMod(params.x, 360.0) - 90.0) * 0.017453292519943295;
		let direction = vec2f(cos(angle), sin(angle));
		const size = max(half * 2.0, vec2f(1e-6));
		if (size.x > size.y) {
			direction.y *= size.y / size.x;
		} else {
			direction.x *= size.x / size.y;
		}
		let t = dot(p, direction) / length(direction);
		t = abs(direction.x) > abs(direction.y) ? (t + half.x) / size.x : (t + half.y) / size.y;
		const span = params.z - params.y;
		t = span > 0.0 ? clamp((t - params.y) / span, 0.0, 1.0) : step(params.y, t);
		let c = mix(input.vFill, input.vExtra, t);
		if (floorMod(input.vParams0.z, 2.0) > 0.5) {
			c = vec4f(linearToSrgb(oklabToLinear(c.xyz)), c.w);
		}
		if (input.vParams0.z > 1.5) {
			c = vec4f(ditherRgb(c.xyz, input.vPixel), c.w);
		}
		return c;
	}
	if (kind == 2) {
		const height = params.x + params.y;
		const period = height * 0.7071067811865476;
		const pattern = floorMod((corner.x + corner.y) * 0.7071067811865476, period);
		const distance = min(pattern, period - pattern) - period * (params.x / height) * 0.5;
		return overCoverage(input.vFill, input.vExtra, coverageFromDistance(distance, aa));
	}
	const cell = floor((corner + vec2f(aa * PATTERN_TIE_BIAS)) / params.x);
	return floorMod(cell.x + cell.y, 2.0) > 0.5 ? input.vFill : input.vExtra;
}

export function cornerDashVelocity(first: float32, second: float32): float32 {
	if (first == 0.0) {
		return second;
	}
	if (second == 0.0) {
		return first;
	}
	return min(first, second);
}

export function dashAlpha(
	t: float32,
	period: float32,
	dashLength: float32,
	velocity: float32,
	aa: float32,
): float32 {
	if (velocity <= 0.0) {
		return 0.0;
	}
	const halfPeriod = period * 0.5;
	const halfLength = dashLength * 0.5;
	const centered = floorMod(t + halfPeriod - halfLength, period) - halfPeriod;
	return coverageFromDistance((abs(centered) - halfLength) / velocity, aa);
}

export function dashedBorderAlpha(
	p: Vec2f,
	half: Vec2f,
	rawRadii: Vec4f,
	borders: Vec4f,
	aa: float32,
): float32 {
	const radii = clamp(rawRadii, vec4f(0.0), vec4f(min(half.x, half.y)));
	const size = half * 2.0;
	const point = p + half;
	const radius = cornerRadius(p, radii);
	const cornerDelta = abs(p) - (half - vec2f(radius));
	const unrounded = radii.x == 0.0 && radii.y == 0.0 && radii.z == 0.0 && radii.w == 0.0;
	const horizontal = cornerDelta.x < cornerDelta.y;
	const dashLength: float32 = 2.0 / 3.0;
	let velocity: float32 = 0.0;
	let t: float32 = 0.0;
	let maxT: float32 = 0.0;
	let noBorder = false;
	if (unrounded) {
		const width = horizontal ? max(borders.y, borders.w) : max(borders.x, borders.z);
		noBorder = width <= 0.0;
		if (!noBorder) {
			velocity = 1.0 / (3.0 * width);
			t = (horizontal ? point.x : point.y) * velocity;
			maxT = (horizontal ? size.x : size.y) * velocity - dashLength;
		}
	} else {
		const dvT: float32 = borders.y > 0.0 ? 1.0 / (3.0 * borders.y) : 0.0;
		const dvR: float32 = borders.z > 0.0 ? 1.0 / (3.0 * borders.z) : 0.0;
		const dvB: float32 = borders.w > 0.0 ? 1.0 / (3.0 * borders.w) : 0.0;
		const dvL: float32 = borders.x > 0.0 ? 1.0 / (3.0 * borders.x) : 0.0;
		const sT = (size.x - radii.x - radii.y) * dvT;
		const sR = (size.y - radii.y - radii.z) * dvR;
		const sB = (size.x - radii.z - radii.w) * dvB;
		const sL = (size.y - radii.w - radii.x) * dvL;
		const cvTR = cornerDashVelocity(dvT, dvR);
		const cvBR = cornerDashVelocity(dvB, dvR);
		const cvBL = cornerDashVelocity(dvB, dvL);
		const cvTL = cornerDashVelocity(dvT, dvL);
		const quarterPi: float32 = 1.5707963267948966;
		const cTR = radii.y * quarterPi * cvTR;
		const cBR = radii.z * quarterPi * cvBR;
		const cBL = radii.w * quarterPi * cvBL;
		const cTL = radii.x * quarterPi * cvTL;
		const uptoTR = sT;
		const uptoR = uptoTR + cTR;
		const uptoBR = uptoR + sR;
		const uptoB = uptoBR + cBR;
		const uptoBL = uptoB + sB;
		const uptoL = uptoBL + cBL;
		const uptoTL = uptoL + sL;
		maxT = uptoTL + cTL;
		if (cornerDelta.x > 0.0 && cornerDelta.y > 0.0) {
			const angle = atan2(cornerDelta.y, cornerDelta.x);
			if (p.x >= 0.0) {
				if (p.y < 0.0) {
					velocity = cvTR;
					t = uptoR - angle * radii.y * velocity;
				} else {
					velocity = cvBR;
					t = uptoBR + angle * radii.z * velocity;
				}
			} else {
				if (p.y >= 0.0) {
					velocity = cvBL;
					t = uptoL - angle * radii.w * velocity;
				} else {
					velocity = cvTL;
					t = uptoTL + angle * radii.x * velocity;
				}
			}
		} else if (horizontal) {
			if (p.y < 0.0) {
				velocity = dvT;
				t = (point.x - radii.x) * velocity;
			} else {
				velocity = dvB;
				t = uptoBL - (point.x - radii.w) * velocity;
			}
		} else {
			if (p.x < 0.0) {
				velocity = dvL;
				t = uptoTL - (point.y - radii.x) * velocity;
			} else {
				velocity = dvR;
				t = uptoR + (point.y - radii.y) * velocity;
			}
		}
	}
	let alpha: float32 = 1.0;
	if (noBorder) {
		alpha = 0.0;
	} else if (maxT >= 1.0) {
		alpha = dashAlpha(t, maxT / floor(maxT), dashLength, velocity, aa);
	} else if (unrounded && maxT - dashLength > 0.0) {
		alpha = dashAlpha(t, maxT, dashLength, velocity, aa);
	}
	return alpha;
}

// GPUI's error function (shaders.wgsl:325), rational form; its polynomial error is orders below
// one 8-bit level. Mirrored in sdf.ms as erfApprox, where the coverage oracle judges the integral.
export function erfApprox(x: float32): float32 {
	const s = sign(x);
	const a = abs(x);
	const r1 = 1.0 + (0.278393 + (0.230389 + (0.000972 + 0.078108 * a) * a) * a) * a;
	const r2 = r1 * r1;
	return s - s / (r2 * r2);
}

// The Gaussian pdf, GPUI's gaussian.
export function gaussianPdf(x: float32, sigma: float32): float32 {
	return exp(-(x * x) / (2.0 * sigma * sigma)) / (sqrt(6.283185307179586) * sigma);
}

// One side's half-extent at |y|: the core width plus the chord the corner circle still covers at
// that height, GPUI's curved per side, where GPUI symmetrises to the point's quadrant.
export function scanlineHalf(hx: float32, hy: float32, ay: float32, r: float32): float32 {
	const dy = ay - (hy - r);
	const under = r * r - dy * dy;
	const chord = dy > 0.0 && under > 0.0 ? sqrt(under) : r;
	return hx - r + chord;
}

// The Gaussian-blurred rounded rect, GPUI's fs_shadow integral: a closed-form CDF difference
// along x (erfApprox) and four midpoint samples along y over the kernel's 3-sigma window clamped
// to the box. Judged against the kernel-integral oracle within 0.02 (worst measured 0.0078).
export function blurredCoverage(c: Vec2f, half: Vec2f, rr: Vec4f, sigma: float32): float32 {
	const low = c.y - half.y;
	const high = c.y + half.y;
	const start = clamp(-3.0 * sigma, low, high);
	const end = clamp(3.0 * sigma, low, high);
	const stepY = (end - start) / 4.0;
	const k = sqrt(0.5) / sigma;
	let acc: float32 = 0.0;
	let y = start + stepY * 0.5;
	for (let i = 0; i < 4; i++) {
		const scanY = c.y - y;
		const ay = abs(scanY);
		const wL = scanlineHalf(half.x, half.y, ay, scanY < 0.0 ? rr.x : rr.w);
		const wR = scanlineHalf(half.x, half.y, ay, scanY < 0.0 ? rr.y : rr.z);
		const hi = 0.5 + 0.5 * erfApprox((c.x + wL) * k);
		const lo = 0.5 + 0.5 * erfApprox((c.x - wR) * k);
		acc += (hi - lo) * gaussianPdf(y, sigma) * stepY;
		y += stepY;
	}
	return acc;
}

// The blur is applied by evaluating at p - offset, GPUI's CPU-side bounds offset as one
// subtraction; sigma <= 0 is the hard shadow.
export function shadowCoverage(
	p: Vec2f,
	half: Vec2f,
	radii: Vec4f,
	offset: Vec2f,
	sigma: float32,
	aa: float32,
): float32 {
	const rr = clamp(radii, vec4f(0.0), vec4f(min(half.x, half.y)));
	const c = p - offset;
	let coverage: float32 = 0.0;
	if (sigma <= 0.0) {
		coverage = coverageFromDistance(roundedRectDistance(c, half, cornerRadius(c, rr)), aa);
	} else {
		coverage = blurredCoverage(c, half, rr, sigma);
	}
	return coverage;
}

// The underline's signed distance: shape.x the thickness, shape.y above 0.5 a wavy line, else the
// straight bar filling the quad.
export function underlineDistance(p: Vec2f, half: Vec2f, shape: Vec4f): float32 {
	const thickness = shape.x;
	if (shape.y > 0.5) {
		const height = half.y * 2.0;
		const frequency = 6.283185307179586 * thickness / height;
		const amplitude = thickness * 0.8 / height;
		const phase = ((p.x + half.x) / height) * frequency;
		const slope = cos(phase) * amplitude * frequency;
		const distance = (p.y / height - sin(phase) * amplitude) * height /
			sqrt(1.0 + slope * slope);
		return abs(distance) - thickness * 0.5;
	}
	return roundedRectDistance(p, half, 0.0);
}

export function uiFs(input: UiInput, b: UiBindings): Vec4f {
	const uvDx = dpdx(input.vUvAa.xy);
	const uvDy = dpdy(input.vUvAa.xy);
	const d = input.clipDistance;
	if (min(min(d.x, d.y), min(d.z, d.w)) < 0.0) {
		discard();
	}
	const p = input.vLocalHalf.xy;
	const half = input.vLocalHalf.zw;
	const aa = input.vUvAa.z;
	const mode = (input.vUvAa.w + 0.5) as int32;
	if (mode == 3) {
		const radii = clamp(input.vBorders, vec4f(0.0), vec4f(min(half.x, half.y)));
		const coverage = coverageFromDistance(
			roundedRectDistance(p, half, cornerRadius(p, radii)), aa);
		let texel = textureSample(b.uiTex, b.uiSmp, input.vUvAa.xy);
		const keyTexel = input.vParams1.y > 0.5 && texel.w > 0.0 ? texel.xyz / texel.w : texel.xyz;
		if (input.vParams1.x > 0.5) {
			const gray = dot(texel.xyz, vec3f(0.2126, 0.7152, 0.0722));
			texel = vec4f(vec3f(gray), texel.w);
		}
		const fill = texel * input.vFill;
		const alpha = fill.w * coverage;
		const rgb = input.vParams1.y > 0.5 ? fill.xyz * (input.vFill.w * coverage) :
			fill.xyz * alpha;
		return withEffect(b, vec4f(rgb, alpha), keyTexel);
	}
	if (mode == 4) {
		const coverage = coverageFromDistance(underlineDistance(p, half, input.vBorders), aa);
		const alpha = input.vFill.w * coverage;
		return withEffect(b, vec4f(input.vFill.xyz * alpha, alpha), vec3f(1.0));
	}
	if (mode == 5) {
		const boxHalf = input.vBorders.xy;
		const radius = input.vBorders.z;
		const gloopiness = input.vBorders.w;
		const params = input.vParams1;
		let distance = roundedRectDistance(p, boxHalf, radius);
		if (params.y > 0.0) {
			const prevCenter = vec2f(params.x + params.y * 0.5 - boxHalf.x, -boxHalf.y * 2.0);
			const prev = roundedRectDistance(
				p - prevCenter, vec2f(params.y * 0.5, boxHalf.y), radius);
			distance = smoothUnionDistance(distance, prev, gloopiness);
		}
		if (params.w > 0.0) {
			const nextCenter = vec2f(params.z + params.w * 0.5 - boxHalf.x, boxHalf.y * 2.0);
			const next = roundedRectDistance(
				p - nextCenter, vec2f(params.w * 0.5, boxHalf.y), radius);
			distance = smoothUnionDistance(distance, next, gloopiness);
		}
		const coverage = coverageFromDistance(distance, aa);
		const alpha = input.vFill.w * coverage;
		return withEffect(b, vec4f(input.vFill.xyz * alpha, alpha), vec3f(1.0));
	}
	const extra = input.vExtra;
	const radiiIn = input.vRadii;
	if (mode == 1) {
		// A standalone drop or inset shadow. The box's half extents and blur ride in the borders
		// lane and the emitter inflates the quad (3 sigma plus offset plus spread for a drop,
		// nothing for an inset), so `half` is the quad's. vParams1 = (offsetX, offsetY, spread):
		// GPUI's drop rect dilated by the spread with the box's radii, its inset hole shrunk by
		// it with the radii shrunk alike (window.rs:4401-4445).
		const halfBox = input.vBorders.xy;
		const sigma = input.vBorders.z;
		const spread = input.vParams1.z;
		let alpha: float32 = 0.0;
		if (input.vBorders.w > 0.5) {
			const blur = shadowCoverage(p, max(halfBox - vec2f(spread), vec2f(0.0)),
				max(radiiIn - vec4f(spread), vec4f(0.0)), input.vParams1.xy, sigma, aa);
			alpha = (1.0 - blur) * coverageFromDistance(
				roundedRectDistance(p, halfBox, cornerRadius(p, radiiIn)), aa);
		} else {
			const offset = input.vParams1.xy;
			alpha = shadowCoverage(p, halfBox + vec2f(spread), radiiIn, offset, sigma, aa);
		}
		return withEffect(b, vec4f(extra.xyz * (extra.w * alpha), extra.w * alpha), vec3f(1.0));
	}
	// A shadowed box is one instance (cardOneInstance): the quad carries the shadow's extent, so
	// the box's half is derived back from the emitter's margin, 3 sigma plus the offset per axis,
	// nothing for an inset. vParams1 = (offsetX, offsetY, sigma, inset) while vExtra.a > 0, vExtra
	// the shadow colour; the margin is one contract with render.ms, as aaWidthForAffine is.
	let halfBox = half;
	const filled = mode == 0 && input.vParams0.y > 0.5;
	const shadowed = !filled && extra.w > 0.0;
	if (shadowed && input.vParams1.w <= 0.5) {
		halfBox = half - (vec2f(3.0 * input.vParams1.z) + abs(input.vParams1.xy));
	}
	const r = cornerRadius(p, radiiIn);
	const dOuter = roundedRectDistance(p, halfBox, r);
	// The border's inner edge is the outer rect inset per side, which moves its centre when two
	// opposite widths differ; each corner radius shrinks by the thicker side touching it.
	const borders = max(input.vBorders, vec4f(0.0));
	const inset = vec2f(borders.x + borders.z, borders.y + borders.w) * 0.5;
	const shift = vec2f(borders.x - borders.z, borders.y - borders.w) * 0.5;
	const innerRadii = max(radiiIn - vec4f(
		max(borders.x, borders.y),
		max(borders.y, borders.z),
		max(borders.z, borders.w),
		max(borders.w, borders.x),
	), vec4f(0.0));
	const innerPoint = p - shift;
	const dInner = roundedRectDistance(
		innerPoint, max(halfBox - inset, vec2f(0.0)), cornerRadius(innerPoint, innerRadii));
	// Area fractions, not a blend factor: the fill covers the inner rect and the border the ring
	// between the two, so a zero-width border has zero area (snap/zeroBorder: zero stays zero).
	const outer = coverageFromDistance(dOuter, aa);
	const inner = coverageFromDistance(dInner, aa);
	let ring = max(outer - inner, 0.0);
	if (mode != 2 && input.vParams0.x > 0.5) {
		ring *= dashedBorderAlpha(p, halfBox, radiiIn, borders, aa);
	}
	let fill = filled ? boxFillAt(input, p, halfBox, aa) : input.vFill;
	if (mode == 2) {
		let coverage = textureSample(b.uiTex, b.uiSmp, input.vUvAa.xy).x;
		if (input.vParams0.x > 0.5) {
			const pageSize = vec2f(textureDimensions(b.uiTex, 0));
			coverage = sdfCoverage(coverage, sdfTexelsPerPixel(uvDx, uvDy, pageSize));
		}
		fill.w = fill.w * applyContrastAndGamma(coverage, fill.xyz, b.ui_fx.textParams.x,
			b.ui_fx.gammaRatios);
	}
	const border = input.vBorder;
	const offset = input.vParams1.xy;
	let alpha = fill.w * inner + border.w * ring;
	let rgb = fill.xyz * (fill.w * inner) + border.xyz * (border.w * ring);
	if (shadowed && input.vParams1.w > 0.5) {
		// Inset: the complement of the blurred hole, clipped to the element, over the fill and
		// under the border, GPUI's paint order (style.rs:711-740) and the multi-instance form's.
		const blurCov = shadowCoverage(p, halfBox, radiiIn, offset, input.vParams1.z, aa);
		const sAlpha = (1.0 - blurCov) * outer * extra.w;
		const fillAlpha = fill.w * inner;
		const under = extra.xyz * sAlpha + fill.xyz * fillAlpha * (1.0 - sAlpha);
		const underAlpha = sAlpha + fillAlpha * (1.0 - sAlpha);
		const ringAlpha = border.w * ring;
		rgb = border.xyz * ringAlpha + under * (1.0 - ringAlpha);
		alpha = ringAlpha + underAlpha * (1.0 - ringAlpha);
	} else if (shadowed) {
		const sAlpha = shadowCoverage(p, halfBox, radiiIn, offset, input.vParams1.z, aa) * extra.w;
		rgb = rgb + extra.xyz * sAlpha * (1.0 - alpha);
		alpha = alpha + sAlpha * (1.0 - alpha);
	}
	return withEffect(b, vec4f(rgb, alpha), vec3f(1.0));
}
