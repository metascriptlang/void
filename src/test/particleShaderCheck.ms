import { linearToSrgb as channelToSrgb, srgbToLinear as channelToLinear } from "../math/math3d";
import { glsl, glslLinked } from "../shader/emit";
import { Vec4f, vec2f, vec3f, vec4f, mat4x4f } from "../shader/std";
import {
	BillboardAttributes, BillboardBindings, BillboardFragmentInput, ParticleAttributes,
	ParticleVisualAttributes, VertexBindings, billboardFs, billboardVs, particleFs, particleVs,
	particleVisualVs, particleVisualPixelArtVs,
} from "../void3d/shader3d";
import { SceneLights, sceneLights } from "./lightHelpers";

test "typed particle VS rotates asymmetric anchored tile in world camera basis" {
	let input: ParticleVisualAttributes = {
		root: vec4f(4, 5, 6, 3), shape: vec4f(1.125, 0.25, -0.5, 1.57079632679),
		tile: vec4f(0.25, 0.125, 0.5, 0.625), color: vec4f(1, 0.5, 0.25, 0.25),
		velocity: vec3f(0, 0, 0), look: none(), scale: none(), pull: vec3f(0, 0, 0),
		emitterRight: vec3f(0, 0, 0), emitterUp: vec3f(0, 0, 0), index: 2,
	};
	let bindings: VertexBindings = {
		vertexParams: {
			viewProj: mat4x4f(vec4f(1, 0, 0, 0), vec4f(0, 1, 0, 0),
				vec4f(0, 0, 1, 0), vec4f(0, 0, 0, 1)),
			cameraRight: vec4f(1, 0, 0, 0), cameraUp: vec4f(0, 1, 0, 0), cameraPosition: none(),
		},
	};
	const point = particleVisualVs(input, bindings);
	assert Math.abs(point.worldPosition.x - 5.125) < 0.0001;
	assert Math.abs(point.worldPosition.y - 4.25) < 0.0001;
	assert point.worldPosition.z == 6 && point.clip.w == 1;
	assert point.towardCamera.z == 1;
	assert point.uv.x == 0.5 && point.uv.y == 0.125 && point.instanceColor.w == 0.25;
	bindings.vertexParams.cameraRight = vec4f(0, 0, -1, 0);
	const turned = particleVisualVs(input, bindings);
	assert turned.worldPosition.x == 4;
	assert Math.abs(turned.worldPosition.y - 4.25) < 0.0001;
	assert Math.abs(turned.worldPosition.z - 4.875) < 0.0001;
	bindings.vertexParams.cameraRight = vec4f(1, 0, 0, 0);
	bindings.vertexParams.viewProj = mat4x4f(vec4f(2, 0, 0, 0), vec4f(0, 3, 0, 0),
		vec4f(0, 0, -1, -1), vec4f(0, 0, -1, 0));
	input.root.z = -6;
	const perspective = particleVisualVs(input, bindings);
	assert Math.abs(perspective.clip.x - 10.25) < 0.0001;
	assert Math.abs(perspective.clip.y - 12.75) < 0.0001;
	assert perspective.clip.z == 5 && perspective.clip.w == 6;
	const pixel = particleVisualPixelArtVs(input, bindings);
	assert pixel.rootPosition.x == 4 && pixel.rootPosition.y == 5 && pixel.rootPosition.z == -6;
	assert pixel.depth01 == perspective.clip.z && pixel.clip.w == perspective.clip.w;
	assert pixel.uv.x == point.uv.x && pixel.instanceColor.w == 0.25;
}

test "typed particle VS emits constant corners and ordered handwritten FS varyings" {
	const source: string = glsl(particleVisualVs);
	assert source.includes("const vec2[6] PARTICLE_CORNERS = vec2[6](");
	assert source.includes("PARTICLE_CORNERS[uint(gl_VertexIndex) % 6]");
	const world = source.indexOf("out vec3 worldPosition;");
	const normal = source.indexOf("out vec3 towardCamera;");
	const uv = source.indexOf("out vec2 uv;");
	const color = source.indexOf("out vec4 instanceColor;");
	assert world >= 0 && normal > world && uv > normal && color > uv;
}

test "typed particle pixel-art VS keeps root and clip-z FS varying contract" {
	const source: string = glsl(particleVisualPixelArtVs);
	const uv = source.indexOf("out vec2 uv;");
	const root = source.indexOf("out vec3 rootPosition;");
	const color = source.indexOf("out vec4 instanceColor;");
	const depth = source.indexOf("out float depth01;");
	assert uv >= 0 && root > uv && color > root && depth > color;
	assert source.includes("PARTICLE_CORNERS[uint(gl_VertexIndex) % 6]");
}

