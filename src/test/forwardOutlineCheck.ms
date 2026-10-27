import { Vec4, identity } from "../math/math3d";
import {
	ForwardOutlineSettings, valid, outlineColor, fxaaCoverage, outlineWidthCoverage,
	OUTLINE_WIDTH_SAMPLES,
} from "../void3d/forwardOutline";
import { Program, ProgramKey, declares, uniformBlockLength } from "../void3d/gpu3d";

const CLEAR: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 0.0 };
const LIT: Vec4 = { x: 0.4, y: 0.2, z: 0.1, w: 0.5 };
const LINE: Vec4 = { x: 1.0, y: 0.5, z: 0.0, w: 0.5 };

// Independent RGB reference transcription of Heaps pass/FXAA.hx, including dot(lumA).
function reference(
	sample: (x: float32, y: float32) => float32,
	x: float32,
	y: float32,
): float32 {
	const nw: float32 = sample(x - 1.0, y - 1.0);
	const ne: float32 = sample(x + 1.0, y - 1.0);
	const sw: float32 = sample(x - 1.0, y + 1.0);
	const se: float32 = sample(x + 1.0, y + 1.0);
	const mid: float32 = sample(x, y);
	const luminance: float32 = 0.299 + 0.587 + 0.114;
	const lnw: float32 = nw * luminance;
	const lne: float32 = ne * luminance;
	const lsw: float32 = sw * luminance;
	const lse: float32 = se * luminance;
	const lm: float32 = mid * luminance;
	const lo: float32 = Math.min(lm, Math.min(Math.min(lnw, lne), Math.min(lsw, lse)));
	const hi: float32 = Math.max(lm, Math.max(Math.max(lnw, lne), Math.max(lsw, lse)));
	const dx: float32 = -((lnw + lne) - (lsw + lse));
	const dy: float32 = (lnw + lsw) - (lne + lse);
	const reduction: float32 =
		Math.max((lnw + lne + lsw + lse) * (0.25 / 128.0), (1.0 / 8.0) as float32);
	const r: float32 = (1.0 / (Math.min(Math.abs(dx), Math.abs(dy)) + reduction)) as float32;
	const ux: float32 = Math.min(8.0, Math.max(-8.0, dx * r));
	const uy: float32 = Math.min(8.0, Math.max(-8.0, dy * r));
	const a: float32 = 0.5 * (sample(x + ux * (-1.0 / 6.0), y + uy * (-1.0 / 6.0)) +
		sample(x + ux * (1.0 / 6.0), y + uy * (1.0 / 6.0)));
	const b: float32 = a * 0.5 + 0.25 * (
		sample(x - ux * 0.5, y - uy * 0.5) + sample(x + ux * 0.5, y + uy * 0.5)
	);
	const lb: float32 = b * luminance;
	return lb > lo && lb < hi ? b : a;
}

function diagonalTexel(x: int32, y: int32): float32 {
	return x >= y && x < y + 2 ? 1.0 : 0.0;
}

function cornerTexel(x: int32, y: int32): float32 {
	return (x >= 0 && x <= 1 && y >= 0) || (y >= 0 && y <= 1 && x >= 0) ? 1.0 : 0.0;
}

function bilinear(x: float32, y: float32, corner: boolean): float32 {
	const ix: int32 = Math.floor(x) as int32;
	const iy: int32 = Math.floor(y) as int32;
	const tx: float32 = x - (ix as float32);
	const ty: float32 = y - (iy as float32);
	const a: float32 = corner ? cornerTexel(ix, iy) : diagonalTexel(ix, iy);
	const b: float32 = corner ? cornerTexel(ix + 1, iy) : diagonalTexel(ix + 1, iy);
	const c: float32 = corner ? cornerTexel(ix, iy + 1) : diagonalTexel(ix, iy + 1);
	const d: float32 = corner ? cornerTexel(ix + 1, iy + 1) : diagonalTexel(ix + 1, iy + 1);
	return (a * (1.0 - tx) + b * tx) * (1.0 - ty) + (c * (1.0 - tx) + d * tx) * ty;
}

function diagonal(x: float32, y: float32): float32 { return bilinear(x, y, false); }
function corner(x: float32, y: float32): float32 { return bilinear(x, y, true); }

