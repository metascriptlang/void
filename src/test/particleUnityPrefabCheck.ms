import { readFile } from "std/fs";
import { identity } from "../math/math3d";
import {
	ParticleEffect, ParticleSystemAsset, SimulationSpace, ShapeType, SubEmitterType,
	SubEmitterProperty, RenderMode, TriggerAction, CollisionType, InheritVelocityMode,
	NoiseQuality, TrailTextureMode, CustomDataMode,
} from "../particles/asset";
import { CurveMode, GradientKind, GradientMode, WeightedMode } from "../particles/curve";
import { ParticleSystem } from "../particles/system";
import { EffectInstance, playEffect, updateEffect } from "../particles/effect";
import { importUnityPrefab, PrefabError, PrefabErrorKind } from "../particles/unityPrefab";

// The fixtures are tests/unity/prefabs/*.prefab, exported by tests/unity/PrefabExport.cs from
// Unity 6000.6.6f1 with the values this file asserts.

const DIR: string = "tests/unity/prefabs/";
const TOL: float32 = 1e-5;

function near(a: float32, b: float32): boolean {
	const d: float32 = a - b;
	return d < TOL && d > -TOL;
}

function prefabText(name: string): string {
	const text = readFile(`${DIR}${name}.prefab`);
	if (!text.ok) { unreachable; }
	return text.value;
}

function loaded(name: string): ParticleEffect {
	const made = importUnityPrefab(prefabText(name));
	if (!made.ok) { unreachable; }
	return made.value;
}

function failureOf(text: string): PrefabError {
	const made = importUnityPrefab(text);
	if (made.ok) { unreachable; }
	return made.error;
}

function replaceFirst(text: string, old: string, replacement: string): string {
	if (text.indexOf(old) < 0) { unreachable; }
	return text.replace(old, replacement);
}

function nthIndexOf(text: string, needle: string, n: int32): int32 {
	let at: int32 = -1;
	for (let i = 0; i <= n; i++) {
		at = text.indexOf(needle, at + 1) as int32;
		if (at < 0) { unreachable; }
	}
	return at;
}

test "fountain: the main, emission and shape values set in Unity" {
	const effect = loaded("fountain");
	assert effect.systems.length == 1;
	const a: ParticleSystemAsset = effect.systems[0];
	assert near(a.main.duration, 4.0);
	assert a.main.loop && !a.main.prewarm && !a.main.playOnAwake && !a.main.useAutoRandomSeed;
	assert a.main.randomSeed == 777;
	assert a.main.startLifetime.mode == CurveMode.Constant && near(a.main.startLifetime.scalar, 2.0);
	assert a.main.startSpeed.mode == CurveMode.Constant && near(a.main.startSpeed.scalar, 6.0);
	assert !a.main.startSize3D && near(a.main.startSizeX.scalar, 0.2);
	assert a.main.startColor.mode == GradientKind.Color;
	assert near(a.main.startColor.maxColor.r, 1.0) && near(a.main.startColor.maxColor.g, 0.5);
	assert near(a.main.startColor.maxColor.b, 0.25) && near(a.main.startColor.maxColor.a, 0.75);
	assert near(a.main.gravityModifier.scalar, 1.0) && a.main.maxParticles == 500;
	assert a.main.simulationSpace == SimulationSpace.World;
	assert a.emission.enabled && near(a.emission.rateOverTime.scalar, 50.0);
	assert a.emission.bursts.length == 1;
	const burst = a.emission.bursts[0];
	assert near(burst.time, 0.5) && burst.cycleCount == 3 && near(burst.repeatInterval, 0.25);
	assert near(burst.probability, 0.5);
	assert burst.count.mode == CurveMode.TwoConstants;
	assert near(burst.count.minScalar, 20.0) && near(burst.count.scalar, 30.0);
	assert a.shape.enabled && a.shape.shapeType == ShapeType.Cone;
	assert near(a.shape.angle, 20.0) && near(a.shape.radius, 0.5) && near(a.shape.radiusThickness, 0.5);
	assert near(a.shape.arc, 270.0);
	assert near(a.shape.position.y, 0.1) && near(a.shape.rotation.x, -90.0);
	assert a.renderer.renderMode == RenderMode.Billboard;
	assert !a.velocityOverLifetime.enabled && !a.trails.enabled && !a.collision.enabled;
}

