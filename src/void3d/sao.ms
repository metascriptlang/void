// Heaps' ScalableAO (h3d/pass/ScalableAO.hx, shader h3d/shader/SAO.hx) as a screen pass over a
// caller's depth and normal targets, into an occlusion target of its own: docs/VOID3D.md
// "Ambient occlusion".

import {
	Program,
	ProgramKey,
	SAO_EYE,
	SAO_FADE,
	SAO_INVERSE_VIEW_PROJ,
	SAO_NOISE,
	SAO_RADIUS,
	SAO_TAPS,
	SAO_UNIFORM_LENGTH,
	SAO_UNIFORM_SLOT,
	SAO_VIEW_DEPTH,
} from "./gpu3d";
import { PixelFormat, LoadAction, depthZeroToOne, endPass } from "../gpu/door";
import { FilterMode, Wrap } from "../gpu/state";
import { Texture, TextureError } from "../gpu/texture";
import {
	RenderTarget,
	ColorAttachment,
	TargetLayout,
	Sampler,
	NO_DEPTH,
	beginPass,
} from "../gpu/target";
import { Material, Phase, UniformBlock } from "./material";
import { Vec4 } from "../math/math3d";
import {
	DrawContext,
	MaterialId,
	MaterialError,
	HandleError,
	addMaterial,
	releaseMaterial,
	reserveUniforms,
	writeUniforms,
} from "./draw";
import { UniformError } from "./uniformPool";
import { screenState } from "./screenFx";
import { Renderer, RendererError, drawScreen } from "./renderer";
import { Camera3D, CameraView, ProjectionKind } from "./camera";
import { pcgHash } from "../particles/curve";

// SAO's USE_START_FADE or USE_FADE range, in world units from the camera.
export struct SaoFade {
	start: float32;
	end: float32;
}

// SAO's parameters and constants, without useWorldUV (the noise follows the screen).
export struct ScalableAoSettings {
	numSamples: int32;
	numSpiralTurns: int32;
	sampleRadius: float32;
	intensity: float32;
	bias: float32;
	noiseScaleX: float32;
	noiseScaleY: float32;
	scalableBias: boolean;
	startFade: SaoFade | null;
	fade: SaoFade | null;
}

// SAO.new.
export function defaults(this typeof ScalableAoSettings): ScalableAoSettings {
	return {
		numSamples: 20,
		numSpiralTurns: 7,
		sampleRadius: 1.0,
		intensity: 1.0,
		bias: 0.01,
		noiseScaleX: 10.0,
		noiseScaleY: 10.0,
		scalableBias: false,
		startFade: null,
		fade: null,
	};
}

function finite(value: float32): boolean {
	return Number.isFinite(value);
}

function validFade(fade: SaoFade | null): boolean {
	return fade === null || (finite(fade.start) && finite(fade.end) && fade.end > fade.start);
}

// SAO's @const bounds (127 samples, 15 turns) and a radius the taps can divide by.
export function valid(this settings: ScalableAoSettings): boolean {
	return settings.numSamples >= 1 && settings.numSamples <= 127 &&
		settings.numSpiralTurns >= 1 && settings.numSpiralTurns <= 15 &&
		finite(settings.sampleRadius) && settings.sampleRadius > 0.0 &&
		finite(settings.intensity) && settings.intensity >= 0.0 && finite(settings.bias) &&
		finite(settings.noiseScaleX) && finite(settings.noiseScaleY) &&
		validFade(settings.startFade) && validFade(settings.fade);
}

// A fade that is off: every distance from the camera is past the start fade's end, and none
// reaches the end fade's start, so saoFaded leaves the occlusion as it is.
export const SAO_NO_START_FADE: SaoFade = { start: -2.0, end: -1.0 };
export const SAO_NO_FADE: SaoFade = { start: 1.0e30, end: 2.0e30 };

