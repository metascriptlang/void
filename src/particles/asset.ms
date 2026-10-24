// The authored particle system: Unity's ParticleSystem modules with Unity's field names, enums,
// units and defaults (docs/PARTICLES.md; field tables in PARTICLES-AUTHORING.md §1). A default
// marked (mem) in that report is from Unity's manual, not its source, until a Unity capture pins it.

import { Vec3, vec3 } from "../math/math3d";
import {
	MinMaxCurve, MinMaxGradient, ParticleColor, AnimationCurve, WHITE,
	constantCurve, constantColor, curveOf, linearCurve, key,
} from "./curve";

export struct Range {
	min: float32;
	max: float32;
}

// ---- Main ----

export enum SimulationSpace {
	Local,
	World,
}

export enum GravitySource {
	Physics3D,
	Physics2D,
}

export enum ScalingMode {
	Hierarchy,
	Local,
	Shape,
}

export enum EmitterVelocityMode {
	Transform,
	Custom,
}

export enum StopAction {
	None,
	Disable,
	Destroy,
	Callback,
}

export enum CullingMode {
	Automatic,
	PauseAndCatchup,
	Pause,
	AlwaysSimulate,
}

export enum RingBufferMode {
	Disabled,
	PauseUntilReplaced,
	LoopUntilReplaced,
}

export struct MainModule {
	duration: float32;
	loop: boolean;
	prewarm: boolean;
	startDelay: MinMaxCurve;
	startLifetime: MinMaxCurve;
	startSpeed: MinMaxCurve;
	startSize3D: boolean;
	startSizeX: MinMaxCurve;
	startSizeY: MinMaxCurve;
	startSizeZ: MinMaxCurve;
	startRotation3D: boolean;
	startRotationX: MinMaxCurve;
	startRotationY: MinMaxCurve;
	startRotationZ: MinMaxCurve;
	flipRotation: float32;
	startColor: MinMaxGradient;
	gravitySource: GravitySource;
	gravityModifier: MinMaxCurve;
	simulationSpace: SimulationSpace;
	simulationSpeed: float32;
	scalingMode: ScalingMode;
	playOnAwake: boolean;
	emitterVelocityMode: EmitterVelocityMode;
	emitterVelocity: Vec3;
	maxParticles: int32;
	stopAction: StopAction;
	cullingMode: CullingMode;
	ringBufferMode: RingBufferMode;
	ringBufferLoopRange: Range;
	useAutoRandomSeed: boolean;
	randomSeed: uint32;
}

// ---- Emission ----

export struct Burst {
	time: float32;
	count: MinMaxCurve;
	cycleCount: int32;
	repeatInterval: float32;
	probability: float32;
}

export struct EmissionModule {
	enabled: boolean;
	rateOverTime: MinMaxCurve;
	rateOverDistance: MinMaxCurve;
	bursts: Vec<Burst>;
}

// ---- Shape ----

// ParticleSystemShapeType (PSE:130-179) without the obsolete shell values; the mesh, sprite and
// renderer sources are listed so an import names them, and the simulation refuses them.
export enum ShapeType {
	Sphere,
	Hemisphere,
	Cone,
	ConeVolume,
	Box,
	BoxShell,
	BoxEdge,
	Circle,
	SingleSidedEdge,
	Donut,
	Rectangle,
	Mesh,
	MeshRenderer,
	SkinnedMeshRenderer,
	Sprite,
	SpriteRenderer,
}

export enum ShapeMultiModeValue {
	Random,
	Loop,
	PingPong,
	BurstSpread,
}

export enum ConeEmitFrom {
	Base,
	Volume,
}

export struct ShapeModule {
	enabled: boolean;
	shapeType: ShapeType;
	radius: float32;
	radiusThickness: float32;
	radiusMode: ShapeMultiModeValue;
	radiusSpread: float32;
	radiusSpeed: MinMaxCurve;
	angle: float32;
	length: float32;
	boxThickness: Vec3;
	arc: float32;
	arcMode: ShapeMultiModeValue;
	arcSpread: float32;
	arcSpeed: MinMaxCurve;
	donutRadius: float32;
	position: Vec3;
	rotation: Vec3;
	scale: Vec3;
	alignToDirection: boolean;
	randomDirectionAmount: float32;
	sphericalDirectionAmount: float32;
	randomPositionAmount: float32;
}

