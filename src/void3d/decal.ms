// Heaps' DecalOverlay (h3d/shader/pbr/VolumeDecal.hx:68-128) as a material of Program.Decal: its
// params and constants, written into the decal's block, and the pass a decal phase draws it with.

import { RenderState, BlendMode, Compare, Face } from "../gpu/state";
import {
	Program, DECAL_UNIFORM_LENGTH, DECAL_COLOR, DECAL_FADE_START, DECAL_FADE_END, DECAL_FADE_POWER,
	DECAL_EMISSIVE, DECAL_CENTERED, DECAL_GAMMA_CORRECT, DECAL_AUTO_ALPHA, DECAL_TONE_MAPPED,
	DECAL_NORMAL_FADE_START, DECAL_NORMAL_FADE_END, DECAL_NORMAL_FADE,
} from "./gpu3d";
import { Material, Phase } from "./material";
import { Rgba } from "./meshData";

export struct DecalOverlay {
	color: Rgba;
	fadeStart: float32;
	fadeEnd: float32;
	fadePower: float32;
	emissive: float32;
	centered: boolean;
	gammaCorrect: boolean;
	autoAlpha: boolean;
	normalFade: boolean;
	normalFadeStart: float32;
	normalFadeEnd: float32;
}

// PbrMaterial's BeforeTonemappingDecal and AfterTonemappingDecal modes (PbrMaterial.hx:245-256):
// over the lit colour and through the tone map with it, or over the tone-mapped colour as is.
// The material's phase and the block's tone-map flag both follow it.
export enum DecalPass {
	BeforeToneMap,
	AfterToneMap,
}

export enum DecalError {
	// The fade divides by fadeEnd - fadeStart.
	FadeRange,
	// The normal fade divides by normalFadeEnd - normalFadeStart.
	NormalFadeRange,
}

export function defaults(this typeof DecalOverlay): DecalOverlay {
	return {
		color: { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 },
		fadeStart: 0.0, fadeEnd: 1.0, fadePower: 1.0, emissive: 0.0,
		centered: true, gammaCorrect: false, autoAlpha: true,
		normalFade: false, normalFadeStart: 0.0, normalFadeEnd: 1.0,
	};
}

function flag(on: boolean): float32 {
	return on ? 1.0 : 0.0;
}

export function decalBlock(
	overlay: DecalOverlay,
	pass: DecalPass,
): Result<Vec<float32>, DecalError> {
	if (!(overlay.fadeEnd > overlay.fadeStart)) { return Result.err(DecalError.FadeRange); }
	if (overlay.normalFade && !(overlay.normalFadeEnd > overlay.normalFadeStart)) {
		return Result.err(DecalError.NormalFadeRange);
	}
	let block: Vec<float32> = new Array(DECAL_UNIFORM_LENGTH);
	block[DECAL_COLOR] = overlay.color.red;
	block[DECAL_COLOR + 1] = overlay.color.green;
	block[DECAL_COLOR + 2] = overlay.color.blue;
	block[DECAL_COLOR + 3] = overlay.color.alpha;
	block[DECAL_FADE_START] = overlay.fadeStart;
	block[DECAL_FADE_END] = overlay.fadeEnd;
	block[DECAL_FADE_POWER] = overlay.fadePower;
	block[DECAL_EMISSIVE] = overlay.emissive;
	block[DECAL_CENTERED] = flag(overlay.centered);
	block[DECAL_GAMMA_CORRECT] = flag(overlay.gammaCorrect);
	block[DECAL_AUTO_ALPHA] = flag(overlay.autoAlpha);
	block[DECAL_TONE_MAPPED] = flag(pass == DecalPass.BeforeToneMap);
	block[DECAL_NORMAL_FADE_START] = overlay.normalFadeStart;
	block[DECAL_NORMAL_FADE_END] = overlay.normalFadeEnd;
	block[DECAL_NORMAL_FADE] = flag(overlay.normalFade);
	return Result.ok(block);
}

// Blended over the colour of `pass` with no depth, its box's back faces drawn so a camera inside
// the box still sees the decal.
export function decal(this typeof Material, pass: DecalPass): Material {
	const state: RenderState = RenderState.defaults().withDepth(false, Compare.Always)
		.withBlendMode(BlendMode.Alpha).withCulling(Face.Front);
	const phase: Phase = pass == DecalPass.BeforeToneMap ? Phase.Decal : Phase.DecalAfterToneMap;
	return Material.plain(Program.Decal, state, phase);
}
