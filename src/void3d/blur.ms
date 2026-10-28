// Heaps' h3d.pass.Blur: a separable blur whose taps fall between texels, so the linear filter
// reads two texels per tap. docs/VOID3D.md "Ambient occlusion".

import { Program, ProgramKey } from "./gpu3d";
import { PixelFormat, LoadAction, endPass } from "../gpu/door";
import { FilterMode, Wrap } from "../gpu/state";
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

// Blur's radius, gain, linear and quality, defaulting as `new Blur()` does.
export struct BlurSettings {
	radius: float32;
	gain: float32;
	linear: float32;
	quality: float32;
}

export function defaults(this typeof BlurSettings): BlurSettings {
	return { radius: 1.0, gain: 1.0, linear: 0.0, quality: 1.0 };
}

// The most taps one side of the blur program reads, the centre one included.
export const BLUR_MAX_TAPS: int32 = 16;
// The blur program's block (post3d.ms BlurParams) at the screen slot: the step in UV and the
// weight count, then a vec4 per tap holding its weight and offset.
export const BLUR_UNIFORM_SLOT: int32 = 0;
export const BLUR_PIXEL: int32 = 0;
export const BLUR_TAPS: int32 = 4;
export const BLUR_UNIFORM_LENGTH: int32 = BLUR_TAPS + 4 * BLUR_MAX_TAPS;

// Tap i's weight and how far it sits from the centre, in pixels per tap index.
export struct BlurKernel {
	values: Vec<float32>;
	offsets: Vec<float32>;
}

function gauss(x: float64, s: float64): float64 {
	if (s <= 0.0) { return x == 0.0 ? 1.0 : 0.0; }
	const sq: float64 = s * s;
	const p: float64 = Math.pow(2.718281828459, -(x * x) / (2.0 * sq));
	return p / Math.sqrt(2.0 * Math.PI * sq);
}

function lerp(a: float64, b: float64, t: float64): float64 {
	return a + (b - a) * t;
}

// Blur.calcValues, in float64 as Heaps computes it.
export function blurKernel(settings: BlurSettings): BlurKernel {
	let values: Vec<float64> = [];
	let offsets: Vec<float64> = [];
	const radius: float64 = settings.radius;
	const quality: float64 = settings.quality;
	const qadj: float64 = (quality < 0.0 ? 0.0 : quality > 1.0 ? 1.0 : quality) * 0.7 + 0.3;
	const spread: float64 = radius - 1.0 > 1.0 ? radius - 1.0 : 1.0;
	const width: int32 = radius > 0.0 ? Math.ceil(spread * qadj / 2.0) as int32 : 0;
	const sigma: float64 = Math.sqrt(radius);
	let total: float64 = 0.0;
	for (let i = 0; i < width + 1; i++) {
		const i1: float64 = (i * 2) as float64;
		const i2: float64 = i == 0 ? 0.0 : (i * 2 - 1) as float64;
		const g1: float64 = gauss(i1, sigma);
		const g2: float64 = gauss(i2, sigma);
		const g: float64 = g1 + g2;
		values.push(g);
		offsets.push(i == 0 ? 0.0 : (g1 * i1 + g2 * i2) / (g * (i as float64) * Math.sqrt(qadj)));
		total += g;
		if (i > 0) { total += g; }
	}
	const least: float64 = values[0] * (0.01 / qadj);
	while (values.length > 2) {
		const last: float64 = values[values.length - 1];
		if (last > least) { break; }
		total -= last * 2.0;
		values.pop();
	}
	total /= settings.gain;
	for (let i = 0; i < values.length; i++) { values[i] = values[i] / total; }
	const linear: float64 = settings.linear;
	if (linear > 0.0) {
		const flat: float64 = settings.gain / ((values.length * 2 - 1) as float64);
		for (let i = 0; i < values.length; i++) {
			values[i] = lerp(values[i], flat, linear);
			const at: float64 = i as float64;
			const spaced: float64 = i == 0 ? 0.0 : (at * 2.0 - 0.5) / (at * qadj);
			offsets[i] = lerp(offsets[i], spaced, linear);
		}
	}
	let kernel: BlurKernel = { values: [], offsets: [] };
	for (let i = 0; i < values.length; i++) {
		kernel.values.push(values[i] as float32);
		kernel.offsets.push(offsets[i] as float32);
	}
	return kernel;
}

// Blur.getKernelSize.
export function blurKernelSize(settings: BlurSettings): int32 {
	if (settings.radius <= 0.0) { return 0; }
	return (blurKernel(settings).values.length as int32) * 2 - 1;
}

// Finite settings, a gain above 0 and a kernel the program holds; a radius of 0 copies.
export function valid(this settings: BlurSettings): boolean {
	return Number.isFinite(settings.radius) && settings.radius >= 0.0 &&
		Number.isFinite(settings.gain) && settings.gain > 0.0 &&
		Number.isFinite(settings.linear) && Number.isFinite(settings.quality) &&
		blurKernel(settings).values.length <= BLUR_MAX_TAPS;
}

const NO_CLEAR: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 0.0 };