// ---- velocity and force ----

export struct VelocityOverLifetimeModule {
	enabled: boolean;
	x: MinMaxCurve;
	y: MinMaxCurve;
	z: MinMaxCurve;
	space: SimulationSpace;
	orbitalX: MinMaxCurve;
	orbitalY: MinMaxCurve;
	orbitalZ: MinMaxCurve;
	orbitalOffsetX: MinMaxCurve;
	orbitalOffsetY: MinMaxCurve;
	orbitalOffsetZ: MinMaxCurve;
	radial: MinMaxCurve;
	speedModifier: MinMaxCurve;
}

export struct LimitVelocityOverLifetimeModule {
	enabled: boolean;
	separateAxes: boolean;
	limit: MinMaxCurve;
	limitX: MinMaxCurve;
	limitY: MinMaxCurve;
	limitZ: MinMaxCurve;
	space: SimulationSpace;
	dampen: float32;
	drag: MinMaxCurve;
	multiplyDragByParticleSize: boolean;
	multiplyDragByParticleVelocity: boolean;
}

export enum InheritVelocityMode {
	Initial,
	Current,
}

export struct InheritVelocityModule {
	enabled: boolean;
	mode: InheritVelocityMode;
	curve: MinMaxCurve;
}

export struct LifetimeByEmitterSpeedModule {
	enabled: boolean;
	curve: MinMaxCurve;
	range: Range;
}

export struct ForceOverLifetimeModule {
	enabled: boolean;
	x: MinMaxCurve;
	y: MinMaxCurve;
	z: MinMaxCurve;
	space: SimulationSpace;
	randomized: boolean;
}

export enum ForceFieldShape {
	Sphere,
	Hemisphere,
	Cylinder,
	Box,
}

// ParticleSystemForceField: a scene object the app places; ExternalForces filters and scales the
// fields that act on this system. Shipped as Godot's attractor plus the Unity names that map 1:1.
export struct ForceField {
	shape: ForceFieldShape;
	position: Vec3;
	startRange: float32;
	endRange: float32;
	length: float32;
	direction: Vec3;
	gravity: float32;
	gravityFocus: float32;
	drag: float32;
	multiplyDragByParticleSize: boolean;
	multiplyDragByParticleVelocity: boolean;
	layer: int32;
}

export struct ExternalForcesModule {
	enabled: boolean;
	multiplier: MinMaxCurve;
	influenceMask: uint32;
}

// ---- appearance over lifetime and by speed ----

export struct ColorOverLifetimeModule {
	enabled: boolean;
	color: MinMaxGradient;
}

export struct ColorBySpeedModule {
	enabled: boolean;
	color: MinMaxGradient;
	range: Range;
}

export struct SizeOverLifetimeModule {
	enabled: boolean;
	separateAxes: boolean;
	x: MinMaxCurve;
	y: MinMaxCurve;
	z: MinMaxCurve;
}

export struct SizeBySpeedModule {
	enabled: boolean;
	separateAxes: boolean;
	x: MinMaxCurve;
	y: MinMaxCurve;
	z: MinMaxCurve;
	range: Range;
}

// Angular velocity in radians per second, as Unity stores it.
export struct RotationOverLifetimeModule {
	enabled: boolean;
	separateAxes: boolean;
	x: MinMaxCurve;
	y: MinMaxCurve;
	z: MinMaxCurve;
}

export struct RotationBySpeedModule {
	enabled: boolean;
	separateAxes: boolean;
	x: MinMaxCurve;
	y: MinMaxCurve;
	z: MinMaxCurve;
	range: Range;
}

// ---- noise ----

export enum NoiseQuality {
	Low,
	Medium,
	High,
}

export struct NoiseModule {
	enabled: boolean;
	separateAxes: boolean;
	strengthX: MinMaxCurve;
	strengthY: MinMaxCurve;
	strengthZ: MinMaxCurve;
	frequency: float32;
	scrollSpeed: MinMaxCurve;
	damping: boolean;
	octaveCount: int32;
	octaveMultiplier: float32;
	octaveScale: float32;
	quality: NoiseQuality;
	remapEnabled: boolean;
	remapX: MinMaxCurve;
	remapY: MinMaxCurve;
	remapZ: MinMaxCurve;
	positionAmount: MinMaxCurve;
	rotationAmount: MinMaxCurve;
	sizeAmount: MinMaxCurve;
}