test "curves: constants, curves, gradients and the modules around them" {
	const a: ParticleSystemAsset = loaded("curves").systems[0];
	assert a.main.simulationSpace == SimulationSpace.Local;
	assert a.main.startLifetime.mode == CurveMode.TwoConstants;
	assert near(a.main.startLifetime.minScalar, 1.0) && near(a.main.startLifetime.scalar, 3.0);
	assert a.main.startSpeed.mode == CurveMode.Curve && near(a.main.startSpeed.scalar, 2.0);
	assert a.main.startSpeed.maxCurve.keys.length == 2;
	assert near(a.main.startSpeed.maxCurve.keys[1].time, 1.0) && near(a.main.startSpeed.maxCurve.keys[1].value, 1.0);
	// Radians in the file and in the asset: 0.5 and 1.5 as written through the API.
	assert a.main.startRotationZ.mode == CurveMode.TwoConstants;
	assert near(a.main.startRotationZ.minScalar, 0.5) && near(a.main.startRotationZ.scalar, 1.5);
	assert a.main.startColor.mode == GradientKind.TwoColors;
	assert near(a.main.startColor.minColor.r, 1.0) && near(a.main.startColor.maxColor.b, 1.0);
	assert near(a.main.startColor.maxColor.a, 0.5);
	assert a.main.gravityModifier.mode == CurveMode.Curve && near(a.main.gravityModifier.scalar, 0.5);
	assert near(a.main.gravityModifier.maxCurve.keys[0].value, 0.2);

	assert a.colorOverLifetime.enabled && a.colorOverLifetime.color.mode == GradientKind.Gradient;
	const g = a.colorOverLifetime.color.maxGradient;
	assert g.mode == GradientMode.Blend;
	assert g.colorKeys.length == 3 && g.alphaKeys.length == 3;
	assert near(g.colorKeys[0].color.r, 1.0) && near(g.colorKeys[1].color.g, 1.0) && near(g.colorKeys[2].color.b, 1.0);
	assert near(g.colorKeys[1].time, 32768.0 / 65535.0) && near(g.colorKeys[2].time, 1.0);
	assert near(g.alphaKeys[0].alpha, 0.0) && near(g.alphaKeys[1].alpha, 1.0) && near(g.alphaKeys[1].time, 16384.0 / 65535.0);

	assert a.sizeOverLifetime.enabled && a.sizeOverLifetime.x.mode == CurveMode.Curve;
	assert near(a.sizeOverLifetime.x.scalar, 3.0) && a.sizeOverLifetime.x.maxCurve.keys.length == 3;
	assert near(a.sizeOverLifetime.x.maxCurve.keys[0].outSlope, 2.0) && near(a.sizeOverLifetime.x.maxCurve.keys[2].inSlope, -1.0);
	assert a.sizeOverLifetime.x.maxCurve.keys[0].weightedMode == WeightedMode.None;
	assert a.rotationOverLifetime.enabled && near(a.rotationOverLifetime.z.minScalar, 0.5);
	assert near(a.rotationOverLifetime.z.scalar, 1.0);

	assert a.velocityOverLifetime.enabled && a.velocityOverLifetime.space == SimulationSpace.World;
	assert near(a.velocityOverLifetime.x.scalar, 1.0) && near(a.velocityOverLifetime.y.minScalar, 1.0);
	assert near(a.velocityOverLifetime.y.scalar, 2.0) && near(a.velocityOverLifetime.speedModifier.scalar, 0.5);
	assert near(a.velocityOverLifetime.radial.scalar, 0.25);
	assert a.forceOverLifetime.enabled && a.forceOverLifetime.randomized;
	assert near(a.forceOverLifetime.x.scalar, 0.5) && near(a.forceOverLifetime.y.scalar, -1.0);
	assert a.limitVelocityOverLifetime.enabled && near(a.limitVelocityOverLifetime.limit.scalar, 4.0);
	assert near(a.limitVelocityOverLifetime.dampen, 0.3) && near(a.limitVelocityOverLifetime.drag.scalar, 0.1);
	assert a.inheritVelocity.enabled && a.inheritVelocity.mode == InheritVelocityMode.Current;
	assert near(a.inheritVelocity.curve.scalar, 0.5);
	assert a.externalForces.enabled && near(a.externalForces.multiplier.scalar, 2.0);
	assert a.externalForces.influenceMask == 0xFFFFFFFF;
	assert a.colorBySpeed.enabled && near(a.colorBySpeed.range.min, 1.0) && near(a.colorBySpeed.range.max, 5.0);
	assert a.sizeBySpeed.enabled && near(a.sizeBySpeed.range.max, 8.0) && near(a.sizeBySpeed.x.scalar, 2.0);
	assert a.rotationBySpeed.enabled && near(a.rotationBySpeed.z.scalar, 1.5);
	assert a.noise.enabled && near(a.noise.strengthX.scalar, 2.0) && near(a.noise.frequency, 0.75);
	assert a.noise.octaveCount == 2 && a.noise.quality == NoiseQuality.Medium && !a.noise.damping;
	assert near(a.noise.scrollSpeed.scalar, 0.5) && near(a.noise.positionAmount.scalar, 0.8);
	assert a.textureSheetAnimation.enabled && a.textureSheetAnimation.numTilesX == 4;
	assert a.textureSheetAnimation.numTilesY == 2 && a.textureSheetAnimation.cycleCount == 2;
	assert a.lights.enabled && near(a.lights.ratio, 0.5) && a.lights.maxLights == 5;
	assert near(a.lights.intensity.scalar, 2.0) && near(a.lights.range.scalar, 3.0);
	assert a.customData.enabled && a.customData.first.mode == CustomDataMode.Vector;
	assert a.customData.first.vectorComponentCount == 2 && near(a.customData.first.x.scalar, 1.0);
	assert a.customData.first.y.mode == CurveMode.Curve && near(a.customData.first.y.scalar, 2.0);
	assert a.customData.second.mode == CustomDataMode.Disabled;
	assert a.renderer.renderMode == RenderMode.Stretch && near(a.renderer.velocityScale, 0.2);
	assert near(a.renderer.lengthScale, 3.0) && a.renderer.sortingOrder == 4;
}