export interface BlurPass {
	settings: BlurSettings;
	kernel: BlurKernel;
	temporary: RenderTarget;
	sampler: Sampler;
	block: UniformBlock;
	material: MaterialId;
	values: Vec<float32>;
	colors: Vec<ColorAttachment>;
}

function stopOnSettings(settings: BlurSettings): void {
	console.log(`void3d: a blur with radius ${settings.radius}, gain ${settings.gain} and ` +
		`quality ${settings.quality}; every value is finite, the radius not negative, the gain ` +
		`above 0 and the kernel at most ${BLUR_MAX_TAPS} weights`);
	unreachable;
}

// Reserves the block and adds the material to `context`, whose pool the caller checked fits
// BLUR_UNIFORM_LENGTH; no GPU object is made here.
export function reserve(
	this typeof BlurPass,
	context: DrawContext,
	settings: BlurSettings,
): BlurPass {
	if (!settings.valid()) { stopOnSettings(settings); }
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, BLUR_UNIFORM_SLOT, BLUR_UNIFORM_LENGTH);
	if (!reserved.ok) {
		console.log("void3d: BlurPass.reserve found no room for its checked block");
		unreachable;
	}
	const added: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.keyed(ProgramKey.of(Program.Blur), screenState(), Phase.Opaque),
		uniforms: reserved.value,
	});
	if (!added.ok) { unreachable; }
	return {
		settings: settings,
		kernel: blurKernel(settings),
		temporary: RenderTarget.unallocated(PixelFormat.Rgba8, true),
		sampler: { filter: FilterMode.Linear, wrap: Wrap.Clamp, handle: 0, generation: 0 },
		block: reserved.value,
		material: added.value,
		values: new Array(BLUR_UNIFORM_LENGTH),
		colors: new Array(1),
	};
}

export function setSettings(this pass: BlurPass, settings: BlurSettings): void {
	if (!settings.valid()) { stopOnSettings(settings); }
	pass.settings = settings;
	pass.kernel = blurKernel(settings);
}

export function adoptContext(this pass: BlurPass): void {
	pass.sampler = Sampler.create(pass.sampler.filter, pass.sampler.wrap);
}

// The block for one direction: `stepX`, `stepY` in UV, then each weight and its offset.
export function writeBlurBlock(
	kernel: BlurKernel,
	stepX: float32,
	stepY: float32,
	out: Span<float32>,
): void {
	const count: int32 = kernel.values.length as int32;
	out[BLUR_PIXEL] = stepX;
	out[BLUR_PIXEL + 1] = stepY;
	out[BLUR_PIXEL + 2] = count as float32;
	out[BLUR_PIXEL + 3] = 0.0;
	for (let i = 0; i < BLUR_MAX_TAPS; i++) {
		const at: int32 = BLUR_TAPS + i * 4;
		out[at] = i < count ? kernel.values[i] : 0.0;
		out[at + 1] = i < count ? kernel.offsets[i] : 0.0;
		out[at + 2] = 0.0;
		out[at + 3] = 0.0;
	}
}

function layoutOf(format: PixelFormat): TargetLayout {
	return {
		color0: format,
		color1: PixelFormat.None,
		color2: PixelFormat.None,
		color3: PixelFormat.None,
		depth: PixelFormat.None,
		sampleCount: 1,
	};
}

function blurInto(
	pass: BlurPass,
	core: Renderer,
	source: RenderTarget,
	target: RenderTarget,
	stepX: float32,
	stepY: float32,
): void {
	const context: DrawContext = core.context;
	context.materials[pass.material.index].texture0 = source.asTexture();
	context.materials[pass.material.index].sampler0 = pass.sampler.asHandle();
	writeBlurBlock(pass.kernel, stepX, stepY, pass.values);
	const written: Result<int32, UniformError> = writeUniforms(context, pass.block, pass.values);
	if (!written.ok) { unreachable; }
	pass.colors[0] = target.asColor(LoadAction.DontCare, NO_CLEAR);
	beginPass(pass.colors, NO_DEPTH);
	const drawn: Result<int32, RendererError> =
		drawScreen(core, pass.material, layoutOf(target.format));
	if (!drawn.ok) { unreachable; }
	endPass();
}

// Blur.apply with no output: `target` blurred across into a temporary of its size and format,
// then down back into itself. A radius of 0 leaves it as it is.
export function draw(this pass: BlurPass, core: Renderer, target: RenderTarget): void {
	if (pass.settings.radius <= 0.0) { return; }
	if (pass.temporary.format != target.format) {
		pass.temporary.close();
		pass.temporary = RenderTarget.unallocated(target.format, true);
	}
	pass.temporary.resize(target.width, target.height);
	blurInto(pass, core, target, pass.temporary, 1.0 / (target.width as float32), 0.0);
	blurInto(pass, core, pass.temporary, target, 0.0, 1.0 / (target.height as float32));
}

export function close(this pass: BlurPass, context: DrawContext, call: string): void {
	pass.temporary.close();
	pass.sampler = pass.sampler.released();
	const released: Result<int32, HandleError> = releaseMaterial(context, pass.material);
	if (!released.ok) {
		console.log(`void3d: ${call} found the blur material ${released.error.toString()}`);
		unreachable;
	}
}
