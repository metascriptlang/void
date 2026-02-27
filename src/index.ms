// Void Engine — Interactive Textured Cube (WebGPU)
// WASD camera orbit, frame-rate independent, window resize

import {
	GPUInstance, GPUAdapter, GPUDevice, GPUCanvasContext,
	GPURenderPipeline, GPUShaderModule, GPUBuffer,
	GPUBindGroupLayout, GPUBindGroup, GPUPipelineLayout,
	GPUTexture, GPUTextureView, GPUSampler,
	createGPUInstance
} from "./gpu/dawn"

import { loadImage, imageWidth, imageHeight, freeImage } from "./assets/image"

import {
	initPlatform, quitPlatform, createWindow, destroyWindow,
	pollEvent, eventKey, eventWidth, eventHeight,
	getTicksNS, EventType, Key
} from "./platform/sdl"

import {
	GPUBufferUsage, GPUTextureUsage, GPUShaderStage,
	VertexFormat, IndexFormat, CullMode, TextureFormat,
	AddressMode, FilterMode
} from "./gpu/constants"

import { setPerspective, setLookAt, setRotateY, multiplyMVP, getMVP, sinf, cosf } from "./math/mat4"

const SHADER = `
struct Uniforms {
  mvp: mat4x4f,
};
@group(0) @binding(0) var<uniform> u: Uniforms;
@group(1) @binding(0) var tex: texture_2d<f32>;
@group(1) @binding(1) var samp: sampler;

struct VOut {
  @builtin(position) pos: vec4f,
  @location(0) uv: vec2f,
};

@vertex fn vs(@location(0) pos: vec3f, @location(1) uv: vec2f) -> VOut {
  return VOut(u.mvp * vec4f(pos, 1), uv);
}

@fragment fn fs(in: VOut) -> @location(0) vec4f {
  return textureSample(tex, samp, in.uv);
}
`;