test "subEmitters: hierarchy order and the sub-emitter links" {
	const effect = loaded("subEmitters");
	assert effect.systems.length == 4;
	assert near(effect.systems[1].main.startLifetime.scalar, 0.5);
	assert near(effect.systems[2].main.startSizeX.scalar, 0.4);
	assert near(effect.systems[3].main.startSizeX.scalar, 0.1);
	const parent = effect.systems[0].subEmitters;
	assert parent.enabled && parent.subEmitters.length == 2;
	assert parent.subEmitters[0].system == 1 && parent.subEmitters[0].subEmitterType == SubEmitterType.Birth;
	assert parent.subEmitters[0].properties == (0 as BitSet<SubEmitterProperty>).incl(SubEmitterProperty.InheritColor);
	assert near(parent.subEmitters[0].emitProbability, 1.0);
	assert parent.subEmitters[1].system == 2 && parent.subEmitters[1].subEmitterType == SubEmitterType.Death;
	assert parent.subEmitters[1].properties.has(SubEmitterProperty.InheritColor);
	assert parent.subEmitters[1].properties.has(SubEmitterProperty.InheritSize);
	assert parent.subEmitters[1].properties.size() == 2;
	assert near(parent.subEmitters[1].emitProbability, 0.5);
	const death = effect.systems[2].subEmitters;
	assert death.enabled && death.subEmitters.length == 1;
	assert death.subEmitters[0].system == 3 && death.subEmitters[0].subEmitterType == SubEmitterType.Collision;
	assert death.subEmitters[0].properties.isEmpty();
	assert !effect.systems[1].subEmitters.enabled && effect.systems[1].subEmitters.subEmitters.length == 0;
	assert effect.systems[2].emission.bursts.length == 1;
	assert near(effect.systems[2].emission.bursts[0].count.scalar, 8.0);
}