// ScalableAO.apply's uniforms for `camera` seen as `view`: SAO's fovTan, 1 / (2 tan(fovY / 2)),
// and its invOrthoHeight are both half the projection's y scale.
export function writeSaoBlock(
	settings: ScalableAoSettings,
	camera: Camera3D,
	view: CameraView,
	zeroToOne: boolean,
	out: Span<float32>,
): void {
	view.inverseViewProj.writeTo(out, SAO_INVERSE_VIEW_PROJ);
	const forward = view.basis.forward;
	out[SAO_VIEW_DEPTH] = forward.x;
	out[SAO_VIEW_DEPTH + 1] = forward.y;
	out[SAO_VIEW_DEPTH + 2] = forward.z;
	out[SAO_VIEW_DEPTH + 3] = -forward.dot(view.eye);
	out[SAO_RADIUS] = settings.sampleRadius;
	out[SAO_RADIUS + 1] = settings.intensity;
	out[SAO_RADIUS + 2] = settings.bias;
	out[SAO_RADIUS + 3] = view.projectionY * 0.5;
	out[SAO_TAPS] = settings.numSamples as float32;
	out[SAO_TAPS + 1] = settings.numSpiralTurns as float32;
	out[SAO_TAPS + 2] = camera.projection.kind == ProjectionKind.Orthographic ? 1.0 : 0.0;
	out[SAO_TAPS + 3] = settings.scalableBias ? 1.0 : 0.0;
	out[SAO_NOISE] = settings.noiseScaleX;
	out[SAO_NOISE + 1] = settings.noiseScaleY;
	out[SAO_NOISE + 2] = zeroToOne ? 1.0 : 0.0;
	out[SAO_NOISE + 3] = 0.0;
	out[SAO_EYE] = view.eye.x;
	out[SAO_EYE + 1] = view.eye.y;
	out[SAO_EYE + 2] = view.eye.z;
	out[SAO_EYE + 3] = 0.0;
	const startFade: SaoFade = settings.startFade ?? SAO_NO_START_FADE;
	const fade: SaoFade = settings.fade ?? SAO_NO_FADE;
	out[SAO_FADE] = startFade.start;
	out[SAO_FADE + 1] = startFade.end;
	out[SAO_FADE + 2] = fade.start;
	out[SAO_FADE + 3] = fade.end;
}

export const SAO_NOISE_SIZE: int32 = 128;

// Texture.genNoise(128) as Texture.allocNoise fills it: one random byte per texel in r, g and b,
// alpha opaque. Heaps draws it from Std.random on every run; a hash of the texel's index keeps
// the image the same from run to run.
export function saoNoisePixels(): Vec<uint32> {
	let pixels: Vec<uint32> = [];
	const count: int32 = SAO_NOISE_SIZE * SAO_NOISE_SIZE;
	for (let i = 0; i < count; i++) {
		const n: uint32 = pcgHash(i as uint32) >> 24;
		pixels.push(0xFF000000 | n | (n << 8) | (n << 16));
	}
	return pixels;
}

// The occlusion target: one Rgba8 colour, no depth.
export const SAO_LAYOUT: TargetLayout = {
	color0: PixelFormat.Rgba8,
	color1: PixelFormat.None,
	color2: PixelFormat.None,
	color3: PixelFormat.None,
	depth: PixelFormat.None,
	sampleCount: 1,
};

const NO_CLEAR: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 0.0 };

export interface ScalableAoPass {
	settings: ScalableAoSettings | null;
	occlusion: RenderTarget;
	noise: Texture | null;
	pointSampler: Sampler;
	noiseSampler: Sampler;
	block: UniformBlock;
	material: MaterialId;
	values: Vec<float32>;
	colors: Vec<ColorAttachment>;
}

// Reserves the block and adds the material to `context`, whose pool the caller checked fits
// SAO_UNIFORM_LENGTH. Off until setSettings; no GPU object is made here.
export function reserve(this typeof ScalableAoPass, context: DrawContext): ScalableAoPass {
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, SAO_UNIFORM_SLOT, SAO_UNIFORM_LENGTH);
	if (!reserved.ok) {
		console.log("void3d: ScalableAoPass.reserve found no room for its checked block");
		unreachable;
	}
	const added: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.keyed(ProgramKey.of(Program.Sao), screenState(), Phase.Opaque),
		uniforms: reserved.value,
	});
	if (!added.ok) { unreachable; }
	return {
		settings: null,
		occlusion: RenderTarget.unallocated(PixelFormat.Rgba8, true),
		noise: null,
		pointSampler: { filter: FilterMode.Nearest, wrap: Wrap.Clamp, handle: 0, generation: 0 },
		noiseSampler: { filter: FilterMode.Linear, wrap: Wrap.Repeat, handle: 0, generation: 0 },
		block: reserved.value,
		material: added.value,
		values: new Array(SAO_UNIFORM_LENGTH),
		colors: new Array(1),
	};
}

