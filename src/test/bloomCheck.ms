import { approx } from "./helpers";
import { bitcastF32toU32, Vec4f } from "../shader/std";
import { Vec4 } from "../math/math3d";
import { Blend, RenderState } from "../gpu/state";
import { DrawContext } from "../void3d/draw";
import {
	BloomSettings,
	BloomCompositeMode,
	bloomMipCount,
	bloomMipWidth,
	bloomBlendFactor,
	thresholdOf,
	upsampleState,
} from "../void3d/bloom";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_HDR_UNIFORM_LENGTH,
	setBloom,
	closeForward,
} from "../void3d/forwardRenderer";
import {
	ToneMapPass, TONE_MAP_UNIFORM_SLOT, TONE_MAP_UNIFORM_LENGTH, TONE_MAP_EXPOSURE, TONE_MAP_MODE,
} from "../void3d/toneMap";
import { ToneMode } from "../void3d/renderer";
import { ToneMapParams } from "../void3d/post3d";

// Bevy 157e1ce6 bevy_post_process/src/bloom, evaluated apart from void3d.
test "bloom's mip chain is Bevy's: ilog2 of the dimension less one, mip 0 at that height" {
	assert bloomMipCount(512) == 8;
	assert bloomMipCount(256) == 7;
	assert bloomMipCount(511) == 7;
	assert bloomMipCount(4) == 1;
	assert bloomMipWidth(1280, 720, 512) == 910;
	assert bloomMipWidth(1, 1000, 512) == 1;
}

test "bloom's blend factors are compute_blend_factor's, energy conserving and additive" {
	const natural: BloomSettings = BloomSettings.natural();
	assert natural.compositeMode == BloomCompositeMode.EnergyConserving;
	assert approx(bloomBlendFactor(natural, 0.0, 7.0), 0.15);
	assert approx(bloomBlendFactor(natural, 7.0, 7.0), 0.745);
	assert approx(bloomBlendFactor(natural, 3.0, 7.0), 0.744992);
	const additive: BloomSettings = { ...natural, compositeMode: BloomCompositeMode.Additive };
	assert approx(bloomBlendFactor(additive, 7.0, 7.0), 0.85);
	assert approx(bloomBlendFactor(additive, 0.0, 7.0), 0.15);
}

test "the soft threshold's precomputations are Bevy's, the softness clamped to 0..1" {
	const settings: BloomSettings =
		{ ...BloomSettings.natural(), threshold: 1.0, thresholdSoftness: 0.5 };
	const soft: Vec4f = thresholdOf(settings);
	assert soft.x == 1.0 && soft.y == 0.5 && soft.z == 1.0 && approx(soft.w, 0.49999);
	const clamped: Vec4f = thresholdOf({ ...settings, thresholdSoftness: 3.0 });
	assert clamped.y == 0.0 && clamped.z == 2.0;
}

test "the upsample blends colour by its alpha and leaves the target's alpha alone" {
	const conserving: RenderState = upsampleState(BloomCompositeMode.EnergyConserving);
	assert conserving.blendSource == Blend.One;
	assert conserving.blendDestination == Blend.OneMinusSourceAlpha;
	assert conserving.blendAlphaSource == Blend.Zero;
	assert conserving.blendAlphaDestination == Blend.One;
	const additive: RenderState = upsampleState(BloomCompositeMode.Additive);
	assert additive.blendSource == Blend.One && additive.blendDestination == Blend.One;
	assert additive.blendAlphaSource == Blend.Zero && additive.blendAlphaDestination == Blend.One;
}

