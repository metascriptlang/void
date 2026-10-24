// The fragment's cluster lookup on the CPU, held to the clusters' own tiling and slicing and to
// assignLights: a fragment at a light's centre finds that light through the two data textures and
// not a light across the screen; and its GLSL fetches both textures as unsigned texels.

import { glsl } from "../shader/emit";
import {
	Sampler, Texture2dU32, Vec2f, Vec4f, builtin, binding, textureLoad, vec2f, vec4f, vec4i,
} from "../shader/std";
import { vec3 } from "../math/math3d";
import { Camera3D, CameraView, ProjectionKind } from "../void3d/camera";
import {
	ClusterAssignment, ClusterConfig, ClusterLight, ClusterLightKind, assignLights,
	clusterFactors, depthToZSlice,
} from "../void3d/clusters";
import {
	ClusterParams, clusterIndexOf, dataTexelOf, indexOfWord, indexTexelOf,
} from "../void3d/clusterLookup";
import {
	DataTexture, clusterParamsOf, clusterTexture, indexTexture,
} from "../void3d/clusterTextures";

const WIDTH: int32 = 1920;
const HEIGHT: int32 = 1080;

struct ProbeInput {
	@builtin(position) position: Vec4f;
}

struct ProbeBindings {
	@binding(5) clusterParams: ClusterParams;
	@binding(6) clusterRecords: Texture2dU32;
	@binding(7) clusterIndices: Texture2dU32;
	@binding(6) dataSampler: Sampler;
}

// 1 when the cluster of a fragment at `frag` pixels and `depth` lists light `light`.
function clusterHolds(frag: Vec2f, depth: float32, light: int32, b: ProbeBindings): float32 {
	const cluster = clusterIndexOf(frag, depth, b.clusterParams.clusterGrid,
		b.clusterParams.clusterFactors);
	const record = vec4i(textureLoad(b.clusterRecords, b.dataSampler, dataTexelOf(cluster), 0));
	const count = record.y + record.z;
	for (let k = 0; k < count; k++) {
		const j = record.x + k;
		const texel = textureLoad(b.clusterIndices, b.dataSampler, indexTexelOf(j), 0);
		if (indexOfWord(texel, j) == light) {
			return 1.0;
		}
	}
	return 0.0;
}

function probeClusterFs(input: ProbeInput, b: ProbeBindings): Vec4f {
	return vec4f(clusterHolds(input.position.xy, input.position.z, 0, b), 0.0, 0.0, 1.0);
}

function camera(orthographic: boolean): CameraView {
	const made: Camera3D = {
		position: vec3(0.0, 0.0, 0.0),
		yaw: 0.0,
		pitch: 0.0,
		projection: orthographic
			? { kind: ProjectionKind.Orthographic, worldPerTexel: 0.02, snap: false }
			: { kind: ProjectionKind.Perspective, fovY: 0.8 },
		nearPlane: 0.1,
		farPlane: 500.0,
	};
	const view = made.resolve(WIDTH, HEIGHT);
	if (!view.ok) { unreachable; }
	return view.value;
}

function pointAt(x: float32, depth: float32): ClusterLight {
	return {
		kind: ClusterLightKind.Point,
		position: vec3(x, 0.0, -depth),
		range: 1.0,
		direction: vec3(0.0, 0.0, -1.0),
		outerHalfAngle: 0.0,
	};
}

function assign(view: CameraView, lights: ClusterLight[]): ClusterAssignment {
	const result = assignLights(ClusterConfig.defaults(), view, WIDTH, HEIGHT, 50.0, lights);
	if (!result.ok) { unreachable; }
	return result.value;
}

function asTexture(data: DataTexture): Texture2dU32 {
	let texels: uint32[] = [];
	for (const word of data.words) { texels.push(word); }
	return { width: data.width, height: data.height, texels };
}

function bound(a: ClusterAssignment, orthographic: boolean): ProbeBindings {
	return {
		clusterParams: clusterParamsOf(a, WIDTH, HEIGHT, orthographic),
		clusterRecords: asTexture(clusterTexture(a)),
		clusterIndices: asTexture(indexTexture(a)),
		dataSampler: {},
	};
}

// The pixel a world point lands on, counted from the top-left.
function pixelOf(view: CameraView, x: float32, depth: float32): Vec2f {
	const ndc = vec3(x, 0.0, -depth).project(view.viewProj);
	return vec2f((ndc.x * 0.5 + 0.5) * (WIDTH as float32), (ndc.y * -0.5 + 0.5) *
		(HEIGHT as float32));
}

function cellOf(position: float32, cells: int32): int32 {
	return Math.min(Math.max(Math.floor(position as float64) as int32, 0), cells - 1);
}

test "a fragment's cluster is its tile column and row from the top-left, then its depth slice" {
	for (const orthographic of [false, true]) {
		const a: ClusterAssignment = assign(camera(orthographic), [pointAt(0.0, 10.0)]);
		const p: ClusterParams = clusterParamsOf(a, WIDTH, HEIGHT, orthographic);
		const g = a.grid;
		const factors = clusterFactors(a.near, a.far, g.z as float32, orthographic);
		for (const frag of [vec2f(0.0, 0.0), vec2f(959.5, 300.25), vec2f(1919.5, 1079.5)]) {
			const depths: float32[] = [0.05, 3.0, 47.0, 900.0];
			for (const depth of depths) {
				const x = cellOf(frag.x * (g.x as float32) / (WIDTH as float32), g.x);
				const y = cellOf(frag.y * (g.y as float32) / (HEIGHT as float32), g.y);
				const z = depthToZSlice(factors, g.z, depth, orthographic);
				const index = clusterIndexOf(frag, depth, p.clusterGrid, p.clusterFactors);
				assert index == (y * g.x + x) * g.z + z;
			}
		}
	}
}

test "a fragment at a light's centre finds that light and not one across the screen" {
	const view: CameraView = camera(false);
	const a: ClusterAssignment = assign(view, [pointAt(-6.0, 12.0), pointAt(6.0, 12.0)]);
	const b: ProbeBindings = bound(a, false);
	const left = pixelOf(view, -6.0, 12.0);
	const right = pixelOf(view, 6.0, 12.0);
	assert clusterHolds(left, 12.0, 0, b) == 1.0 && clusterHolds(left, 12.0, 1, b) == 0.0;
	assert clusterHolds(right, 12.0, 1, b) == 1.0 && clusterHolds(right, 12.0, 0, b) == 0.0;
	assert clusterHolds(left, 40.0, 0, b) == 0.0;
}

test "record i sits at texel (i % 256, i / 256), and index j in channel j % 4 of texel j / 4" {
	const at = dataTexelOf(256 * 3 + 17);
	assert at.x == 17 && at.y == 3;
	const next = indexTexelOf(256 * 4 + 5);
	assert next.x == 1 && next.y == 1;
	assert indexOfWord({ x: 5, y: 6, z: 7, w: 8 }, 9) == 6;
	assert indexOfWord({ x: 5, y: 6, z: 7, w: 8 }, 12) == 5;
}

test "the lookup's GLSL fetches the cluster record and the index list as unsigned texels" {
	const source: string = glsl(probeClusterFs);
	assert source.includes("uniform utexture2D clusterRecords;");
	assert source.includes("texelFetch(usampler2D(clusterIndices, dataSampler), ");
	assert source.includes("log(");
}