function upright(): VertexBindings {
	return {
		vertexParams: {
			viewProj: mat4x4f(vec4f(1, 0, 0, 0), vec4f(0, 1, 0, 0),
				vec4f(0, 0, 1, 0), vec4f(0, 0, 0, 1)),
			cameraRight: vec4f(1, 0, 0, 0), cameraUp: vec4f(0, 1, 0, 0), cameraPosition: none(),
		},
	};
}

function none(): Vec4f {
	return vec4f(0, 0, 0, 0);
}

// A white texture and tint, no point light, the identity tone.
function plainBillboard(): BillboardBindings {
	const lights: SceneLights = sceneLights(none(), vec4f(0, 0, 1, 0.5), vec4f(1, 1, 1, 0), []);
	return {
		billboardParams: { billboardColor: vec4f(1, 1, 1, 1), billboard: none() },
		lightParams: lights.lightParams,
		lightRecords: lights.lightRecords,
		clusterRecords: lights.clusterRecords,
		clusterIndices: lights.clusterIndices,
		frameParams: { frame: vec4f(0, 1, 0, 0) },
		billboardTexture: { width: 1, height: 1, texels: [1.0, 1.0, 1.0, 1.0] },
		billboardSampler: { nearest: true },
	};
}

test "particle VS spans the root size along the camera basis and keeps its colour" {
	const input: ParticleAttributes = {
		root: vec4f(1, 2, 3, 2), color: vec4f(1, 0.5, 0.25, 0.75), index: 2,
	};
	const point = particleVs(input, upright());
	assert point.clip.x == 2 && point.clip.y == 3 && point.clip.z == 3 && point.clip.w == 1;
	assert point.particleColor.y == 0.5 && point.particleColor.w == 0.75;
	const first = particleVs({ root: input.root, color: input.color, index: 6 }, upright());
	assert first.clip.x == 0 && first.clip.y == 1;
}

test "particle FS keeps a solid colour under cutout and tones it" {
	const color = vec4f(0.5, 0.25, 1, 0.75);
	const kept = particleFs({ particleColor: color }, { frameParams: { frame: vec4f(0, 1, 0, 0) } },
		{ cutout: true });
	assert kept.x == 0.5 && kept.y == 0.25 && kept.w == 0.75;
	const linear = particleFs({ particleColor: color },
		{ frameParams: { frame: vec4f(0, 1, 1, 0) } }, { cutout: false });
	assert Math.abs(linear.x - channelToLinear(0.5)) < 1e-4 && linear.w == 0.75;
}

test "billboard VS offsets the corner from its anchor and maps the tile" {
	let input: BillboardAttributes = {
		position: vec3f(1, 2, 3), size: vec2f(2, 4), anchor: vec2f(0, -0.5),
		tile: vec4f(0.25, 0.125, 0.5, 0.625), color: vec4f(1, 0.5, 0.25, 0.25), index: 2,
	};
	const top = billboardVs(input, upright());
	assert top.worldPosition.x == 2 && top.worldPosition.y == 6 && top.worldPosition.z == 3;
	assert top.uv.x == 0.5 && top.uv.y == 0.125 && top.towardCamera.z == 1;
	assert top.instanceColor.w == 0.25 && top.clip.y == 6 && top.clip.w == 1;
	input.index = 0;
	const bottom = billboardVs(input, upright());
	assert bottom.worldPosition.x == 0 && bottom.worldPosition.y == 2;
	assert bottom.uv.x == 0.25 && bottom.uv.y == 0.625;
}

test "billboard FS tints, lights in linear when asked, and premultiplies" {
	const input: BillboardFragmentInput = {
		worldPosition: vec3f(0, 0, 0), towardCamera: vec3f(0, 0, 2), uv: vec2f(0.5, 0.5),
		instanceColor: vec4f(0.5, 0.25, 1, 0.75),
	};
	let b = plainBillboard();
	const plain = billboardFs(input, b, { cutout: false, premultiplied: false });
	assert plain.x == 0.5 && plain.y == 0.25 && plain.z == 1 && plain.w == 0.75;
	const premultiplied = billboardFs(input, b, { cutout: true, premultiplied: true });
	assert Math.abs(premultiplied.x - 0.375) < 1e-4 && premultiplied.w == 0.75;
	b.billboardParams.billboard = vec4f(0, 1, 0, 0);
	const lit = billboardFs(input, b, { cutout: false, premultiplied: false });
	assert Math.abs(lit.x - channelToSrgb(channelToLinear(0.5) * 0.5)) < 1e-4;
	assert lit.w == 0.75;
}

test "billboard FS links to the billboard and the particle-visual VS alike" {
	const billboard: string = glslLinked(billboardFs, billboardVs);
	const visual: string = glslLinked(billboardFs, particleVisualVs);
	assert billboard == visual;
	assert billboard.includes("#ifdef PREMULTIPLIED") && billboard.includes("#ifdef CUTOUT");
}
