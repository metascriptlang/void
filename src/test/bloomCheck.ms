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
