// Full-resolution Forward auxiliary targets and ScreenFx passes. Normal/depth are nearest
// opaque surfaces (Heaps fwd.Renderer); mask edges reuse pixelArt postFs. Grayscale coverage
// is an ordinary RGB input to Heaps pass/FXAA; only the final mix supplies canvas alpha.

import { Vec4 } from "../math/math3d";
import { PixelFormat, LoadAction, StoreAction, endPass } from "../gpu/door";
import { FilterMode, Wrap } from "../gpu/state";
import {
	RenderTarget, Sampler, ColorAttachment, DepthAttachment, TargetLayout, NO_DEPTH, beginPass,
} from "../gpu/target";
import { Program } from "./gpu3d";
import { Material, Phase, TypedBlock } from "./material";
import {
	DrawContext, MaterialId, MaterialError, HandleError, addMaterial, releaseMaterial,
	reserveBlock, writeBlock,
} from "./draw";
import { OutlineMaskParams, OutlineMixParams, OutlineWidthParams } from "./post3d";
import { UniformError } from "./uniformPool";
import { Renderer, RendererError, drawScreen } from "./renderer";
import { screenState } from "./screenFx";

export struct ForwardOutlineSettings {
	// Straight RGBA in [0,1]; premultiplied once after the coverage filter.
	color: Vec4;
	// Framebuffer pixels, not CSS pixels. Depth threshold is normalized clip-depth distance.
	pixelWidth: float32;
	depthThreshold: float32;
	// A crease when dot(n0,n1) is below this value.
	normalThreshold: float32;
}

export function defaults(this typeof ForwardOutlineSettings): ForwardOutlineSettings {
	return {
		color: { x: 0.0, y: 0.0, z: 0.0, w: 1.0 },
		pixelWidth: 2.0,
		depthThreshold: 0.002,
		normalThreshold: 0.8,
	};
}

export function valid(this settings: ForwardOutlineSettings): boolean {
	const c: Vec4 = settings.color;
	return unit(c.x) && unit(c.y) && unit(c.z) && unit(c.w) &&
		Number.isFinite(settings.pixelWidth) && settings.pixelWidth >= 1.0 &&
		settings.pixelWidth <= 16.0 && Number.isFinite(settings.depthThreshold) &&
		settings.depthThreshold > 0.0 && settings.depthThreshold <= 1.0 &&
		Number.isFinite(settings.normalThreshold) && settings.normalThreshold >= -1.0 &&
		settings.normalThreshold <= 1.0;
}

function unit(value: float32): boolean {
	return Number.isFinite(value) && value >= 0.0 && value <= 1.0;
}

export function outlineColor(
	normal: Vec4,
	line: Vec4,
	coverage: float32,
	blend: float32,
): Vec4 {
	const alpha: float32 = line.w * coverage;
	return {
		x: normal.x * (1.0 - blend) + line.x * alpha * blend,
		y: normal.y * (1.0 - blend) + line.y * alpha * blend,
		z: normal.z * (1.0 - blend) + line.z * alpha * blend,
		w: normal.w * (1.0 - blend) + alpha * blend,
	};
}

// Heaps pass/FXAA.hx:14–41 on grayscale RGB: dot(c,c,c,lumA) == c. Same direction,
// reduction, bounded taps and range selection; auxiliary mask alpha is not canvas alpha.
export function fxaaCoverage(
	sample: (x: float32, y: float32) => float32,
	x: float32,
	y: float32,
): float32 {
	const nw: float32 = sample(x - 1.0, y - 1.0);
	const ne: float32 = sample(x + 1.0, y - 1.0);
	const sw: float32 = sample(x - 1.0, y + 1.0);
	const se: float32 = sample(x + 1.0, y + 1.0);
	const mid: float32 = sample(x, y);
	const low: float32 = Math.min(mid, Math.min(Math.min(nw, ne), Math.min(sw, se)));
	const high: float32 = Math.max(mid, Math.max(Math.max(nw, ne), Math.max(sw, se)));
	let dx: float32 = -((nw + ne) - (sw + se));
	let dy: float32 = (nw + sw) - (ne + se);
	const reduce: float32 = Math.max((nw + ne + sw + se) * (0.25 / 128.0), (1.0 / 8.0) as float32);
	const reciprocal: float32 =
		(1.0 / (Math.min(Math.abs(dx), Math.abs(dy)) + reduce)) as float32;
	dx = Math.min(8.0, Math.max(-8.0, dx * reciprocal));
	dy = Math.min(8.0, Math.max(-8.0, dy * reciprocal));
	const a: float32 = 0.5 * (
		sample(x + dx * (1.0 / 3.0 - 0.5), y + dy * (1.0 / 3.0 - 0.5)) +
		sample(x + dx * (2.0 / 3.0 - 0.5), y + dy * (2.0 / 3.0 - 0.5))
	);
	const b: float32 = a * 0.5 + 0.25 * (
		sample(x - dx * 0.5, y - dy * 0.5) + sample(x + dx * 0.5, y + dy * 0.5)
	);
	return b > low && b < high ? b : a;
}