async function main(): int32 {
	if (!initPlatform()) {
		console.log("Failed to init platform");
		return 1;
	}

	var WIDTH: uint32 = 800;
	var HEIGHT: uint32 = 600;

	const window = createWindow("Void Engine", WIDTH as int32, HEIGHT as int32);
	const gpu = createGPUInstance();
	defer gpu.release();
	const context = gpu.createSurface(window);
	defer context.release();
	const adapter = gpu.requestAdapter(context);
	defer adapter.release();
	const device = adapter.requestDevice();
	defer device.release();

	context.configure({ device: device, format: "bgra8unorm", width: WIDTH, height: HEIGHT });

	const shader = device.createShaderModule({ code: SHADER });
	defer shader.release();

	// --- Vertex buffer: 24 vertices (4 per face), each pos(3f) + uv(2f) = 5 floats ---
	// 24 * 5 * 4 = 480 bytes
	const vbUsage: uint32 = (GPUBufferUsage.VERTEX as uint32) | (GPUBufferUsage.COPY_DST as uint32);
	const vertexBuffer = device.createBuffer({
		size: 480,
		usage: vbUsage,
		mappedAtCreation: 1,
	});
	defer vertexBuffer.release();

	const vMap = vertexBuffer.getMappedRange(0, 480);
	// Front face (z = +0.5)
	vertexBuffer.mappedWriteFloat(vMap, 0, -0.5); vertexBuffer.mappedWriteFloat(vMap, 1, -0.5); vertexBuffer.mappedWriteFloat(vMap, 2,  0.5); vertexBuffer.mappedWriteFloat(vMap, 3, 0.0); vertexBuffer.mappedWriteFloat(vMap, 4, 1.0);
	vertexBuffer.mappedWriteFloat(vMap, 5,  0.5); vertexBuffer.mappedWriteFloat(vMap, 6, -0.5); vertexBuffer.mappedWriteFloat(vMap, 7,  0.5); vertexBuffer.mappedWriteFloat(vMap, 8, 1.0); vertexBuffer.mappedWriteFloat(vMap, 9, 1.0);
	vertexBuffer.mappedWriteFloat(vMap, 10, 0.5); vertexBuffer.mappedWriteFloat(vMap, 11, 0.5); vertexBuffer.mappedWriteFloat(vMap, 12, 0.5); vertexBuffer.mappedWriteFloat(vMap, 13, 1.0); vertexBuffer.mappedWriteFloat(vMap, 14, 0.0);
	vertexBuffer.mappedWriteFloat(vMap, 15,-0.5); vertexBuffer.mappedWriteFloat(vMap, 16, 0.5); vertexBuffer.mappedWriteFloat(vMap, 17, 0.5); vertexBuffer.mappedWriteFloat(vMap, 18, 0.0); vertexBuffer.mappedWriteFloat(vMap, 19, 0.0);
	// Back face (z = -0.5)
	vertexBuffer.mappedWriteFloat(vMap, 20, 0.5); vertexBuffer.mappedWriteFloat(vMap, 21,-0.5); vertexBuffer.mappedWriteFloat(vMap, 22,-0.5); vertexBuffer.mappedWriteFloat(vMap, 23, 0.0); vertexBuffer.mappedWriteFloat(vMap, 24, 1.0);
	vertexBuffer.mappedWriteFloat(vMap, 25,-0.5); vertexBuffer.mappedWriteFloat(vMap, 26,-0.5); vertexBuffer.mappedWriteFloat(vMap, 27,-0.5); vertexBuffer.mappedWriteFloat(vMap, 28, 1.0); vertexBuffer.mappedWriteFloat(vMap, 29, 1.0);
	vertexBuffer.mappedWriteFloat(vMap, 30,-0.5); vertexBuffer.mappedWriteFloat(vMap, 31, 0.5); vertexBuffer.mappedWriteFloat(vMap, 32,-0.5); vertexBuffer.mappedWriteFloat(vMap, 33, 1.0); vertexBuffer.mappedWriteFloat(vMap, 34, 0.0);
	vertexBuffer.mappedWriteFloat(vMap, 35, 0.5); vertexBuffer.mappedWriteFloat(vMap, 36, 0.5); vertexBuffer.mappedWriteFloat(vMap, 37,-0.5); vertexBuffer.mappedWriteFloat(vMap, 38, 0.0); vertexBuffer.mappedWriteFloat(vMap, 39, 0.0);
	// Top face (y = +0.5)
	vertexBuffer.mappedWriteFloat(vMap, 40,-0.5); vertexBuffer.mappedWriteFloat(vMap, 41, 0.5); vertexBuffer.mappedWriteFloat(vMap, 42, 0.5); vertexBuffer.mappedWriteFloat(vMap, 43, 0.0); vertexBuffer.mappedWriteFloat(vMap, 44, 1.0);
	vertexBuffer.mappedWriteFloat(vMap, 45, 0.5); vertexBuffer.mappedWriteFloat(vMap, 46, 0.5); vertexBuffer.mappedWriteFloat(vMap, 47, 0.5); vertexBuffer.mappedWriteFloat(vMap, 48, 1.0); vertexBuffer.mappedWriteFloat(vMap, 49, 1.0);
	vertexBuffer.mappedWriteFloat(vMap, 50, 0.5); vertexBuffer.mappedWriteFloat(vMap, 51, 0.5); vertexBuffer.mappedWriteFloat(vMap, 52,-0.5); vertexBuffer.mappedWriteFloat(vMap, 53, 1.0); vertexBuffer.mappedWriteFloat(vMap, 54, 0.0);
	vertexBuffer.mappedWriteFloat(vMap, 55,-0.5); vertexBuffer.mappedWriteFloat(vMap, 56, 0.5); vertexBuffer.mappedWriteFloat(vMap, 57,-0.5); vertexBuffer.mappedWriteFloat(vMap, 58, 0.0); vertexBuffer.mappedWriteFloat(vMap, 59, 0.0);
	// Bottom face (y = -0.5)
	vertexBuffer.mappedWriteFloat(vMap, 60,-0.5); vertexBuffer.mappedWriteFloat(vMap, 61,-0.5); vertexBuffer.mappedWriteFloat(vMap, 62,-0.5); vertexBuffer.mappedWriteFloat(vMap, 63, 0.0); vertexBuffer.mappedWriteFloat(vMap, 64, 1.0);
	vertexBuffer.mappedWriteFloat(vMap, 65, 0.5); vertexBuffer.mappedWriteFloat(vMap, 66,-0.5); vertexBuffer.mappedWriteFloat(vMap, 67,-0.5); vertexBuffer.mappedWriteFloat(vMap, 68, 1.0); vertexBuffer.mappedWriteFloat(vMap, 69, 1.0);
	vertexBuffer.mappedWriteFloat(vMap, 70, 0.5); vertexBuffer.mappedWriteFloat(vMap, 71,-0.5); vertexBuffer.mappedWriteFloat(vMap, 72, 0.5); vertexBuffer.mappedWriteFloat(vMap, 73, 1.0); vertexBuffer.mappedWriteFloat(vMap, 74, 0.0);
	vertexBuffer.mappedWriteFloat(vMap, 75,-0.5); vertexBuffer.mappedWriteFloat(vMap, 76,-0.5); vertexBuffer.mappedWriteFloat(vMap, 77, 0.5); vertexBuffer.mappedWriteFloat(vMap, 78, 0.0); vertexBuffer.mappedWriteFloat(vMap, 79, 0.0);
	// Right face (x = +0.5)
	vertexBuffer.mappedWriteFloat(vMap, 80, 0.5); vertexBuffer.mappedWriteFloat(vMap, 81,-0.5); vertexBuffer.mappedWriteFloat(vMap, 82, 0.5); vertexBuffer.mappedWriteFloat(vMap, 83, 0.0); vertexBuffer.mappedWriteFloat(vMap, 84, 1.0);
	vertexBuffer.mappedWriteFloat(vMap, 85, 0.5); vertexBuffer.mappedWriteFloat(vMap, 86,-0.5); vertexBuffer.mappedWriteFloat(vMap, 87,-0.5); vertexBuffer.mappedWriteFloat(vMap, 88, 1.0); vertexBuffer.mappedWriteFloat(vMap, 89, 1.0);
	vertexBuffer.mappedWriteFloat(vMap, 90, 0.5); vertexBuffer.mappedWriteFloat(vMap, 91, 0.5); vertexBuffer.mappedWriteFloat(vMap, 92,-0.5); vertexBuffer.mappedWriteFloat(vMap, 93, 1.0); vertexBuffer.mappedWriteFloat(vMap, 94, 0.0);
	vertexBuffer.mappedWriteFloat(vMap, 95, 0.5); vertexBuffer.mappedWriteFloat(vMap, 96, 0.5); vertexBuffer.mappedWriteFloat(vMap, 97, 0.5); vertexBuffer.mappedWriteFloat(vMap, 98, 0.0); vertexBuffer.mappedWriteFloat(vMap, 99, 0.0);
	// Left face (x = -0.5)
	vertexBuffer.mappedWriteFloat(vMap, 100,-0.5); vertexBuffer.mappedWriteFloat(vMap, 101,-0.5); vertexBuffer.mappedWriteFloat(vMap, 102,-0.5); vertexBuffer.mappedWriteFloat(vMap, 103, 0.0); vertexBuffer.mappedWriteFloat(vMap, 104, 1.0);
	vertexBuffer.mappedWriteFloat(vMap, 105,-0.5); vertexBuffer.mappedWriteFloat(vMap, 106,-0.5); vertexBuffer.mappedWriteFloat(vMap, 107, 0.5); vertexBuffer.mappedWriteFloat(vMap, 108, 1.0); vertexBuffer.mappedWriteFloat(vMap, 109, 1.0);
	vertexBuffer.mappedWriteFloat(vMap, 110,-0.5); vertexBuffer.mappedWriteFloat(vMap, 111, 0.5); vertexBuffer.mappedWriteFloat(vMap, 112, 0.5); vertexBuffer.mappedWriteFloat(vMap, 113, 1.0); vertexBuffer.mappedWriteFloat(vMap, 114, 0.0);
	vertexBuffer.mappedWriteFloat(vMap, 115,-0.5); vertexBuffer.mappedWriteFloat(vMap, 116, 0.5); vertexBuffer.mappedWriteFloat(vMap, 117,-0.5); vertexBuffer.mappedWriteFloat(vMap, 118, 0.0); vertexBuffer.mappedWriteFloat(vMap, 119, 0.0);
	vertexBuffer.unmap();

	// --- Index buffer: 6 faces * 2 triangles * 3 = 36 indices (uint16) = 72 bytes ---
	const ibUsage: uint32 = (GPUBufferUsage.INDEX as uint32) | (GPUBufferUsage.COPY_DST as uint32);
	const indexBuffer = device.createBuffer({
		size: 72,
		usage: ibUsage,
		mappedAtCreation: 1,
	});
	defer indexBuffer.release();

	const iMap = indexBuffer.getMappedRange(0, 72);
	var fi: uint32 = 0;
	var vi: uint16 = 0;
	while (fi < 6) {
		const base: uint32 = fi * 6;
		indexBuffer.mappedWriteU16(iMap, base + 0, vi + 0);
		indexBuffer.mappedWriteU16(iMap, base + 1, vi + 1);
		indexBuffer.mappedWriteU16(iMap, base + 2, vi + 2);
		indexBuffer.mappedWriteU16(iMap, base + 3, vi + 0);
		indexBuffer.mappedWriteU16(iMap, base + 4, vi + 2);
		indexBuffer.mappedWriteU16(iMap, base + 5, vi + 3);
		fi = fi + 1;
		vi = vi + 4;
	}
	indexBuffer.unmap();

	// --- Uniform buffer: 64 bytes (mat4x4f) ---
	const ubUsage: uint32 = (GPUBufferUsage.UNIFORM as uint32) | (GPUBufferUsage.COPY_DST as uint32);
	const uniformBuffer = device.createBuffer({
		size: 64,
		usage: ubUsage,
		mappedAtCreation: 0,
	});
	defer uniformBuffer.release();

	// --- Load texture from PNG ---
	const imgData = await loadImage("assets/test.png", 4);
	const imgW: uint32 = imageWidth() as uint32;
	const imgH: uint32 = imageHeight() as uint32;
	const imgBytes: uint64 = (imgW * imgH * 4) as uint64;
	const texUsage: uint32 = (GPUTextureUsage.TEXTURE_BINDING as uint32) | (GPUTextureUsage.COPY_DST as uint32);
	const loadedTexture = device.createTexture(imgW, imgH, TextureFormat.RGBA8_UNORM as uint32, texUsage, 1);
	defer loadedTexture.release();
	device.getQueue().writeTexture(loadedTexture, imgData, imgBytes, imgW * 4, imgW, imgH);
	freeImage(imgData);

	const texView = loadedTexture.createView();
	defer texView.release();

	// --- Sampler ---
	const sampler = device.createSampler(
		AddressMode.REPEAT as uint32,
		FilterMode.LINEAR as uint32,
		FilterMode.LINEAR as uint32
	);
	defer sampler.release();

	// --- Bind group 0: uniform buffer (MVP) ---
	const visVertex: uint32 = GPUShaderStage.VERTEX as uint32;
	const uniformBGL = device.createBindGroupLayout1Buf(0, visVertex, 64);
	defer uniformBGL.release();
	const uniformBG = device.createBindGroup1Buf(uniformBGL, 0, uniformBuffer, 0, 64);
	defer uniformBG.release();

	// --- Bind group 1: texture + sampler ---
	const visFragment: uint32 = GPUShaderStage.FRAGMENT as uint32;
	const texSampBGL = device.createBindGroupLayout1Tex1Samp(0, visFragment, 1, visFragment);
	defer texSampBGL.release();
	const texSampBG = device.createBindGroup1Tex1Samp(texSampBGL, 0, texView, 1, sampler);
	defer texSampBG.release();

	// --- Pipeline layout (2 bind groups) ---
	const pipelineLayout = device.createPipelineLayout2BG(uniformBGL, texSampBGL);
	defer pipelineLayout.release();

	// --- Pipeline: pos(vec3f) + uv(vec2f), depth, back-face culling, no blend ---
	const pipeline = device.createRenderPipelineExt2(
		shader, "vs", "fs",
		pipelineLayout,
		20, 2,
		VertexFormat.FLOAT32X3 as uint32, 0, 0,
		VertexFormat.FLOAT32X2 as uint32, 12, 1,
		0, 0, 0,
		1,
		CullMode.BACK as uint32,
		0,
		0, 0, 0, 0, 0, 0
	);
	defer pipeline.release();

	// --- Depth texture (mutable for resize) ---
	var depthTexture = device.createDepthTexture(WIDTH, HEIGHT);
	var depthView = depthTexture.createView();

	// --- Camera state ---
	var camAngle: float32 = 0.0;   // orbit angle around Y
	var camDist: float32 = 3.0;    // distance from origin
	var camHeight: float32 = 1.5;  // eye Y position

	// --- Setup initial projection ---
	setPerspective(1.0472, (WIDTH as float32) / (HEIGHT as float32), 0.1, 100.0);

	// --- Input state (0 = not pressed, 1 = pressed) ---
	var keyW: int32 = 0;
	var keyA: int32 = 0;
	var keyS: int32 = 0;
	var keyD: int32 = 0;
	var keyQ: int32 = 0;
	var keyE: int32 = 0;

	var angle: float32 = 0.0;
	var lastTime: uint64 = getTicksNS();
	var running: int32 = 1;

	while (running === 1) {
		// --- Process events ---
		var evt: int32 = pollEvent();
		while (evt !== 0) {
			if (evt === EventType.QUIT) {
				running = 0;
			}
			if (evt === EventType.KEY_DOWN) {
				const k: int32 = eventKey();
				if (k === Key.ESCAPE) running = 0;
				if (k === Key.W) keyW = 1;
				if (k === Key.A) keyA = 1;
				if (k === Key.S) keyS = 1;
				if (k === Key.D) keyD = 1;
				if (k === Key.Q) keyQ = 1;
				if (k === Key.E) keyE = 1;
			}
			if (evt === EventType.KEY_UP) {
				const k: int32 = eventKey();
				if (k === Key.W) keyW = 0;
				if (k === Key.A) keyA = 0;
				if (k === Key.S) keyS = 0;
				if (k === Key.D) keyD = 0;
				if (k === Key.Q) keyQ = 0;
				if (k === Key.E) keyE = 0;
			}
			if (evt === EventType.WINDOW_RESIZE) {
				WIDTH = eventWidth() as uint32;
				HEIGHT = eventHeight() as uint32;
				if (WIDTH > 0 && HEIGHT > 0) {
					context.configure({ device: device, format: "bgra8unorm", width: WIDTH, height: HEIGHT });
					depthView.release();
					depthTexture.release();
					depthTexture = device.createDepthTexture(WIDTH, HEIGHT);
					depthView = depthTexture.createView();
					setPerspective(1.0472, (WIDTH as float32) / (HEIGHT as float32), 0.1, 100.0);
				}
			}
			evt = pollEvent();
		}

		// --- Frame timing ---
		const now: uint64 = getTicksNS();
		const dtNS: uint64 = now - lastTime;
		lastTime = now;
		const dt: float32 = (dtNS as float32) / 1000000000.0;

		// --- Update camera ---
		if (keyA === 1) camAngle = camAngle - dt * 2.0;
		if (keyD === 1) camAngle = camAngle + dt * 2.0;
		if (keyW === 1) camDist = camDist - dt * 3.0;
		if (keyS === 1) camDist = camDist + dt * 3.0;
		if (keyQ === 1) camHeight = camHeight - dt * 2.0;
		if (keyE === 1) camHeight = camHeight + dt * 2.0;

		// Clamp distance
		if (camDist < 1.0) camDist = 1.0;
		if (camDist > 10.0) camDist = 10.0;

		const eyeX: float32 = sinf(camAngle) * camDist;
		const eyeZ: float32 = cosf(camAngle) * camDist;
		setLookAt(eyeX, camHeight, eyeZ, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0);

		// --- Rotate cube ---
		angle = angle + dt * 1.0;
		setRotateY(angle);
		multiplyMVP();

		const mvpPtr = getMVP();
		device.getQueue().writeBuffer(uniformBuffer, 0, mvpPtr, 64);

		// --- Render ---
		const texture = context.getCurrentTexture();
		if (texture._handle === null) continue;

		const view = texture.createView();
		const encoder = device.createCommandEncoder();
		const pass = encoder.beginRenderPassDepth({
			colorAttachments: [{
				view: view,
				clearR: 0.05, clearG: 0.05, clearB: 0.15, clearA: 1.0,
				loadOp: "clear",
				storeOp: "store"
			}]
		}, depthView);

		pass.setPipeline(pipeline);
		pass.setBindGroup(0, uniformBG);
		pass.setBindGroup(1, texSampBG);
		pass.setVertexBuffer(0, vertexBuffer);
		pass.setIndexBuffer(indexBuffer, IndexFormat.UINT16 as uint32);
		pass.drawIndexed(36);
		pass.end();

		const cmd = encoder.finish();
		device.getQueue().submit([cmd]);
		context.present();

		cmd.release();
		encoder.release();
		view.release();
	}

	depthView.release();
	depthTexture.release();
	destroyWindow(window);
	quitPlatform();

	return 0;
}

main();