test "trailsCollision: trails, a collision plane and the trigger module" {
	const a: ParticleSystemAsset = loaded("trailsCollision").systems[0];
	assert a.trails.enabled && near(a.trails.ratio, 0.5) && near(a.trails.lifetime.scalar, 0.4);
	assert near(a.trails.minVertexDistance, 0.1) && a.trails.worldSpace && !a.trails.dieWithParticles;
	assert !a.trails.sizeAffectsWidth && !a.trails.inheritParticleColor;
	assert a.trails.textureMode == TrailTextureMode.Tile;
	assert a.trails.widthOverTrail.mode == CurveMode.Curve && a.trails.widthOverTrail.maxCurve.keys.length == 2;
	assert near(a.trails.widthOverTrail.maxCurve.keys[1].value, 0.0);
	assert a.trails.colorOverLifetime.maxGradient.colorKeys.length == 2;
	assert near(a.trails.colorOverLifetime.maxGradient.colorKeys[1].color.g, 0.92156863);
	assert near(a.trails.colorOverTrail.maxGradient.alphaKeys[1].alpha, 0.0);
	assert a.collision.enabled && a.collision.collisionType == CollisionType.Planes;
	assert a.collision.planes.length == 1;
	assert near(a.collision.planes[0].point.y, -2.0) && near(a.collision.planes[0].normal.y, 1.0);
	assert near(a.collision.planes[0].normal.x, 0.0) && near(a.collision.planes[0].normal.z, 0.0);
	assert near(a.collision.dampen.scalar, 0.2) && near(a.collision.bounce.scalar, 0.6);
	assert near(a.collision.lifetimeLoss.scalar, 0.1) && near(a.collision.minKillSpeed, 0.5);
	assert near(a.collision.maxKillSpeed, 50.0) && near(a.collision.radiusScale, 0.9);
	assert a.collision.sendCollisionMessages;
	assert a.trigger.enabled && a.trigger.inside == TriggerAction.Callback;
	assert a.trigger.enter == TriggerAction.Kill && a.trigger.exit == TriggerAction.Ignore;
	assert near(a.trigger.radiusScale, 0.5);
}

test "every fixture builds a ParticleSystem and the effect simulates" {
	const names: string[] = ["fountain", "curves", "subEmitters", "trailsCollision"];
	for (const name of names) {
		const effect = loaded(name);
		for (const asset of effect.systems) {
			assert ParticleSystem.create(asset, 1).ok;
		}
		const made = EffectInstance.create(effect, 12345);
		assert made.ok;
		let fx = made.value;
		playEffect(fx, identity());
		let seen: int32 = 0;
		for (let k = 0; k < 30; k++) {
			const done = updateEffect(fx, 1.0 / 30.0, identity());
			assert done.ok;
			if (done.value > seen) { seen = done.value; }
		}
		assert seen > 0;
	}
}