test "forwardOutline straight blend preserves disabled bytes and premultiplies coverage once" {
	assert outlineColor(LIT, LINE, 0.75, 0.0) == LIT;
	assert outlineColor(LIT, LINE, 0.0, 1.0) == CLEAR;
	const edge: Vec4 = outlineColor(LIT, LINE, 0.5, 1.0);
	const expected: Vec4 = { x: 0.25, y: 0.125, z: 0.0, w: 0.25 };
	assert edge == expected;
	const half: Vec4 = outlineColor(LIT, LINE, 0.5, 0.5);
	assert Math.abs(half.x - 0.325) < 0.00001;
	assert Math.abs(half.w - 0.375) < 0.00001;
	assert outlineColor(LIT, CLEAR, 1.0, 1.0) == CLEAR;
	const black: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 0.5 };
	assert outlineColor(LIT, black, 0.5, 1.0).w == 0.25;
}

test "forwardOutline FXAA coverage equals unchanged RGB reference on diagonal and corner masks" {
	let filtered: int32 = 0;
	for (let y = -3; y <= 4; y++) {
		for (let x = -3; x <= 4; x++) {
			const px: float32 = x as float32;
			const py: float32 = y as float32;
			const a: float32 = fxaaCoverage(diagonal, px, py);
			const b: float32 = fxaaCoverage(corner, px, py);
			assert Math.abs(a - reference(diagonal, px, py)) < 0.00001;
			assert Math.abs(b - reference(corner, px, py)) < 0.00001;
			assert a >= 0.0 && a <= 1.0 && b >= 0.0 && b <= 1.0;
			if (Math.abs(a - diagonal(px, py)) > 0.001) { filtered++; }
		}
	}
	// Control: bypassing the filter must not be equal on every mask pixel.
	assert filtered > 0;
}

test "forwardOutline settings reject nonfinite and contract violations" {
	const settings: ForwardOutlineSettings = ForwardOutlineSettings.defaults();
	assert settings.valid();
	assert !valid({ ...settings, pixelWidth: 0.0 });
	assert !valid({ ...settings, pixelWidth: 17.0 });
	assert !valid({ ...settings, depthThreshold: 0.0 });
	assert !valid({ ...settings, normalThreshold: 1.1 });
	assert !valid({ ...settings, pixelWidth: NaN as float32 });
	assert !valid({ ...settings, color: { x: 0.0, y: 0.0, z: 0.0, w: -1.0 } });
}

test "forwardOutline normal MRT occupies bit15 never skin bit14" {
	const normal: ProgramKey = ProgramKey.of(Program.Lit).withNormalMrt();
	assert normal.bits() == 32768;
	assert (normal.bits() & 16384) == 0;
	assert normal.withCutout().bits() == 32896;
	assert ProgramKey.of(Program.Lit).bits() == 0;
}

import {
	ForwardRenderer, ForwardError, FORWARD_UNIFORM_LENGTH, FORWARD_OUTLINE_UNIFORM_LENGTH,
	setOutlineBlend, setOutlineSettings, closeForward, prepareFrame,
} from "../void3d/forwardRenderer";
import {
	DrawContext, DrawItem, MaterialId, MaterialError, addMaterial, releaseMaterial, closeContext,
} from "../void3d/draw";
import { Material, Phase } from "../void3d/material";
import { RenderState, BlendMode, Compare } from "../gpu/state";
import { VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH, drawnIn, Preset, declares } from
	"../void3d/gpu3d";

test "forwardOutline disabled create keeps old budget and lazy zero path" {
	const context: DrawContext = DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH);
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, CLEAR);
	assert made.ok;
	if (made.ok) {
		const renderer: ForwardRenderer = made.value;
		assert renderer.outline === null && renderer.outlineBlend == 0.0;
		setOutlineBlend(renderer, 0.0);
		assert renderer.outline === null && !renderer.core.normalMrt;
		assert renderer.colorTarget.image == 0 && renderer.depthTarget.image == 0;
		closeForward(renderer);
		assert context.liveMaterials() == 0;
	}
	closeContext(context);
}