export function outlineWidthCoverage(
	sample: (x: float32, y: float32) => float32,
	x: float32,
	y: float32,
	width: float32,
): float32 {
	const radius: float32 = (Math.abs(width - 2.0) * 0.5) as float32;
	const complement: boolean = width < 2.0;
	const step: float32 = (6.283185307179586 / OUTLINE_WIDTH_SAMPLES) as float32;
	let angle: float32 = 0.0;
	const own: float32 = sample(x, y);
	let maximum: float32 = complement ? 1.0 - own : own;
	for (let i = 0; i < OUTLINE_WIDTH_SAMPLES; i++) {
		angle += step;
		const value: float32 = sample(
			x + ((Math.cos(angle) * radius) as float32),
			y + ((Math.sin(angle) * radius) as float32),
		);
		maximum = Math.max(maximum, complement ? 1.0 - value : value);
	}
	return complement ? 1.0 - maximum : maximum;
}

export const FORWARD_OUTLINE_PASS_UNIFORM_LENGTH: int32 = 20;
export const FORWARD_OUTLINE_BLOCKS: Vec<int32> = [8, 8, 4];
export const OUTLINE_WIDTH_SAMPLES: int32 = 48;
export const OUTLINE_SCENE_LAYOUT: TargetLayout = {
	color0: PixelFormat.Rgba8, color1: PixelFormat.Rgba8,
	color2: PixelFormat.None, color3: PixelFormat.None,
	depth: PixelFormat.Depth, sampleCount: 1,
};
export const OUTLINE_SCREEN_LAYOUT: TargetLayout = {
	color0: PixelFormat.Rgba8, color1: PixelFormat.None,
	color2: PixelFormat.None, color3: PixelFormat.None,
	depth: PixelFormat.None, sampleCount: 1,
};
const ZERO: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 0.0 };
const NORMAL_CLEAR: Vec4 = { x: 0.5, y: 0.5, z: 0.5, w: 0.0 };

export interface ForwardOutlinePass {
	lit: RenderTarget;
	normal: RenderTarget;
	depth: RenderTarget;
	mask: RenderTarget;
	width: RenderTarget;
	linearSampler: Sampler;
	maskMaterial: MaterialId;
	mixMaterial: MaterialId;
	widthMaterial: MaterialId;
	maskBlock: TypedBlock<OutlineMaskParams>;
	mixBlock: TypedBlock<OutlineMixParams>;
	widthBlock: TypedBlock<OutlineWidthParams>;
	sceneColors: Vec<ColorAttachment>;
	translucentColors: Vec<ColorAttachment>;
	maskColors: Vec<ColorAttachment>;
	widthColors: Vec<ColorAttachment>;
	sceneDepth: DepthAttachment;
	translucentDepth: DepthAttachment;
}

export function reserve(this typeof ForwardOutlinePass, context: DrawContext): ForwardOutlinePass {
	const mask: Result<TypedBlock<OutlineMaskParams>, UniformError> =
		reserveBlock<OutlineMaskParams>(context, 0);
	const mix: Result<TypedBlock<OutlineMixParams>, UniformError> =
		reserveBlock<OutlineMixParams>(context, 0);
	const width: Result<TypedBlock<OutlineWidthParams>, UniformError> =
		reserveBlock<OutlineWidthParams>(context, 0);
	if (!mask.ok || !mix.ok || !width.ok) { unreachable; }
	const maskAdded: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.plain(Program.OutlineMask, screenState(), Phase.Opaque), uniforms: mask.value.block,
	});
	const mixAdded: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.plain(Program.OutlineMix, screenState(), Phase.Opaque), uniforms: mix.value.block,
	});
	const widthAdded: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.plain(Program.OutlineWidth, screenState(), Phase.Opaque), uniforms: width.value.block,
	});
	if (!maskAdded.ok || !mixAdded.ok || !widthAdded.ok) { unreachable; }
	return {
		lit: RenderTarget.unallocated(PixelFormat.Rgba8, true),
		normal: RenderTarget.unallocated(PixelFormat.Rgba8, true),
		depth: RenderTarget.unallocated(PixelFormat.Depth, true),
		mask: RenderTarget.unallocated(PixelFormat.Rgba8, true),
		width: RenderTarget.unallocated(PixelFormat.Rgba8, true),
		linearSampler: { filter: FilterMode.Linear, wrap: Wrap.Clamp, handle: 0 },
		maskMaterial: maskAdded.value, mixMaterial: mixAdded.value, widthMaterial: widthAdded.value,
		maskBlock: mask.value, mixBlock: mix.value, widthBlock: width.value,
		sceneColors: new Array(2), translucentColors: new Array(1), maskColors: new Array(1),
		widthColors: new Array(1),
		sceneDepth: NO_DEPTH, translucentDepth: NO_DEPTH,
	};
}

export function adoptContext(this pass: ForwardOutlinePass): void {
	pass.linearSampler = Sampler.create(FilterMode.Linear, Wrap.Clamp);
}