// ---- collision and triggers ----

export enum CollisionType {
	Planes,
	World,
}

export enum CollisionMode {
	Collision3D,
	Collision2D,
}

// A plane through `point` facing `normal`; particles live on the side the normal points to.
export struct CollisionPlane {
	point: Vec3;
	normal: Vec3;
}

export enum ColliderShape {
	Sphere,
	Box,
	Capsule,
}

// An analytic collider of the particle world (Godot's particle colliders; capsule is an addition).
// A box is centred on `center` with half-extents `extents`; a capsule runs from `center` to `end`.
export struct ParticleCollider {
	shape: ColliderShape;
	center: Vec3;
	extents: Vec3;
	end: Vec3;
	radius: float32;
	layer: int32;
}

export struct CollisionModule {
	enabled: boolean;
	collisionType: CollisionType;
	mode: CollisionMode;
	planes: Vec<CollisionPlane>;
	dampen: MinMaxCurve;
	bounce: MinMaxCurve;
	lifetimeLoss: MinMaxCurve;
	minKillSpeed: float32;
	maxKillSpeed: float32;
	radiusScale: float32;
	collidesWith: uint32;
	sendCollisionMessages: boolean;
}

export enum TriggerAction {
	Ignore,
	Kill,
	Callback,
}

export struct TriggerModule {
	enabled: boolean;
	inside: TriggerAction;
	outside: TriggerAction;
	enter: TriggerAction;
	exit: TriggerAction;
	radiusScale: float32;
	colliders: Vec<ParticleCollider>;
}

// ---- sub-emitters ----

export enum SubEmitterType {
	Birth,
	Collision,
	Death,
	Trigger,
	Manual,
}

export enum SubEmitterProperty {
	InheritColor,
	InheritSize,
	InheritRotation,
	InheritLifetime,
	InheritDuration,
}

// `system` is the child's index in its ParticleEffect.
export struct SubEmitter {
	system: int32;
	subEmitterType: SubEmitterType;
	properties: BitSet<SubEmitterProperty>;
	emitProbability: float32;
}

export struct SubEmittersModule {
	enabled: boolean;
	subEmitters: Vec<SubEmitter>;
}

// ---- texture sheet ----

export enum TextureSheetMode {
	Grid,
	Sprites,
}

export enum TextureSheetAnimationType {
	WholeSheet,
	SingleRow,
}

export enum TextureSheetRowMode {
	Custom,
	Random,
}

export enum TextureSheetTimeMode {
	Lifetime,
	Speed,
	FPS,
}

// `frameOverTime` and `startFrame` are fractions of the sheet, 0 to 1, as Unity stores them.
export struct TextureSheetAnimationModule {
	enabled: boolean;
	mode: TextureSheetMode;
	numTilesX: int32;
	numTilesY: int32;
	animation: TextureSheetAnimationType;
	rowMode: TextureSheetRowMode;
	rowIndex: int32;
	timeMode: TextureSheetTimeMode;
	frameOverTime: MinMaxCurve;
	startFrame: MinMaxCurve;
	fps: float32;
	speedRange: Range;
	cycleCount: int32;
	flipU: float32;
	flipV: float32;
	spriteCount: int32;
}

// ---- lights, trails, custom data ----

export struct LightsModule {
	enabled: boolean;
	ratio: float32;
	useRandomDistribution: boolean;
	useParticleColor: boolean;
	sizeAffectsRange: boolean;
	alphaAffectsIntensity: boolean;
	range: MinMaxCurve;
	rangeMultiplier: float32;
	intensity: MinMaxCurve;
	intensityMultiplier: float32;
	color: ParticleColor;
	maxLights: int32;
}

export enum TrailMode {
	PerParticle,
	Ribbon,
}

export enum TrailTextureMode {
	Stretch,
	Tile,
	DistributePerSegment,
	RepeatPerSegment,
	Static,
}

