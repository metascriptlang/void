// h3d.scene.pbr.Environment: an equirectangular panorama turned into a cube (equiToCube), then
// the diffuse irradiance cube and the specular cube whose mip j holds roughness j / specLevels
// (computeIrradiance). The filtering is Bevy's (light_probe/generate.rs): the source cube gets a
// mip chain, each sample reads the mip that covers its solid angle, the sample count grows with
// roughness, and the specular mip 0 is the source itself. The shaders are environmentShader.ms.

import { Vec4 } from "../math/math3d";
import {
	PixelFormat, LoadAction, endPass, formatRenderable, makeSamplerEx, destroySampler,
} from "../gpu/door";
import { FilterMode, Wrap } from "../gpu/state";
import { ColorAttachment, NO_DEPTH, beginPass, layoutOf } from "../gpu/target";
import { PipelineCache, closePipelines, pipelineFor } from "../gpu/pipeline";
import {
	BINDING_LENGTH,
	BINDING_SAMPLER,
	BINDING_VERTEX_BUFFER,
	BINDING_VIEW,
	applyBindings,
	applyPipeline,
	applyUniforms,
	destroyBuffer,
	draw,
} from "../gpu/draw";
import { CUBE_FACES, CubeTarget, cubeFullLevels } from "../gpu/cubeTarget";
import { Texture } from "../gpu/texture";
import { TextureMipFilter } from "./textureMip";
import { makeScreenTriangle, screenState } from "./screenFx";
import { shaderProgram } from "../shader/program";
import { programLayout } from "../gpu/door";
import { fullscreenVs } from "./post3d";
import {
	environmentIrradianceFs,
	environmentPanoramaFs,
	environmentRadianceFs,
	environmentResampleFs,
} from "./environmentShader";

shaderProgram(environmentPanorama, fullscreenVs, environmentPanoramaFs);
shaderProgram(environmentResample, fullscreenVs, environmentResampleFs);
shaderProgram(environmentRadiance, fullscreenVs, environmentRadianceFs);
shaderProgram(environmentIrradiance, fullscreenVs, environmentIrradianceFs);

enum EnvironmentProgram {
	Panorama,
	Resample,
	Radiance,
	Irradiance,
}

function programOf(program: EnvironmentProgram): int32 {
	return match (program) {
		EnvironmentProgram.Panorama => environmentPanorama,
		EnvironmentProgram.Resample => environmentResample,
		EnvironmentProgram.Radiance => environmentRadiance,
		EnvironmentProgram.Irradiance => environmentIrradiance,
	};
}

// shader EnvironmentParams: five vec4.
const ENVIRONMENT_PARAMS_FLOATS: int32 = 20;

export enum EnvironmentError {
	NotPanorama,
	NotRenderable,
}

export interface Environment {
	source: Texture;
	diffSize: int32;
	specSize: int32;
	// Heaps' IrradShader.hdrMax: no source texel is brighter in the bake.
	hdrMax: float32;
	// equiToCube's fake HDR: a panorama texel brighter than `threshold` is multiplied by `scale`.
	threshold: float32;
	scale: float32;
	// The panorama stores sRGB-encoded colour, as an 8-bit image does.
	srgb: boolean;
	// Renderer.hx:715-723: the light's multiplier and its turn about the up axis, in radians.
	power: float32;
	rotation: float32;
	env: CubeTarget;
	scratch: CubeTarget;
	diffuse: CubeTarget;
	specular: CubeTarget;
	pipelines: PipelineCache;
	triangle: uint32;
	sampler: uint32;
	params: Vec<float32>;
	bindings: Vec<uint32>;
	closed: boolean;
}

// Heaps' DEFAULT_FORMAT for a float panorama, Bevy's for every baked cube.
const BAKE_FORMAT: PixelFormat = PixelFormat.Rgba16f;
const IRRADIANCE_SAMPLES: float32 = 1024.0;
const PARAM_FACE: int32 = 0;
const PARAM_BAKE: int32 = 12;
const PARAM_SOURCE: int32 = 16;