test "forwardOutline lazy holders reuse ranges and settings snapshot marks changed" {
	const context: DrawContext = DrawContext.withUniformCapacity(FORWARD_OUTLINE_UNIFORM_LENGTH);
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, CLEAR);
	assert made.ok;
	if (made.ok) {
		const renderer: ForwardRenderer = made.value;
		setOutlineBlend(renderer, 1.0);
		const pass = renderer.outline;
		assert pass !== null;
		if (pass !== null) {
			assert pass.depth.sampled && pass.normal.sampled && pass.mask.sampled;
			assert pass.depth.image == 0 && pass.linearSampler.handle == 0;
			const used: int32 = context.uniforms.used;
			setOutlineBlend(renderer, 0.5);
			setOutlineBlend(renderer, 0.0);
			setOutlineBlend(renderer, 1.0);
			assert context.uniforms.used == used && context.liveMaterials() == 5;
			let settings: ForwardOutlineSettings =
				{ ...ForwardOutlineSettings.defaults(), color: LINE };
			renderer.core.changed = false;
			setOutlineSettings(renderer, settings);
			settings.color.w = 0.0;
			assert renderer.outlineSettings.color.w == 0.5 && renderer.core.changed;
			closeForward(renderer);
			assert pass.lit.closed && pass.normal.closed && pass.depth.closed;
			assert pass.mask.closed && pass.width.closed && context.liveMaterials() == 0;
		}
	}
	// Returned uniform ranges can be reused by a second issuer; no GPU allocation needed.
	const again: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, CLEAR);
	assert again.ok;
	if (again.ok) {
		setOutlineBlend(again.value, 1.0);
		closeForward(again.value);
	}
	closeContext(context);
}

test "forwardOutline opaque variants preserve feature keys and sampled shader reflection" {
	const lit: ProgramKey = ProgramKey.of(Program.Lit);
	const mapped: ProgramKey = ProgramKey.of(Program.LitTextured).withNormalMap().withEmissive();
	for (const source of [lit, lit.withCutout(), mapped]) {
		const drawn = drawnIn(source, Preset.Core, false, true);
		assert drawn.ok;
		if (drawn.ok) {
			assert drawn.value.normalMrt && declares(drawn.value);
			assert drawn.value.normalMap == source.normalMap;
			assert drawn.value.cutout == source.cutout && drawn.value.emissive == source.emissive;
		}
	}
	assert !drawnIn(ProgramKey.of(Program.Particle), Preset.Core, false, true).ok;
	assert !drawnIn(ProgramKey.of(Program.Lit), Preset.PixelArt, false, true).ok;
}

function phaseRefusal(pass: RenderState, phase: Phase): ForwardError | null {
	const context: DrawContext = DrawContext.withUniformCapacity(FORWARD_OUTLINE_UNIFORM_LENGTH);
	const made = ForwardRenderer.create(context, CLEAR);
	if (!made.ok) { unreachable; }
	const renderer: ForwardRenderer = made.value;
	setOutlineBlend(renderer, 1.0);
	const added: Result<MaterialId, MaterialError> =
		addMaterial(context, Material.plain(Program.Lit, pass, phase));
	if (!added.ok) { unreachable; }
	const items: Vec<DrawItem> = [{
		mesh: { store: 0, index: 0, generation: 0 }, material: added.value,
		world: identity(),
	}];
	const camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	const lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
	const result = prepareFrame(renderer, items, camera, lights, 64, 64);
	assertNoGpu(renderer);
	closeForward(renderer);
	const released = releaseMaterial(context, added.value);
	if (!released.ok) { unreachable; }
	closeContext(context);
	return result.ok ? null : result.error;
}

function assertNoGpu(renderer: ForwardRenderer): void {
	if (renderer.colorTarget.image != 0 || renderer.core.generation != 0) { unreachable; }
}

test "forwardOutline unsafe phase contracts refuse before any frame GPU writes" {
	const state: RenderState = RenderState.defaults();
	assert phaseRefusal(state.withBlendMode(BlendMode.Alpha), Phase.Opaque) ==
		ForwardError.OutlineBlendedOpaque;
	assert phaseRefusal(state.withDepth(false, Compare.Less), Phase.Opaque) ==
		ForwardError.OutlineOpaqueDepth;
	assert phaseRefusal(state.withDepth(true, Compare.Always), Phase.Opaque) ==
		ForwardError.OutlineOpaqueDepth;
	assert phaseRefusal(state, Phase.Alpha) == ForwardError.OutlineTranslucentDepthWrite;
}

function widthSeed(x: float32, _y: float32): float32 {
	const left: int32 = Math.floor(x) as int32;
	const fraction: float32 = x - (left as float32);
	const a: float32 = left == 0 || left == 1 ? 1.0 : 0.0;
	const b: float32 = left + 1 == 0 || left + 1 == 1 ? 1.0 : 0.0;
	return a + (b - a) * fraction;
}