export struct TrailModule {
	enabled: boolean;
	mode: TrailMode;
	ratio: float32;
	lifetime: MinMaxCurve;
	minVertexDistance: float32;
	textureMode: TrailTextureMode;
	textureScale: Vec3;
	worldSpace: boolean;
	dieWithParticles: boolean;
	sizeAffectsWidth: boolean;
	sizeAffectsLifetime: boolean;
	inheritParticleColor: boolean;
	colorOverLifetime: MinMaxGradient;
	widthOverTrail: MinMaxCurve;
	colorOverTrail: MinMaxGradient;
	ribbonCount: int32;
	splitSubEmitterRibbons: boolean;
	attachRibbonsToTransform: boolean;
}

export enum CustomDataMode {
	Disabled,
	Vector,
	Color,
}

export struct CustomDataStream {
	mode: CustomDataMode;
	vectorComponentCount: int32;
	x: MinMaxCurve;
	y: MinMaxCurve;
	z: MinMaxCurve;
	w: MinMaxCurve;
	color: MinMaxGradient;
}

export struct CustomDataModule {
	enabled: boolean;
	first: CustomDataStream;
	second: CustomDataStream;
}

// ---- renderer ----

export enum RenderMode {
	Billboard,
	Stretch,
	HorizontalBillboard,
	VerticalBillboard,
	Mesh,
	None,
}

export enum RenderAlignment {
	View,
	World,
	Local,
	Facing,
	Velocity,
}

export enum ParticleSortMode {
	None,
	Distance,
	OldestInFront,
	YoungestInFront,
	Depth,
	DistanceReverse,
	DepthReverse,
}

// How a Mesh-mode particle picks one of the renderer's meshes: any with equal odds, or by weight.
export const MAX_MESHES: int32 = 4;

export enum MeshDistribution {
	UniformRandom,
	NonUniformRandom,
}

export struct RendererModule {
	renderMode: RenderMode;
	alignment: RenderAlignment;
	sortMode: ParticleSortMode;
	sortingFudge: float32;
	sortingOrder: int32;
	minParticleSize: float32;
	maxParticleSize: float32;
	lengthScale: float32;
	velocityScale: float32;
	cameraVelocityScale: float32;
	normalDirection: float32;
	pivot: Vec3;
	flip: Vec3;
	allowRoll: boolean;
	freeformStretching: boolean;
	rotateWithStretchDirection: boolean;
	softParticlesNear: float32;
	softParticlesFar: float32;
	cameraFadeNear: float32;
	cameraFadeFar: float32;
	meshCount: int32;
	meshWeights: float32[4];
	meshDistribution: MeshDistribution;
}

// ---- the system ----

export struct ParticleSystemAsset {
	main: MainModule;
	emission: EmissionModule;
	shape: ShapeModule;
	velocityOverLifetime: VelocityOverLifetimeModule;
	limitVelocityOverLifetime: LimitVelocityOverLifetimeModule;
	inheritVelocity: InheritVelocityModule;
	lifetimeByEmitterSpeed: LifetimeByEmitterSpeedModule;
	forceOverLifetime: ForceOverLifetimeModule;
	externalForces: ExternalForcesModule;
	colorOverLifetime: ColorOverLifetimeModule;
	colorBySpeed: ColorBySpeedModule;
	sizeOverLifetime: SizeOverLifetimeModule;
	sizeBySpeed: SizeBySpeedModule;
	rotationOverLifetime: RotationOverLifetimeModule;
	rotationBySpeed: RotationBySpeedModule;
	noise: NoiseModule;
	collision: CollisionModule;
	trigger: TriggerModule;
	subEmitters: SubEmittersModule;
	textureSheetAnimation: TextureSheetAnimationModule;
	lights: LightsModule;
	trails: TrailModule;
	customData: CustomDataModule;
	renderer: RendererModule;
	// Godot's PARTICLE_FLAG_DISABLE_Z: the integrator keeps z at zero, for void2d.
	space2D: boolean;
}

// A root system and the systems its sub-emitters name, by index; the root is index 0.
export struct ParticleEffect {
	systems: Vec<ParticleSystemAsset>;
}

const DEGREE: float32 = 0.017453292519943295;

function zero(): MinMaxCurve {
	return constantCurve(0.0);
}

function one(): MinMaxCurve {
	return constantCurve(1.0);
}

function unitRange(): Range {
	return { min: 0.0, max: 1.0 };
}

function rising(): AnimationCurve {
	return linearCurve([key(0.0, 0.0), key(1.0, 1.0)]);
}