function stopOnSettings(settings: ScalableAoSettings): void {
	console.log(`void3d: setScalableAo with ${settings.numSamples} samples, ` +
		`${settings.numSpiralTurns} turns and radius ${settings.sampleRadius}; samples are 1 to ` +
		"127, turns 1 to 15, the radius above 0, the intensity not negative, every value finite " +
		"and each fade ending past its start");
	unreachable;
}

// Turns the pass on with `settings`, or off with null, which releases the occlusion target.
export function setSettings(this pass: ScalableAoPass, settings: ScalableAoSettings | null): void {
	if (settings !== null) {
		if (!settings.valid()) { stopOnSettings(settings); }
	} else {
		pass.occlusion.close();
		pass.occlusion = RenderTarget.unallocated(PixelFormat.Rgba8, true);
	}
	pass.settings = settings;
}

export function isOn(this pass: ScalableAoPass): boolean {
	return pass.settings !== null;
}

// Makes the samplers again for a new GPU context; the target follows from resize and the noise
// texture uploads its kept pixels again when it is next bound.
export function adoptContext(this pass: ScalableAoPass): void {
	pass.pointSampler = Sampler.create(pass.pointSampler.filter, pass.pointSampler.wrap);
	pass.noiseSampler = Sampler.create(pass.noiseSampler.filter, pass.noiseSampler.wrap);
}

// The occlusion target for a `width` × `height` frame; allocates only when the size or the GPU
// context changed.
export function resize(this pass: ScalableAoPass, width: int32, height: int32): void {
	if (pass.settings === null) { return; }
	pass.occlusion.resize(width, height);
}

function noiseOf(pass: ScalableAoPass): Texture {
	const made: Texture | null = pass.noise;
	if (made !== null) { return made; }
	const uploaded: Result<Texture, TextureError> =
		Texture.fromPixels(saoNoisePixels(), SAO_NOISE_SIZE, SAO_NOISE_SIZE, true);
	if (!uploaded.ok) {
		console.log(`void3d: ScalableAoPass noise texture ${uploaded.error.toString()}`);
		unreachable;
	}
	pass.noise = uploaded.value;
	return uploaded.value;
}

// ScalableAO.apply: SAO over `depth` and `normal`, both the frame's size, into the occlusion
// target. resize ran for this frame's size first.
export function draw(
	this pass: ScalableAoPass,
	core: Renderer,
	depth: RenderTarget,
	normal: RenderTarget,
	camera: Camera3D,
	view: CameraView,
): void {
	const settings: ScalableAoSettings | null = pass.settings;
	if (settings === null) { return; }
	const context: DrawContext = core.context;
	const index: int32 = pass.material.index;
	context.materials[index].texture0 = depth.asTexture();
	context.materials[index].texture1 = normal.asTexture();
	context.materials[index].texture2 = noiseOf(pass).asView();
	context.materials[index].sampler0 = pass.pointSampler.asHandle();
	context.materials[index].sampler1 = pass.noiseSampler.asHandle();
	writeSaoBlock(settings, camera, view, depthZeroToOne(), pass.values);
	const written: Result<int32, UniformError> = writeUniforms(context, pass.block, pass.values);
	if (!written.ok) { unreachable; }
	pass.colors[0] = pass.occlusion.asColor(LoadAction.DontCare, NO_CLEAR);
	beginPass(pass.colors, NO_DEPTH);
	const drawn: Result<int32, RendererError> = drawScreen(core, pass.material, SAO_LAYOUT);
	if (!drawn.ok) { unreachable; }
	endPass();
}

export function close(this pass: ScalableAoPass, context: DrawContext, call: string): void {
	pass.occlusion.close();
	const noise: Texture | null = pass.noise;
	if (noise !== null) { noise.close(); }
	pass.noise = null;
	pass.pointSampler = pass.pointSampler.released();
	pass.noiseSampler = pass.noiseSampler.released();
	const released: Result<int32, HandleError> = releaseMaterial(context, pass.material);
	if (!released.ok) {
		console.log(`void3d: ${call} found the SAO material ${released.error.toString()}`);
		unreachable;
	}
}
