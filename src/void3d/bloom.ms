// Bevy 157e1ce6 crates/bevy_post_process/src/bloom over the HDR target, before the tone map: a
// chain of half-size mips, each downsampled from the one above (the first with Karis' firefly
// average and an optional soft threshold), then each upsampled onto the one above it and the
// last onto the HDR target, blended by mod.rs compute_blend_factor. Heaps has no 3D bloom (only
// h2d.filter.Bloom): docs/VOID3D.md "Bloom, as built".

import { Program } from "./gpu3d";
import { PixelFormat, LoadAction, endPass } from "../gpu/door";
import { Blend, FilterMode, RenderState, Wrap } from "../gpu/state";
import { TypedBlock } from "./material";
import { Vec4 } from "../math/math3d";
import { Vec4f } from "../shader/std";
import { BloomParams } from "./post3d";
import { uniformSize } from "../shader/uniform";
import {
	RenderTarget,
	ColorAttachment,
	TargetLayout,
	Sampler,
	NO_DEPTH,
	beginPass,
} from "../gpu/target";
import {
	DrawContext,
	MaterialId,
	HandleError,
	releaseMaterial,
	writeBlock,
} from "./draw";
import { UniformError, stopOnFailedWrite } from "./uniformPool";
import { screenState, reserveScreenBlock, addScreenMaterial } from "./screenFx";
import { Renderer, RendererError, drawScreen } from "./renderer";

// settings.rs BloomCompositeMode.
export enum BloomCompositeMode {
	EnergyConserving,
	Additive,
}

// settings.rs Bloom, without the anamorphic `scale` (docs/VOID3D.md, Bloom).
export struct BloomSettings {
	intensity: float32;
	lowFrequencyBoost: float32;
	lowFrequencyBoostCurvature: float32;
	highPassFrequency: float32;
	threshold: float32;
	thresholdSoftness: float32;
	compositeMode: BloomCompositeMode;
	maxMipDimension: int32;
}

// settings.rs Bloom::NATURAL.
export function natural(this typeof BloomSettings): BloomSettings {
	return {
		intensity: 0.15,
		lowFrequencyBoost: 0.7,
		lowFrequencyBoostCurvature: 0.95,
		highPassFrequency: 1.0,
		threshold: 0.0,
		thresholdSoftness: 0.0,
		compositeMode: BloomCompositeMode.EnergyConserving,
		maxMipDimension: 512,
	};
}

// post3d.ms bloomParams: one texel of the source, then of the target; the upsample's blend
// factor; the soft threshold's precomputations.
export const BLOOM_UNIFORM_SLOT: int32 = 0;
export const BLOOM_UNIFORM_LENGTH: int32 = uniformSize<BloomParams>() / 4;

// The pool floats a BloomPass reserves: one block for each of its three programs.
export const BLOOM_PASS_UNIFORM_LENGTH: int32 = 3 * BLOOM_UNIFORM_LENGTH;

// Every bloom pass: one Rgba16f mip, no depth.
export const BLOOM_LAYOUT: TargetLayout = {
	color0: PixelFormat.Rgba16f,
	color1: PixelFormat.None,
	color2: PixelFormat.None,
	color3: PixelFormat.None,
	depth: PixelFormat.None,
	sampleCount: 1,
};

const NO_CLEAR: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 0.0 };

// mod.rs:326, `max_mip_dimension.ilog2().max(2) - 1`.
export function bloomMipCount(maxMipDimension: int32): int32 {
	let log: int32 = 0;
	while ((1 << (log + 1)) <= maxMipDimension) { log = log + 1; }
	return (log > 2 ? log : 2) - 1;
}

// mod.rs:335, mip 0's size: the frame scaled so its height is `maxMipDimension`, rounded.
export function bloomMipWidth(width: int32, height: int32, maxMipDimension: int32): int32 {
	const ratio: float64 = (maxMipDimension as float64) / (height as float64);
	const scaled: int32 = Math.round((width as float64) * ratio) as int32;
	return scaled > 1 ? scaled : 1;
}

// mod.rs:486-500 compute_blend_factor, `mip` the lower frequency level blended into the one
// above it.
export function bloomBlendFactor(settings: BloomSettings, mip: float32, maxMip: float32): float32 {
	const curve: float32 =
		Math.pow(1.0 - mip / maxMip, 1.0 / (1.0 - settings.lowFrequencyBoostCurvature)) as float32;
	let lowFrequencyBoost: float32 = (1.0 - curve) * settings.lowFrequencyBoost;
	const frequency: float32 = settings.highPassFrequency;
	let highPass: float32 = ((mip / maxMip) - frequency) / frequency;
	if (highPass < 0.0) { highPass = 0.0; }
	if (highPass > 1.0) { highPass = 1.0; }
	if (settings.compositeMode == BloomCompositeMode.EnergyConserving) {
		lowFrequencyBoost = lowFrequencyBoost * (1.0 - settings.intensity);
	}
	return (settings.intensity + lowFrequencyBoost) * (1.0 - highPass);
}

