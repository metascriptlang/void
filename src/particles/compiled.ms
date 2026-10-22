// The asset's animatable values compiled once at create, so a step evaluates segments and never
// re-validates keys (docs/PARTICLES.md: Heaps' split of authored state from the simulation).

import { MinMaxCurve, CompiledMinMaxCurve, CurveError } from "./curve";
import { ParticleSystemAsset } from "./asset";

export struct CompiledCurves {
	startDelay: CompiledMinMaxCurve;
	startLifetime: CompiledMinMaxCurve;
	startSpeed: CompiledMinMaxCurve;
	startSizeX: CompiledMinMaxCurve;
	startSizeY: CompiledMinMaxCurve;
	startSizeZ: CompiledMinMaxCurve;
	startRotationX: CompiledMinMaxCurve;
	startRotationY: CompiledMinMaxCurve;
	startRotationZ: CompiledMinMaxCurve;
	gravityModifier: CompiledMinMaxCurve;
	rateOverTime: CompiledMinMaxCurve;
	rateOverDistance: CompiledMinMaxCurve;
	burstCounts: Vec<CompiledMinMaxCurve>;
	arcSpeed: CompiledMinMaxCurve;
	radiusSpeed: CompiledMinMaxCurve;
	velocityX: CompiledMinMaxCurve;
	velocityY: CompiledMinMaxCurve;
	velocityZ: CompiledMinMaxCurve;
	orbitalX: CompiledMinMaxCurve;
	orbitalY: CompiledMinMaxCurve;
	orbitalZ: CompiledMinMaxCurve;
	orbitalOffsetX: CompiledMinMaxCurve;
	orbitalOffsetY: CompiledMinMaxCurve;
	orbitalOffsetZ: CompiledMinMaxCurve;
	radial: CompiledMinMaxCurve;
	speedModifier: CompiledMinMaxCurve;
	limit: CompiledMinMaxCurve;
	limitX: CompiledMinMaxCurve;
	limitY: CompiledMinMaxCurve;
	limitZ: CompiledMinMaxCurve;
	drag: CompiledMinMaxCurve;
	inheritVelocity: CompiledMinMaxCurve;
	lifetimeByEmitterSpeed: CompiledMinMaxCurve;
	forceX: CompiledMinMaxCurve;
	forceY: CompiledMinMaxCurve;
	forceZ: CompiledMinMaxCurve;
	externalMultiplier: CompiledMinMaxCurve;
	sizeX: CompiledMinMaxCurve;
	sizeY: CompiledMinMaxCurve;
	sizeZ: CompiledMinMaxCurve;
	sizeBySpeedX: CompiledMinMaxCurve;
	sizeBySpeedY: CompiledMinMaxCurve;
	sizeBySpeedZ: CompiledMinMaxCurve;
	rotationX: CompiledMinMaxCurve;
	rotationY: CompiledMinMaxCurve;
	rotationZ: CompiledMinMaxCurve;
	rotationBySpeedX: CompiledMinMaxCurve;
	rotationBySpeedY: CompiledMinMaxCurve;
	rotationBySpeedZ: CompiledMinMaxCurve;
	noiseStrengthX: CompiledMinMaxCurve;
	noiseStrengthY: CompiledMinMaxCurve;
	noiseStrengthZ: CompiledMinMaxCurve;
	noiseScroll: CompiledMinMaxCurve;
	noiseRemapX: CompiledMinMaxCurve;
	noiseRemapY: CompiledMinMaxCurve;
	noiseRemapZ: CompiledMinMaxCurve;
	noisePosition: CompiledMinMaxCurve;
	noiseRotation: CompiledMinMaxCurve;
	noiseSize: CompiledMinMaxCurve;
	collisionDampen: CompiledMinMaxCurve;
	collisionBounce: CompiledMinMaxCurve;
	collisionLifetimeLoss: CompiledMinMaxCurve;
	frameOverTime: CompiledMinMaxCurve;
	startFrame: CompiledMinMaxCurve;
	lightRange: CompiledMinMaxCurve;
	trailLifetime: CompiledMinMaxCurve;
	trailWidth: CompiledMinMaxCurve;
	lightIntensity: CompiledMinMaxCurve;
	custom1X: CompiledMinMaxCurve;
	custom1Y: CompiledMinMaxCurve;
	custom1Z: CompiledMinMaxCurve;
	custom1W: CompiledMinMaxCurve;
	custom2X: CompiledMinMaxCurve;
	custom2Y: CompiledMinMaxCurve;
	custom2Z: CompiledMinMaxCurve;
	custom2W: CompiledMinMaxCurve;
}

function c(value: MinMaxCurve): Result<CompiledMinMaxCurve, CurveError> {
	return value.compile();
}