test "an HDR preset reserves its bloom off, and setBloom turns it on and off" {
	let context: DrawContext = DrawContext.withUniformCapacity(FORWARD_HDR_UNIFORM_LENGTH);
	const background: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
	const created: Result<ForwardRenderer, ForwardError> =
		ForwardRenderer.createHdrWhere(context, background, true);
	assert created.ok;
	if (created.ok) {
		let forward: ForwardRenderer = created.value;
		const pass: ToneMapPass | null = forward.toneMap;
		assert pass !== null;
		if (pass !== null) {
			assert !pass.bloom.isOn();
			forward.core.changed = false;
			const additive: BloomSettings =
				{ ...BloomSettings.natural(), compositeMode: BloomCompositeMode.Additive };
			setBloom(forward, additive);
			assert pass.bloom.isOn() && forward.core.changed;
			const up: RenderState = context.materials[pass.bloom.up.index].pass;
			assert up.blendDestination == Blend.One;
			setBloom(forward, null);
			assert !pass.bloom.isOn() && (pass.bloom.mips.length as int32) == 0;
		}
		closeForward(forward);
		assert context.liveMaterials() == 0;
	}
}

import { BloomParams } from "../void3d/post3d";
import { UniformPool, reserveBlock, writeBlock } from "../void3d/uniformPool";
import { uniformSize } from "../shader/uniform";
import { BLOOM_UNIFORM_LENGTH, BLOOM_PASS_UNIFORM_LENGTH, paramsOf } from "../void3d/bloom";

function sameLanes(made: Vec<float32>, expected: float32[]): boolean {
	if (made.length != expected.length) { return false; }
	for (let i = 0; i < expected.length; i++) {
		if (bitcastF32toU32(made[i]) != bitcastF32toU32(expected[i])) { return false; }
	}
	return true;
}

test "bloom's block is its params struct's floats, three to a pass" {
	assert BLOOM_UNIFORM_LENGTH == uniformSize<BloomParams>() / 4;
	assert BLOOM_PASS_UNIFORM_LENGTH == 3 * BLOOM_UNIFORM_LENGTH;
}

test "bloom writes one texel of the source, one of the target, the blend and the threshold, every lane written" {
	let pool: UniformPool = UniformPool.withCapacity(BLOOM_UNIFORM_LENGTH);
	for (let i = 0; i < BLOOM_UNIFORM_LENGTH; i++) { pool.values[i] = -7.0; }
	const reserved = reserveBlock<BloomParams>(pool, 0);
	assert reserved.ok;
	const settings: BloomSettings = { ...BloomSettings.natural(), threshold: 1.0, thresholdSoftness: 0.5 };
	const threshold: Vec4f = thresholdOf(settings);
	assert writeBlock(pool, reserved.value, paramsOf(64, 128, 32, 16, 0.375, threshold)).ok;
	assert approx(pool.values[11], 0.49999);
	pool.values[11] = threshold.w;
	assert sameLanes(pool.values, [
		0.015625, 0.0078125, 0.03125, 0.0625,
		0.375, 0, 0, 0,
		1, 0.5, 1, threshold.w,
	]);
}

test "the tone map block comes out the way prepare writes it by hand, the lanes it leaves zero" {
	for (const mode of [ToneMode.Linear, ToneMode.Reinhard, ToneMode.Filmic, ToneMode.Neutral]) {
		let hand: Vec<float32> = new Array(TONE_MAP_UNIFORM_LENGTH);
		hand[TONE_MAP_EXPOSURE] = 2.5;
		hand[TONE_MAP_MODE] = mode as float32;
		let pool: UniformPool = UniformPool.withCapacity(TONE_MAP_UNIFORM_LENGTH);
		for (let i = 0; i < TONE_MAP_UNIFORM_LENGTH; i++) { pool.values[i] = -7.0; }
		const reserved = reserveBlock<ToneMapParams>(pool, TONE_MAP_UNIFORM_SLOT);
		assert reserved.ok;
		assert writeBlock(pool, reserved.value, { toneMap: { x: 2.5, y: mode as float32, z: 0.0, w: 0.0 } }).ok;
		assert hand.length == 4 && pool.values.length == 4;
		for (let i = 0; i < 4; i++) {
			assert bitcastF32toU32(hand[i]) == bitcastF32toU32(pool.values[i]);
		}
	}
}