// settings.rs:243-251, the soft threshold's precomputations.
export function thresholdOf(settings: BloomSettings): Vec4f {
	let softness: float32 = settings.thresholdSoftness;
	if (softness < 0.0) { softness = 0.0; }
	if (softness > 1.0) { softness = 1.0; }
	const knee: float32 = settings.threshold * softness;
	return {
		x: settings.threshold,
		y: settings.threshold - knee,
		z: 2.0 * knee,
		w: 0.25 / (knee + 0.00001),
	};
}

export function paramsOf(
	sourceWidth: int32,
	sourceHeight: int32,
	targetWidth: int32,
	targetHeight: int32,
	blend: float32,
	threshold: Vec4f,
): BloomParams {
	return {
		bloomTexel: {
			x: 1.0 / (sourceWidth as float32),
			y: 1.0 / (sourceHeight as float32),
			z: 1.0 / (targetWidth as float32),
			w: 1.0 / (targetHeight as float32),
		},
		bloomBlend: { x: blend, y: 0.0, z: 0.0, w: 0.0 },
		bloomThreshold: threshold,
	};
}

// upsampling_pipeline.rs:74-121 with the factor in alpha (its TODO at :86): colour One /
// OneMinusSrcAlpha for energy conserving, One / One for additive; the target's alpha kept.
export function upsampleState(mode: BloomCompositeMode): RenderState {
	const destination: Blend =
		mode == BloomCompositeMode.EnergyConserving ? Blend.OneMinusSourceAlpha : Blend.One;
	return {
		...screenState().withBlend(Blend.One, destination),
		blendAlphaSource: Blend.Zero,
		blendAlphaDestination: Blend.One,
	};
}

export interface BloomPass {
	settings: BloomSettings | null;
	mips: Vec<RenderTarget>;
	colors: Vec<ColorAttachment>;
	sampler: Sampler;
	firstBlock: TypedBlock<BloomParams>;
	downBlock: TypedBlock<BloomParams>;
	upBlock: TypedBlock<BloomParams>;
	first: MaterialId;
	down: MaterialId;
	up: MaterialId;
}

function reserveParams(context: DrawContext): TypedBlock<BloomParams> {
	return reserveScreenBlock<BloomParams>(context, BLOOM_UNIFORM_SLOT, "BloomPass.reserve");
}

function addScreen(
	context: DrawContext,
	program: Program,
	state: RenderState,
	block: TypedBlock<BloomParams>,
): MaterialId {
	return addScreenMaterial(context, program, state, block.block, "BloomPass.reserve");
}

// Reserves the three blocks and adds the three materials to `context`, whose pool the caller
// checked fits BLOOM_PASS_UNIFORM_LENGTH. Off until setSettings; no GPU object is made here.
export function reserve(this typeof BloomPass, context: DrawContext): BloomPass {
	const firstBlock: TypedBlock<BloomParams> = reserveParams(context);
	const downBlock: TypedBlock<BloomParams> = reserveParams(context);
	const upBlock: TypedBlock<BloomParams> = reserveParams(context);
	const upState: RenderState = upsampleState(BloomCompositeMode.EnergyConserving);
	return {
		settings: null,
		mips: [],
		colors: new Array(1),
		sampler: { filter: FilterMode.Linear, wrap: Wrap.Clamp, handle: 0, generation: 0 },
		firstBlock: firstBlock,
		downBlock: downBlock,
		upBlock: upBlock,
		first: addScreen(context, Program.BloomDownsampleFirst, screenState(), firstBlock),
		down: addScreen(context, Program.BloomDownsample, screenState(), downBlock),
		up: addScreen(context, Program.BloomUpsample, upState, upBlock),
	};
}

function stopOnSettings(settings: BloomSettings): void {
	console.log(`void3d: setBloom with intensity ${settings.intensity}, max mip dimension ` +
		`${settings.maxMipDimension} and high-pass frequency ${settings.highPassFrequency}; ` +
		"intensity is finite and not negative, the dimension at least 4, the frequency above 0 " +
		"and the curvature below 1");
	unreachable;
}

