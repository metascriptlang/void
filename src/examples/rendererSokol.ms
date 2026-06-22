// Void — cube renderer (platform-independent). All GPU sequencing lives here;
// src/sokol/{gpu.ms,gpu.wms} are thin sokol wrappers. Used by mainSokol.ms.

import {
	gfxSetup, fbWidth, fbHeight,
	makeVertexBuffer, makeIndexBuffer, makeCubeShader, makePipeline,
	makeImage, makeView, makeSampler,
	beginPass, applyPipeline, applyBindings, applyMvp, draw, endPass, commit,
} from "../sokol/gpu";
import { setPerspective, setLookAt, setRotateY, multiplyMVP, getMVP } from "../math/mat4";
import { loadImageSync, imageWidth, imageHeight, freeImage } from "../assets/image";
import { cubeVertices, cubeIndices, cubeVertexBytes, cubeIndexBytes, cubeIndexCount } from "./cubedata";

let vbuf: uint32 = 0;
let ibuf: uint32 = 0;
let pipeline: uint32 = 0;
let texView: uint32 = 0;
let sampler: uint32 = 0;
let angle: float32 = 0.0;

export function initRenderer(): void {
	gfxSetup();
	vbuf = makeVertexBuffer(cubeVertices[0], cubeVertexBytes);
	ibuf = makeIndexBuffer(cubeIndices[0], cubeIndexBytes);
	pipeline = makePipeline(makeCubeShader());

	const img = loadImageSync("assets/test.png", 4);
	texView = makeView(makeImage(img, imageWidth(), imageHeight()));
	freeImage(img);
	sampler = makeSampler();
}

export function renderFrame(): void {
	angle = angle + 0.02;
	const aspect: float32 = (fbWidth() as float32) / (fbHeight() as float32);
	setPerspective(1.0472, aspect, 0.1, 100.0);
	setLookAt(2.5, 1.5, 3.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0);
	setRotateY(angle);
	multiplyMVP();

	beginPass(0.05, 0.05, 0.15, 1.0);
	applyPipeline(pipeline);
	applyBindings(vbuf, ibuf, texView, sampler);
	applyMvp(getMVP());
	draw(cubeIndexCount);
	endPass();
	commit();
}