export function compileCurves(asset: ParticleSystemAsset): Result<CompiledCurves, CurveError> {
	const m = asset.main;
	const v = asset.velocityOverLifetime;
	const l = asset.limitVelocityOverLifetime;
	const n = asset.noise;
	const sheet = asset.textureSheetAnimation;
	const cd = asset.customData;
	let bursts: Vec<CompiledMinMaxCurve> = [];
	for (const burst of asset.emission.bursts) { bursts.push(try c(burst.count)); }
	return Result.ok({
		startDelay: try c(m.startDelay),
		startLifetime: try c(m.startLifetime),
		startSpeed: try c(m.startSpeed),
		startSizeX: try c(m.startSizeX),
		startSizeY: try c(m.startSizeY),
		startSizeZ: try c(m.startSizeZ),
		startRotationX: try c(m.startRotationX),
		startRotationY: try c(m.startRotationY),
		startRotationZ: try c(m.startRotationZ),
		gravityModifier: try c(m.gravityModifier),
		rateOverTime: try c(asset.emission.rateOverTime),
		rateOverDistance: try c(asset.emission.rateOverDistance),
		burstCounts: bursts,
		arcSpeed: try c(asset.shape.arcSpeed),
		radiusSpeed: try c(asset.shape.radiusSpeed),
		velocityX: try c(v.x),
		velocityY: try c(v.y),
		velocityZ: try c(v.z),
		orbitalX: try c(v.orbitalX),
		orbitalY: try c(v.orbitalY),
		orbitalZ: try c(v.orbitalZ),
		orbitalOffsetX: try c(v.orbitalOffsetX),
		orbitalOffsetY: try c(v.orbitalOffsetY),
		orbitalOffsetZ: try c(v.orbitalOffsetZ),
		radial: try c(v.radial),
		speedModifier: try c(v.speedModifier),
		limit: try c(l.limit),
		limitX: try c(l.limitX),
		limitY: try c(l.limitY),
		limitZ: try c(l.limitZ),
		drag: try c(l.drag),
		inheritVelocity: try c(asset.inheritVelocity.curve),
		lifetimeByEmitterSpeed: try c(asset.lifetimeByEmitterSpeed.curve),
		forceX: try c(asset.forceOverLifetime.x),
		forceY: try c(asset.forceOverLifetime.y),
		forceZ: try c(asset.forceOverLifetime.z),
		externalMultiplier: try c(asset.externalForces.multiplier),
		sizeX: try c(asset.sizeOverLifetime.x),
		sizeY: try c(asset.sizeOverLifetime.y),
		sizeZ: try c(asset.sizeOverLifetime.z),
		sizeBySpeedX: try c(asset.sizeBySpeed.x),
		sizeBySpeedY: try c(asset.sizeBySpeed.y),
		sizeBySpeedZ: try c(asset.sizeBySpeed.z),
		rotationX: try c(asset.rotationOverLifetime.x),
		rotationY: try c(asset.rotationOverLifetime.y),
		rotationZ: try c(asset.rotationOverLifetime.z),
		rotationBySpeedX: try c(asset.rotationBySpeed.x),
		rotationBySpeedY: try c(asset.rotationBySpeed.y),
		rotationBySpeedZ: try c(asset.rotationBySpeed.z),
		noiseStrengthX: try c(n.strengthX),
		noiseStrengthY: try c(n.strengthY),
		noiseStrengthZ: try c(n.strengthZ),
		noiseScroll: try c(n.scrollSpeed),
		noiseRemapX: try c(n.remapX),
		noiseRemapY: try c(n.remapY),
		noiseRemapZ: try c(n.remapZ),
		noisePosition: try c(n.positionAmount),
		noiseRotation: try c(n.rotationAmount),
		noiseSize: try c(n.sizeAmount),
		collisionDampen: try c(asset.collision.dampen),
		collisionBounce: try c(asset.collision.bounce),
		collisionLifetimeLoss: try c(asset.collision.lifetimeLoss),
		frameOverTime: try c(sheet.frameOverTime),
		startFrame: try c(sheet.startFrame),
		lightRange: try c(asset.lights.range),
		trailLifetime: try c(asset.trails.lifetime),
		trailWidth: try c(asset.trails.widthOverTrail),
		lightIntensity: try c(asset.lights.intensity),
		custom1X: try c(cd.first.x),
		custom1Y: try c(cd.first.y),
		custom1Z: try c(cd.first.z),
		custom1W: try c(cd.first.w),
		custom2X: try c(cd.second.x),
		custom2Y: try c(cd.second.y),
		custom2Z: try c(cd.second.z),
		custom2W: try c(cd.second.w),
	});
}