// Turns bloom on with `settings`, or off with null, which releases the mips.
export function setSettings(
	this pass: BloomPass,
	context: DrawContext,
	settings: BloomSettings | null,
): void {
	if (settings !== null) {
		const valid: boolean = Number.isFinite(settings.intensity) && settings.intensity >= 0.0 &&
			settings.maxMipDimension >= 4 && settings.highPassFrequency > 0.0 &&
			settings.lowFrequencyBoostCurvature < 1.0;
		if (!valid) { stopOnSettings(settings); }
		context.materials[pass.up.index].pass = upsampleState(settings.compositeMode);
	} else {
		pass.closeMips();
	}
	pass.settings = settings;
}

export function isOn(this pass: BloomPass): boolean {
	return pass.settings !== null;
}

function closeMips(this pass: BloomPass): void {
	for (const mip of pass.mips) { mip.close(); }
	pass.mips = [];
}

// Makes the sampler again for a new GPU context; the mips follow from resize.
export function adoptContext(this pass: BloomPass): void {
	pass.sampler = Sampler.create(pass.sampler.filter, pass.sampler.wrap);
}

// The mips for a `width` × `height` HDR target; allocates only when the size, the settings'
// dimension or the GPU context changed.
export function resize(this pass: BloomPass, width: int32, height: int32): void {
	const settings: BloomSettings | null = pass.settings;
	if (settings === null) { return; }
	const count: int32 = bloomMipCount(settings.maxMipDimension);
	if ((pass.mips.length as int32) != count) {
		pass.closeMips();
		for (let i = 0; i < count; i++) {
			pass.mips.push(RenderTarget.unallocated(PixelFormat.Rgba16f, true));
		}
	}
	const mipWidth: int32 = bloomMipWidth(width, height, settings.maxMipDimension);
	for (let i = 0; i < count; i++) {
		const w: int32 = mipWidth >> i;
		const h: int32 = settings.maxMipDimension >> i;
		pass.mips[i].resize(w > 1 ? w : 1, h > 1 ? h : 1);
	}
}

// One fullscreen pass of `material` from `source` into `target`.
function drawMip(
	pass: BloomPass,
	core: Renderer,
	material: MaterialId,
	block: TypedBlock<BloomParams>,
	source: RenderTarget,
	target: RenderTarget,
	load: LoadAction,
	blend: float32,
	threshold: Vec4f,
): void {
	const context: DrawContext = core.context;
	context.materials[material.index].texture0 = source.asTexture();
	context.materials[material.index].sampler0 = pass.sampler.asHandle();
	const written: Result<int32, UniformError> = writeBlock(context, block,
		paramsOf(source.width, source.height, target.width, target.height, blend, threshold));
	if (!written.ok) { stopOnFailedWrite("BloomPass.draw", written.error); }
	pass.colors[0] = target.asColor(load, NO_CLEAR);
	beginPass(pass.colors, NO_DEPTH);
	const drawn: Result<int32, RendererError> = drawScreen(core, material, BLOOM_LAYOUT);
	if (!drawn.ok) { unreachable; }
	endPass();
}

// mod.rs:184-270: the first downsample from `hdr`, the downsamples, the upsamples, and the final
// upsample onto `hdr`. resize ran for this frame's size first.
export function draw(this pass: BloomPass, core: Renderer, hdr: RenderTarget): void {
	const settings: BloomSettings | null = pass.settings;
	if (settings === null) { return; }
	const count: int32 = pass.mips.length as int32;
	const maxMip: float32 = (count - 1) as float32;
	const threshold: Vec4f = thresholdOf(settings);
	drawMip(pass, core, pass.first, pass.firstBlock, hdr, pass.mips[0], LoadAction.DontCare, 0.0,
		threshold);
	for (let i = 1; i < count; i++) {
		drawMip(pass, core, pass.down, pass.downBlock, pass.mips[i - 1], pass.mips[i],
			LoadAction.DontCare, 0.0, threshold);
	}
	for (let i = count - 1; i >= 1; i--) {
		const factor: float32 = bloomBlendFactor(settings, i as float32, maxMip);
		drawMip(pass, core, pass.up, pass.upBlock, pass.mips[i], pass.mips[i - 1], LoadAction.Load,
			factor, threshold);
	}
	const last: float32 = bloomBlendFactor(settings, 0.0, maxMip);
	drawMip(pass, core, pass.up, pass.upBlock, pass.mips[0], hdr, LoadAction.Load, last, threshold);
}

export function close(this pass: BloomPass, context: DrawContext, call: string): void {
	pass.closeMips();
	pass.sampler = pass.sampler.released();
	for (const material of [pass.first, pass.down, pass.up]) {
		const released: Result<int32, HandleError> = releaseMaterial(context, material);
		if (!released.ok) {
			console.log(`void3d: ${call} found a bloom material ${released.error.toString()}`);
			unreachable;
		}
	}
}
