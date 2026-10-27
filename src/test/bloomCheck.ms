import { approx } from "./helpers";
import { Vec4 } from "../math/math3d";
import { Blend, RenderState } from "../gpu/state";
import { DrawContext } from "../void3d/draw";
import {
	BloomSettings,
	BloomCompositeMode,
	bloomMipCount,
	bloomMipWidth,
	bloomBlendFactor,
	writeThreshold,
	upsampleState,
} from "../void3d/bloom";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_HDR_UNIFORM_LENGTH,
	setBloom,
	closeForward,
} from "../void3d/forwardRenderer";
import { ToneMapPass } from "../void3d/toneMap";

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
	let out: Vec<float32> = new Array(4);
	const settings: BloomSettings =
		{ ...BloomSettings.natural(), threshold: 1.0, thresholdSoftness: 0.5 };
	writeThreshold(settings, out, 0);
	assert out[0] == 1.0 && out[1] == 0.5 && out[2] == 1.0 && approx(out[3], 0.49999);
	writeThreshold({ ...settings, thresholdSoftness: 3.0 }, out, 0);
	assert out[1] == 0.0 && out[2] == 2.0;
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
import { bitcastF32toU32 } from "../shader/std";
import {
	BLOOM_SOURCE_TEXEL, BLOOM_TARGET_TEXEL, BLOOM_BLEND, BLOOM_THRESHOLD, BLOOM_UNIFORM_LENGTH,
} from "../void3d/bloom";

function bloomByHand(
	settings: BloomSettings,
	source: int32,
	target: int32,
	blend: float32,
): Vec<float32> {
	let values: Vec<float32> = new Array(BLOOM_UNIFORM_LENGTH);
	writeThreshold(settings, values, BLOOM_THRESHOLD);
	values[BLOOM_SOURCE_TEXEL] = 1.0 / (source as float32);
	values[BLOOM_SOURCE_TEXEL + 1] = 1.0 / ((source * 2) as float32);
	values[BLOOM_TARGET_TEXEL] = 1.0 / (target as float32);
	values[BLOOM_TARGET_TEXEL + 1] = 1.0 / ((target * 2) as float32);
	values[BLOOM_BLEND] = blend;
	return values;
}

function bloomFromBlock(
	settings: BloomSettings,
	source: int32,
	target: int32,
	blend: float32,
): Vec<float32> {
	let pool: UniformPool = UniformPool.withCapacity(BLOOM_UNIFORM_LENGTH);
	for (let i = 0; i < BLOOM_UNIFORM_LENGTH; i++) { pool.values[i] = -7.0; }
	const reserved = reserveBlock<BloomParams>(pool, 0);
	if (!reserved.ok) { unreachable; }
	let threshold: Vec<float32> = new Array(4);
	writeThreshold(settings, threshold, 0);
	if (!writeBlock(pool, reserved.value, {
		bloomTexel: {
			x: 1.0 / (source as float32), y: 1.0 / ((source * 2) as float32),
			z: 1.0 / (target as float32), w: 1.0 / ((target * 2) as float32),
		},
		bloomBlend: { x: blend, y: 0.0, z: 0.0, w: 0.0 },
		bloomThreshold: { x: threshold[0], y: threshold[1], z: threshold[2], w: threshold[3] },
	}).ok) { unreachable; }
	return pool.values;
}

test "bloom's block comes out the way a mip pass writes it by hand, the lanes it leaves zero" {
	const soft: BloomSettings = { ...BloomSettings.natural(), threshold: 1.0, thresholdSoftness: 0.5 };
	for (const settings of [BloomSettings.natural(), soft]) {
		const hand: Vec<float32> = bloomByHand(settings, 64, 32, 0.375);
		const made: Vec<float32> = bloomFromBlock(settings, 64, 32, 0.375);
		assert hand.length == 12 && made.length == 12;
		for (let i = 0; i < 12; i++) {
			assert bitcastF32toU32(hand[i]) == bitcastF32toU32(made[i]);
		}
	}
}