test "forwardOutline Heaps48circle RGB width operator and affine complement" {
	assert OUTLINE_WIDTH_SAMPLES == 48;
	const widths: Vec<float32> = [1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 8.0, 16.0];
	for (let i = 0; i < widths.length; i++) {
		let mass: float32 = 0.0;
		for (let x = -20; x <= 20; x++) {
			const coverage: float32 = outlineWidthCoverage(widthSeed, x as float32, 0.0, widths[i]);
			assert coverage >= 0.0 && coverage <= 1.0;
			mass += coverage;
			if (widths[i] == 2.0) { assert coverage == widthSeed(x as float32, 0.0); }
		}
		assert Math.abs(mass - widths[i]) < 0.0001;
	}
	assert outlineWidthCoverage((x, y) => 0.0, 0.0, 0.0, 16.0) == 0.0;
	assert outlineWidthCoverage((x, y) => 1.0, 0.0, 0.0, 1.0) == 1.0;
}

test "forwardOutline width screen reflection has own four-float block" {
	const key: ProgramKey = ProgramKey.of(Program.OutlineWidth);
	assert declares(key);
	assert uniformBlockLength(key, 0) == 4;
	assert uniformBlockLength(key, 6) == 0;
}

test "forwardOutline RGBA8 partial coverage interval rejects old four-pixel width3" {
	const alpha: float32 = 0.5;
	const coverage: float32 = 0.5;
	const maskLow: int32 = Math.ceil(coverage*255.0-1.0) as int32;
	const maskHigh: int32 = Math.floor(coverage*255.0+1.0) as int32;
	const partialLow: int32 = Math.ceil(alpha*(maskLow as float32)-1.0) as int32;
	const partialHigh: int32 = Math.floor(alpha*(maskHigh as float32)+1.0) as int32;
	const fullLow: int32 = Math.ceil(alpha*255.0-1.0) as int32;
	const fullHigh: int32 = Math.floor(alpha*255.0+1.0) as int32;
	const low: int32 = 2*fullLow+2*partialLow;
	const high: int32 = 2*fullHigh+2*partialHigh;
	assert low == 380 && high == 386;
	assert 508 > high;
	assert 380 >= low && 380 <= high;
	assert fullLow == 127 && fullHigh == 128;
}

import { ForwardOutlinePass, FORWARD_OUTLINE_PASS_UNIFORM_LENGTH } from "../void3d/forwardOutline";
import { sameLanes } from "./helpers";

const UNWRITTEN: float32 = -7.0;

function outlineLanes(
	settings: ForwardOutlineSettings,
	blend: float32,
	zeroToOne: boolean,
): Vec<float32> {
	const context: DrawContext =
		DrawContext.withUniformCapacity(FORWARD_OUTLINE_PASS_UNIFORM_LENGTH);
	for (let i = 0; i < FORWARD_OUTLINE_PASS_UNIFORM_LENGTH; i++) {
		context.uniforms.values[i] = UNWRITTEN;
	}
	const pass: ForwardOutlinePass = ForwardOutlinePass.reserve(context);
	pass.writeSettings(context, settings, blend, zeroToOne);
	return context.uniforms.values;
}

test "forwardOutline writes the mask, mix and width blocks lane for lane, every lane written" {
	const color: Vec4 = { x: 0.3, y: 0.6, z: 0.9, w: 0.5 };
	const narrow: ForwardOutlineSettings =
		{ color: color, pixelWidth: 1.0, depthThreshold: 0.002, normalThreshold: 0.8 };
	assert sameLanes(outlineLanes(narrow, 0.75, true), [
		2, 0.002, 0.8, 1, 0, 0.75, 0, 0,
		0.15, 0.3, 0.45, 0.5, 0.75, 0, 0, 0,
		0.5, 1, 0, 0,
	]);
	assert sameLanes(outlineLanes({ ...narrow, pixelWidth: 2.0 }, 0.75, false), [
		2, 0.002, 0.8, 2, -1, 0.75, 0, 0,
		0.15, 0.3, 0.45, 0.5, 0.75, 0, 0, 0,
		0, 0, 0, 0,
	]);
	assert sameLanes(outlineLanes({ ...narrow, pixelWidth: 3.5 }, 0.0, true), [
		2, 0.002, 0.8, 1, 0, 0, 0, 0,
		0.15, 0.3, 0.45, 0.5, 0, 0, 0, 0,
		0.75, 0, 0, 0,
	]);
}
