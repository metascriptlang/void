import { glsl } from "../shader/emit";
import { vec4f, mat4x4f } from "../shader/std";
import {
	ParticleVisualAttributes, VertexBindings, particleVisualVs, particleVisualPixelArtVs,
} from "../void3d/shader3d";

test "typed particle VS rotates asymmetric anchored tile in world camera basis" {
	let input: ParticleVisualAttributes = {
		root: vec4f(4, 5, 6, 3), shape: vec4f(1.125, 0.25, -0.5, 1.57079632679),
		tile: vec4f(0.25, 0.125, 0.5, 0.625), color: vec4f(1, 0.5, 0.25, 0.25), index: 2,
	};
	let bindings: VertexBindings = {
		vertexParams: {
			viewProj: mat4x4f(vec4f(1, 0, 0, 0), vec4f(0, 1, 0, 0),
				vec4f(0, 0, 1, 0), vec4f(0, 0, 0, 1)),
			cameraRight: vec4f(1, 0, 0, 0), cameraUp: vec4f(0, 1, 0, 0),
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
	assert source.includes("PARTICLE_CORNERS[gl_VertexIndex % 6]");
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
	assert source.includes("PARTICLE_CORNERS[gl_VertexIndex % 6]");
}