function disabledStream(): CustomDataStream {
	return {
		mode: CustomDataMode.Disabled, vectorComponentCount: 4,
		x: zero(), y: zero(), z: zero(), w: zero(), color: constantColor(WHITE),
	};
}

// A new ParticleSystem component as Unity creates it.
export function defaults(this typeof ParticleSystemAsset): ParticleSystemAsset {
	return {
		main: {
			duration: 5.0, loop: true, prewarm: false, startDelay: zero(),
			startLifetime: constantCurve(5.0), startSpeed: constantCurve(5.0),
			startSize3D: false, startSizeX: one(), startSizeY: one(), startSizeZ: one(),
			startRotation3D: false, startRotationX: zero(), startRotationY: zero(),
			startRotationZ: zero(), flipRotation: 0.0, startColor: constantColor(WHITE),
			gravitySource: GravitySource.Physics3D, gravityModifier: zero(),
			simulationSpace: SimulationSpace.Local, simulationSpeed: 1.0,
			scalingMode: ScalingMode.Local, playOnAwake: true,
			emitterVelocityMode: EmitterVelocityMode.Transform, emitterVelocity: vec3(0.0, 0.0, 0.0),
			maxParticles: 1000, stopAction: StopAction.None, cullingMode: CullingMode.Automatic,
			ringBufferMode: RingBufferMode.Disabled, ringBufferLoopRange: unitRange(),
			useAutoRandomSeed: true, randomSeed: 0,
		},
		emission: {
			enabled: true, rateOverTime: constantCurve(10.0), rateOverDistance: zero(), bursts: [],
		},
		shape: {
			enabled: true, shapeType: ShapeType.Cone, radius: 1.0, radiusThickness: 1.0,
			radiusMode: ShapeMultiModeValue.Random, radiusSpread: 0.0, radiusSpeed: one(),
			angle: 25.0, length: 5.0, boxThickness: vec3(0.0, 0.0, 0.0), arc: 360.0,
			arcMode: ShapeMultiModeValue.Random, arcSpread: 0.0, arcSpeed: one(),
			donutRadius: 0.2, position: vec3(0.0, 0.0, 0.0), rotation: vec3(0.0, 0.0, 0.0),
			scale: vec3(1.0, 1.0, 1.0), alignToDirection: false, randomDirectionAmount: 0.0,
			sphericalDirectionAmount: 0.0, randomPositionAmount: 0.0,
		},
		velocityOverLifetime: {
			enabled: false, x: zero(), y: zero(), z: zero(), space: SimulationSpace.Local,
			orbitalX: zero(), orbitalY: zero(), orbitalZ: zero(),
			orbitalOffsetX: zero(), orbitalOffsetY: zero(), orbitalOffsetZ: zero(),
			radial: zero(), speedModifier: one(),
		},
		limitVelocityOverLifetime: {
			enabled: false, separateAxes: false, limit: one(), limitX: one(), limitY: one(),
			limitZ: one(), space: SimulationSpace.Local, dampen: 0.0, drag: zero(),
			multiplyDragByParticleSize: true, multiplyDragByParticleVelocity: true,
		},
		inheritVelocity: { enabled: false, mode: InheritVelocityMode.Initial, curve: zero() },
		lifetimeByEmitterSpeed: { enabled: false, curve: one(), range: unitRange() },
		forceOverLifetime: {
			enabled: false, x: zero(), y: zero(), z: zero(), space: SimulationSpace.Local,
			randomized: false,
		},
		externalForces: { enabled: false, multiplier: one(), influenceMask: 0xFFFFFFFF },
		colorOverLifetime: { enabled: false, color: constantColor(WHITE) },
		colorBySpeed: { enabled: false, color: constantColor(WHITE), range: unitRange() },
		sizeOverLifetime: {
			enabled: false, separateAxes: false,
			x: curveOf(1.0, rising()), y: curveOf(1.0, rising()), z: curveOf(1.0, rising()),
		},
		sizeBySpeed: {
			enabled: false, separateAxes: false,
			x: curveOf(1.0, rising()), y: curveOf(1.0, rising()), z: curveOf(1.0, rising()),
			range: unitRange(),
		},
		rotationOverLifetime: {
			enabled: false, separateAxes: false, x: zero(), y: zero(), z: constantCurve(45.0 * DEGREE),
		},
		rotationBySpeed: {
			enabled: false, separateAxes: false, x: zero(), y: zero(),
			z: constantCurve(45.0 * DEGREE), range: unitRange(),
		},
		noise: {
			enabled: false, separateAxes: false, strengthX: one(), strengthY: one(), strengthZ: one(),
			frequency: 0.5, scrollSpeed: zero(), damping: true, octaveCount: 1,
			octaveMultiplier: 0.5, octaveScale: 2.0, quality: NoiseQuality.High,
			remapEnabled: false, remapX: curveOf(1.0, linearCurve([key(0.0, -1.0), key(1.0, 1.0)])),
			remapY: curveOf(1.0, linearCurve([key(0.0, -1.0), key(1.0, 1.0)])),
			remapZ: curveOf(1.0, linearCurve([key(0.0, -1.0), key(1.0, 1.0)])),
			positionAmount: one(), rotationAmount: zero(), sizeAmount: zero(),
		},
		collision: {
			enabled: false, collisionType: CollisionType.Planes, mode: CollisionMode.Collision3D,
			planes: [], dampen: zero(), bounce: one(), lifetimeLoss: zero(), minKillSpeed: 0.0,
			maxKillSpeed: 10000.0, radiusScale: 1.0, collidesWith: 0xFFFFFFFF,
			sendCollisionMessages: false,
		},
		trigger: {
			enabled: false, inside: TriggerAction.Kill, outside: TriggerAction.Ignore,
			enter: TriggerAction.Ignore, exit: TriggerAction.Ignore, radiusScale: 1.0, colliders: [],
		},
		subEmitters: { enabled: false, subEmitters: [] },
		textureSheetAnimation: {
			enabled: false, mode: TextureSheetMode.Grid, numTilesX: 1, numTilesY: 1,
			animation: TextureSheetAnimationType.WholeSheet, rowMode: TextureSheetRowMode.Custom,
			rowIndex: 0, timeMode: TextureSheetTimeMode.Lifetime,
			frameOverTime: curveOf(1.0, rising()), startFrame: zero(), fps: 30.0,
			speedRange: { min: 0.0, max: 1.0 }, cycleCount: 1, flipU: 0.0, flipV: 0.0,
			spriteCount: 1,
		},
		lights: {
			enabled: false, ratio: 0.0, useRandomDistribution: true, useParticleColor: true,
			sizeAffectsRange: true, alphaAffectsIntensity: true, range: one(), rangeMultiplier: 1.0,
			intensity: one(), intensityMultiplier: 1.0, color: WHITE, maxLights: 20,
		},
		trails: {
			enabled: false, mode: TrailMode.PerParticle, ratio: 1.0, lifetime: one(),
			minVertexDistance: 0.2, textureMode: TrailTextureMode.Stretch,
			textureScale: vec3(1.0, 1.0, 0.0), worldSpace: false, dieWithParticles: true,
			sizeAffectsWidth: true, sizeAffectsLifetime: false, inheritParticleColor: true,
			colorOverLifetime: constantColor(WHITE), widthOverTrail: one(),
			colorOverTrail: constantColor(WHITE), ribbonCount: 1, splitSubEmitterRibbons: false,
			attachRibbonsToTransform: false,
		},
		customData: { enabled: false, first: disabledStream(), second: disabledStream() },
		renderer: {
			renderMode: RenderMode.Billboard, alignment: RenderAlignment.View,
			sortMode: ParticleSortMode.None, sortingFudge: 0.0, sortingOrder: 0,
			minParticleSize: 0.0, maxParticleSize: 0.5, lengthScale: 2.0, velocityScale: 0.0,
			cameraVelocityScale: 0.0, normalDirection: 1.0, pivot: vec3(0.0, 0.0, 0.0),
			flip: vec3(0.0, 0.0, 0.0), allowRoll: true, freeformStretching: false,
			rotateWithStretchDirection: true, softParticlesNear: 0.0, softParticlesFar: 1.0,
			cameraFadeNear: 1.0, cameraFadeFar: 2.0,
			meshCount: 1, meshWeights: [1.0, 0.0, 0.0, 0.0],
			meshDistribution: MeshDistribution.UniformRandom,
		},
		space2D: false,
	};
}