export function resize(
	this pass: ForwardOutlinePass,
	width: int32,
	height: int32,
	widthPass: boolean,
): void {
	pass.lit.resize(width, height);
	pass.normal.resize(width, height);
	pass.depth.resize(width, height);
	pass.mask.resize(width, height);
	if (widthPass) {
		pass.width.resize(width, height);
		pass.widthColors[0] = pass.width.asColor(LoadAction.DontCare, ZERO);
	}
	pass.sceneColors[0] = pass.lit.asColor(LoadAction.Clear, ZERO);
	pass.sceneColors[1] = pass.normal.asColor(LoadAction.Clear, NORMAL_CLEAR);
	pass.translucentColors[0] = pass.lit.asColor(LoadAction.Load, ZERO);
	pass.maskColors[0] = pass.mask.asColor(LoadAction.DontCare, ZERO);
	pass.sceneDepth = pass.depth.asDepth(LoadAction.Clear, 1.0, StoreAction.Store);
	pass.translucentDepth = pass.depth.asDepth(LoadAction.Load, 1.0, StoreAction.Store);
}

export function writeSettings(
	this pass: ForwardOutlinePass,
	context: DrawContext,
	settings: ForwardOutlineSettings,
	blend: float32,
	zeroToOne: boolean,
): void {
	const color: Vec4 = settings.color;
	const masked = writeBlock(context, pass.maskBlock, {
		outlineEdge: {
			x: 2.0, y: settings.depthThreshold, z: settings.normalThreshold, w: zeroToOne ? 1.0 : 2.0,
		},
		outlineDepthMap: { x: zeroToOne ? 0.0 : -1.0, y: blend, z: 0.0, w: 0.0 },
	});
	const mixed = writeBlock(context, pass.mixBlock, {
		outlineColor: { x: color.x * color.w, y: color.y * color.w, z: color.z * color.w, w: color.w },
		outlineMix: { x: blend, y: 0.0, z: 0.0, w: 0.0 },
	});
	const widened = writeBlock(context, pass.widthBlock, {
		outlineWidth: {
			x: (Math.abs(settings.pixelWidth - 2.0) * 0.5) as float32,
			y: settings.pixelWidth < 2.0 ? 1.0 : 0.0,
			z: 0.0,
			w: 0.0,
		},
	});
	if (!masked.ok || !mixed.ok || !widened.ok) { unreachable; }
}

export function prepare(
	this pass: ForwardOutlinePass,
	context: DrawContext,
	settings: ForwardOutlineSettings,
	blend: float32,
	zeroToOne: boolean,
	pointSampler: uint32,
): void {
	pass.writeSettings(context, settings, blend, zeroToOne);
	context.materials[pass.maskMaterial.index].texture0 = pass.normal.asTexture();
	context.materials[pass.maskMaterial.index].texture1 = pass.depth.asTexture();
	context.materials[pass.maskMaterial.index].sampler0 = pointSampler;
	context.materials[pass.maskMaterial.index].sampler1 = pointSampler;
	context.materials[pass.mixMaterial.index].texture0 = pass.lit.asTexture();
	context.materials[pass.mixMaterial.index].texture1 = settings.pixelWidth == 2.0 ?
		pass.mask.asTexture() : pass.width.asTexture();
	context.materials[pass.widthMaterial.index].texture0 = pass.mask.asTexture();
	context.materials[pass.widthMaterial.index].sampler0 = pass.linearSampler.asHandle();
	context.materials[pass.mixMaterial.index].sampler0 = pointSampler;
	context.materials[pass.mixMaterial.index].sampler1 = pass.linearSampler.asHandle();
}

export function drawMask(this pass: ForwardOutlinePass, core: Renderer): void {
	beginPass(pass.maskColors, NO_DEPTH);
	const drawn: Result<int32, RendererError> = drawScreen(core, pass.maskMaterial,
		OUTLINE_SCREEN_LAYOUT);
	if (!drawn.ok) { unreachable; }
	endPass();
}

export function drawWidth(this pass: ForwardOutlinePass, core: Renderer): void {
	beginPass(pass.widthColors, NO_DEPTH);
	const drawn: Result<int32, RendererError> =
		drawScreen(core, pass.widthMaterial, OUTLINE_SCREEN_LAYOUT);
	if (!drawn.ok) { unreachable; }
	endPass();
}

export function drawMix(
	this pass: ForwardOutlinePass,
	core: Renderer,
	colors: Vec<ColorAttachment>,
): void {
	beginPass(colors, NO_DEPTH);
	const drawn: Result<int32, RendererError> =
		drawScreen(core, pass.mixMaterial, OUTLINE_SCREEN_LAYOUT);
	if (!drawn.ok) { unreachable; }
	endPass();
}

export function close(this pass: ForwardOutlinePass, context: DrawContext): void {
	pass.lit.close();
	pass.normal.close();
	pass.depth.close();
	pass.mask.close();
	pass.width.close();
	pass.linearSampler = pass.linearSampler.released();
	const mask: Result<int32, HandleError> = releaseMaterial(context, pass.maskMaterial);
	const mix: Result<int32, HandleError> = releaseMaterial(context, pass.mixMaterial);
	const width: Result<int32, HandleError> = releaseMaterial(context, pass.widthMaterial);
	if (!mask.ok || !mix.ok || !width.ok) { unreachable; }
}