// Environment.new's sizes (diffSize 64, specSize 512) and the defaults of equiToCube and hdrMax.
// The cube is as wide as the panorama is high (equiToCube).
export function fromPanorama(
	this typeof Environment,
	source: Texture,
	diffSize: int32 = 64,
	specSize: int32 = 512,
): Result<Environment, EnvironmentError> {
	if (source.width != source.height * 2) { return Result.err(EnvironmentError.NotPanorama); }
	if (!formatRenderable(BAKE_FORMAT)) { return Result.err(EnvironmentError.NotRenderable); }
	const size: int32 = source.height;
	return Result.ok({
		source: source,
		diffSize: diffSize,
		specSize: specSize,
		hdrMax: 10.0,
		threshold: 1.0,
		scale: 1.0,
		srgb: true,
		power: 1.0,
		rotation: 0.0,
		env: CubeTarget.unallocated(size, cubeFullLevels(size), BAKE_FORMAT),
		scratch: CubeTarget.unallocated(size >> 1, cubeFullLevels(size) - 1, BAKE_FORMAT),
		diffuse: CubeTarget.unallocated(diffSize, 1, BAKE_FORMAT),
		specular: CubeTarget.unallocated(specSize, cubeFullLevels(specSize), BAKE_FORMAT),
		pipelines: PipelineCache.empty(),
		triangle: 0,
		sampler: 0,
		params: new Array(ENVIRONMENT_PARAMS_FLOATS),
		bindings: new Array(BINDING_LENGTH),
		closed: false,
	});
}

function stopOnClosedEnvironment(call: string): void {
	console.log(`void3d environment: ${call} on an environment that was closed`);
	unreachable;
}

// Heaps' Environment.specLevels: the specular mip that holds roughness 1.
export function specLevels(this environment: Environment): int32 {
	return environment.specular.levels - 1;
}

// Whether the baked cubes belong to the current GPU context; after context loss compute bakes
// them again.
export function isCurrent(this environment: Environment): boolean {
	if (environment.closed) { stopOnClosedEnvironment("isCurrent"); }
	return environment.diffuse.isCurrent() && environment.specular.isCurrent();
}

function mipSize(size: int32, level: int32): int32 {
	const shifted: int32 = size >> level;
	return shifted > 0 ? shifted : 1;
}

// Environment.getCubeMatrix, as the three rows faceDirection reads.
function writeFace(environment: Environment, face: int32): void {
	const rows: float32[] = match (face) {
		0 => [0.0, 0.0, -1.0, 0.0, -1.0, 0.0, 1.0, 0.0, 0.0],
		1 => [0.0, 0.0, 1.0, 0.0, -1.0, 0.0, -1.0, 0.0, 0.0],
		2 => [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0],
		3 => [1.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, -1.0, 0.0],
		4 => [1.0, 0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 1.0],
		_ => [-1.0, 0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, -1.0],
	};
	for (let row = 0; row < 3; row++) {
		for (let i = 0; i < 3; i++) {
			environment.params[PARAM_FACE + row * 4 + i] = rows[row * 3 + i];
		}
		environment.params[PARAM_FACE + row * 4 + 3] = 0.0;
	}
}

function writeBake(
	environment: Environment, x: float32, count: float32, sourceWidth: int32, drawnWidth: int32,
): void {
	environment.params[PARAM_BAKE] = x;
	environment.params[PARAM_BAKE + 1] = count;
	environment.params[PARAM_BAKE + 2] = sourceWidth as float32;
	environment.params[PARAM_BAKE + 3] = drawnWidth as float32;
}

const CLEAR: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 0.0 };

// One fullscreen draw of `program` into face `face` of mip `level` of `target`, reading `view`.
function bakeFace(
	environment: Environment,
	program: EnvironmentProgram,
	target: CubeTarget,
	face: int32,
	level: int32,
	view: uint32,
): void {
	writeFace(environment, face);
	const colors: ColorAttachment[] = [target.asColor(face, level, LoadAction.DontCare, CLEAR)];
	beginPass(colors, NO_DEPTH);
	const id: int32 = programOf(program);
	const pipeline: uint32 = pipelineFor(environment.pipelines, id, programLayout(id), false,
		screenState(), layoutOf(colors, NO_DEPTH));
	applyPipeline(pipeline);
	for (let i = 0; i < BINDING_LENGTH; i++) { environment.bindings[i] = 0; }
	environment.bindings[BINDING_VERTEX_BUFFER] = environment.triangle;
	environment.bindings[BINDING_VIEW] = view;
	environment.bindings[BINDING_SAMPLER] = environment.sampler;
	applyBindings(environment.bindings);
	applyUniforms(0, environment.params);
	draw(0, 3, 1);
	endPass();
}