test "unknown enum values and missing fields are named errors" {
	const fountain: string = prefabText("fountain");
	const state = failureOf(replaceFirst(fountain, "minMaxState: 0", "minMaxState: 7"));
	assert state.kind == PrefabErrorKind.BadEnum;
	assert state.path.indexOf("minMaxState") >= 0 && state.path.startsWith("ParticleSystem[0]");
	assert state.detail == "7";
	assert failureOf(replaceFirst(fountain, "  type: 4\n", "  type: 21\n")).kind == PrefabErrorKind.BadEnum;
	assert failureOf(replaceFirst(fountain, "looping: 1", "looping: 2")).kind == PrefabErrorKind.BadNumber;
	assert failureOf(replaceFirst(fountain, "lengthInSec: 4", "lengthInSec: four")).kind == PrefabErrorKind.BadNumber;
	const missing = failureOf(replaceFirst(fountain, "  looping: 1\n", ""));
	assert missing.kind == PrefabErrorKind.MissingField && missing.path == "ParticleSystem[0].looping";
	assert failureOf(replaceFirst(fountain, "m_PreInfinity: 2", "m_PreInfinity: 0")).kind == PrefabErrorKind.Unsupported;
}

test "values the asset cannot hold are refused" {
	const fountain: string = prefabText("fountain");
	const version = failureOf(replaceFirst(fountain, "  serializedVersion: 8\n", "  serializedVersion: 7\n"));
	assert version.kind == PrefabErrorKind.UnsupportedVersion;
	assert failureOf(replaceFirst(fountain, "useUnscaledTime: 0", "useUnscaledTime: 1")).kind == PrefabErrorKind.Unsupported;
	assert failureOf(replaceFirst(fountain, "moveWithTransform: 1", "moveWithTransform: 2")).kind == PrefabErrorKind.Unsupported;
	assert importUnityPrefab(fountain).ok;
	const withBody: string = fountain + "--- !u!54 &1\nRigidbody:\n  m_Mass: 1\n";
	assert failureOf(withBody).kind == PrefabErrorKind.Unsupported;
	assert failureOf(fountain + "--- !u!1001 &2\nPrefabInstance:\n  m_Modification: {}\n").kind == PrefabErrorKind.Unsupported;
}

test "sub-emitter links name a missing or earlier system" {
	const text: string = prefabText("subEmitters");
	const marker: string = "emitter: {fileID: ";
	const at: int32 = text.indexOf(marker) as int32 + (marker.length as int32);
	const end: int32 = text.indexOf("}", at) as int32;
	const missing = failureOf(text.substring(0, at) + "42" + text.substring(end, text.length as int32));
	assert missing.kind == PrefabErrorKind.BadReference && missing.path.indexOf("subEmitters[0].emitter") >= 0;
	const idMarker: string = "!u!198 &";
	const idAt: int32 = text.indexOf(idMarker) as int32 + (idMarker.length as int32);
	const parentId: string = text.substring(idAt, text.indexOf("\n", idAt) as int32);
	const third: int32 = nthIndexOf(text, marker, 2) + (marker.length as int32);
	const thirdEnd: int32 = text.indexOf("}", third) as int32;
	const loop = failureOf(text.substring(0, third) + parentId + text.substring(thirdEnd, text.length as int32));
	assert loop.kind == PrefabErrorKind.SubEmitterOrder;
}

test "malformed text is a Syntax error" {
	const fountain: string = prefabText("fountain");
	assert failureOf("").kind == PrefabErrorKind.Syntax;
	assert failureOf("not a prefab\n").kind == PrefabErrorKind.Syntax;
	assert failureOf(replaceFirst(fountain, "ringBufferLoopRange: {x: 0, y: 1}", "ringBufferLoopRange: {x: 0, y: 1")).kind == PrefabErrorKind.Syntax;
	assert failureOf(replaceFirst(fountain, "  looping: 1\n", "      looping: 1\n")).kind == PrefabErrorKind.Syntax;
	assert failureOf(replaceFirst(fountain, "--- !u!198 &", "--- !u!x &")).kind == PrefabErrorKind.Syntax;
	const noSystem = failureOf("%YAML 1.1\n--- !u!1 &1\nGameObject:\n  m_Component: []\n");
	assert noSystem.kind == PrefabErrorKind.Syntax || noSystem.kind == PrefabErrorKind.NoParticleSystem;
}
