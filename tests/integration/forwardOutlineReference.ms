import { shaderProgram } from "../../src/shader/program";
import {
	Sampler,
	Texture2d,
	Vec2f,
	Vec4f,
	binding,
	builtin,
	cos,
	max,
	sin,
	textureDimensions,
	textureSample,
	vec2f,
	vec4f,
} from "../../src/shader/std";
import { programLayout } from "../../src/gpu/door";
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
	makeVertexBuffer,
} from "../../src/gpu/draw";

struct ReferenceAttributes {
	position: Vec2f;
}

struct ReferenceVaryings {
	@builtin(position) clip: Vec4f;
}

struct ReferenceInput {
	@builtin(position) position: Vec4f;
}

struct ReferenceParameters {
	referenceSize: Vec4f;
}

struct ReferenceBindings {
	@binding(0) referenceImage: Texture2d;
	@binding(0) referenceSampler: Sampler;
	@binding(0) referenceParameters: ReferenceParameters;
}

function outlineReferenceVs(input: ReferenceAttributes): ReferenceVaryings {
	return { clip: vec4f(input.position, 0.5, 1.0) };
}

function referenceCoverage(b: ReferenceBindings, coordinate: Vec2f): float32 {
	const coverage = textureSample(b.referenceImage, b.referenceSampler, coordinate).x;
	return b.referenceParameters.referenceSize.z > 0.5 ? 1.0 - coverage : coverage;
}

function outlineReferenceFs(input: ReferenceInput, b: ReferenceBindings): Vec4f {
	const size = b.referenceParameters.referenceSize;
	const inputUv = input.position.xy /
		vec2f(textureDimensions(b.referenceImage, b.referenceSampler, 0));
	const ownColor = referenceCoverage(b, inputUv);
	let maxAlpha: float32 = 0.0;
	let angle: float32 = 0.0;
	const step: float32 = 6.283185307179586 / 48.0;
	for (let i = 0; i < 48; i++) {
		angle += step;
		const displaced = vec2f(inputUv.x + size.x * cos(angle), inputUv.y + size.y * sin(angle));
		maxAlpha = max(maxAlpha, referenceCoverage(b, displaced));
	}
	const resultAlpha = max(maxAlpha, ownColor);
	const coverage = size.z > 0.5 ? 1.0 - resultAlpha : resultAlpha;
	return vec4f(coverage);
}

shaderProgram(outlineReference, outlineReferenceVs, outlineReferenceFs);

let referenceVertices: uint32 = 0;

export function outlineReferenceProgram(): int32 {
	return outlineReference;
}

export function outlineReferenceLayout(): int32 {
	return programLayout(outlineReference);
}

export function outlineReferenceDraw(
	pipeline: uint32, view: uint32, sampler: uint32,
	sizeX: float32, sizeY: float32, complement: float32,
): void {
	if (referenceVertices == 0) {
		const triangle: Vec<float32> = [-1.0, -1.0, 3.0, -1.0, -1.0, 3.0];
		referenceVertices = makeVertexBuffer(triangle);
	}
	applyPipeline(pipeline);
	let bindings: Vec<uint32> = [];
	for (let i = 0; i < BINDING_LENGTH; i++) { bindings.push(0); }
	bindings[BINDING_VERTEX_BUFFER] = referenceVertices;
	bindings[BINDING_VIEW] = view;
	bindings[BINDING_SAMPLER] = sampler;
	applyBindings(bindings);
	const parameters: Vec<float32> = [sizeX, sizeY, complement, 0.0];
	applyUniforms(0, parameters);
	draw(0, 3, 1);
}

export function outlineReferenceClose(): void {
	if (referenceVertices != 0) { destroyBuffer(referenceVertices); }
	referenceVertices = 0;
}