function bakeCube(
	environment: Environment,
	program: EnvironmentProgram,
	target: CubeTarget,
	level: int32,
	view: uint32,
): void {
	for (let face = 0; face < CUBE_FACES; face++) {
		bakeFace(environment, program, target, face, level, view);
	}
}

// generate.rs's sample count for a radiance mip: 32 at roughness 0, doubling each quarter.
function radianceSamples(roughness: float32): float32 {
	return (32 * (1 << ((roughness * 4.0) as int32))) as float32;
}

function allocateGpu(environment: Environment): void {
	if (environment.triangle == 0) { environment.triangle = makeScreenTriangle(); }
	if (environment.sampler == 0) {
		environment.sampler = makeSamplerEx(FilterMode.Linear as int32, FilterMode.Linear as int32,
			TextureMipFilter.Linear as int32, Wrap.Clamp as int32, Wrap.Clamp as int32, 0.0, 1000.0,
			1);
	}
	environment.env.allocate();
	environment.scratch.allocate();
	environment.diffuse.allocate();
	environment.specular.allocate();
}

// Environment.compute with equiToCube before it; call outside any pass, before the frame's draws.
export function compute(this environment: Environment): void {
	if (environment.closed) { stopOnClosedEnvironment("compute"); }
	allocateGpu(environment);
	const env: CubeTarget = environment.env;
	const size: int32 = env.size;
	environment.params[PARAM_SOURCE] = environment.threshold;
	environment.params[PARAM_SOURCE + 1] = environment.scale;
	environment.params[PARAM_SOURCE + 2] = environment.hdrMax;
	environment.params[PARAM_SOURCE + 3] = environment.srgb ? 1.0 : 0.0;

	writeBake(environment, 0.0, 0.0, size, size);
	bakeCube(environment, EnvironmentProgram.Panorama, env, 0, environment.source.asView());

	// A cube cannot be read while one of its own mips is drawn, so each mip goes through the
	// scratch cube, whose mip k - 1 is the env's mip k.
	for (let level = 1; level < env.levels; level++) {
		const width: int32 = mipSize(size, level);
		writeBake(environment, (level - 1) as float32, 0.0, size, width);
		bakeCube(environment, EnvironmentProgram.Resample, environment.scratch, level - 1,
			env.asTexture());
		writeBake(environment, (level - 1) as float32, 0.0, size, width);
		bakeCube(environment, EnvironmentProgram.Resample, env, level,
			environment.scratch.asTexture());
	}

	const source: uint32 = env.asTexture();
	writeBake(environment, 0.0, IRRADIANCE_SAMPLES, size, environment.diffSize);
	bakeCube(environment, EnvironmentProgram.Irradiance, environment.diffuse, 0, source);

	const specular: CubeTarget = environment.specular;
	const matched: float32 =
		Math.max(Math.log2((size as float64) / (specular.size as float64)), 0.0) as float32;
	writeBake(environment, matched, 0.0, size, specular.size);
	bakeCube(environment, EnvironmentProgram.Resample, specular, 0, source);
	for (let level = 1; level < specular.levels; level++) {
		const roughness: float32 = (level as float32) / (environment.specLevels() as float32);
		writeBake(environment, roughness, radianceSamples(roughness), size,
			mipSize(specular.size, level));
		bakeCube(environment, EnvironmentProgram.Radiance, specular, level, source);
	}
}

export function close(this environment: Environment): void {
	if (environment.closed) { stopOnClosedEnvironment("close"); }
	environment.env.close();
	environment.scratch.close();
	environment.diffuse.close();
	environment.specular.close();
	closePipelines(environment.pipelines);
	if (environment.triangle != 0) { destroyBuffer(environment.triangle); }
	if (environment.sampler != 0) { destroySampler(environment.sampler); }
	environment.triangle = 0;
	environment.sampler = 0;
	environment.closed = true;
}
