// The campfire spike's passes on the M2 bridge: targets, materials, pipelines and frame order,
// all decided here; gpu3d.c only builds the sokol structs. Replaced by the Hibernal renderer in
// M3 and deleted with the spike in M6 (docs/VOID3D.md).
//
// Frame: scene pass (lit geometry, grass, flame) into color + normal/depth targets, post pass
// (outline + fog) into a low-res target, blit pass integer-scaling it to the swapchain.

import { Vec4, identity } from "../math/math3d";
import {
	Program,
	VertexLayout,
	PixelFormat,
	LoadAction,
	Filter,
	Wrap,
	VERTEX_UNIFORM_SLOT,
	VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_SLOT,
	LIGHT_UNIFORM_LENGTH,
	POST_UNIFORM_SLOT,
	POST_UNIFORM_LENGTH,
	BLIT_UNIFORM_SLOT,
	BLIT_UNIFORM_LENGTH,
	makeVertexBuffer,
	endPass,
	commit,
} from "../void3d/gpu3d";
import { RenderState, Face, Compare } from "../void3d/pass";
import { UniformBlock, NO_UNIFORMS } from "../void3d/material";
import {
	RenderTarget,
	ColorAttachment,
	DepthAttachment,
	TargetLayout,
	Sampler,
	NO_DEPTH,
	SWAPCHAIN_LAYOUT,
	layoutOf,
	beginPass,
	beginScreenPass,
} from "../void3d/target";
import {
	DrawContext,
	DrawItem,
	addMesh,
	addMaterial,
	reserveUniforms,
	writeUniforms,
	drawItems,
} from "../void3d/draw";

// What campfireScene.ms builds and uploads before the passes are set up.
export struct CampfireAssets {
	sceneBuffer: uint32;
	sceneVertexCount: int32;
	grassBuffer: uint32;
	grassCount: int32;
	grassTexture: uint32;
	flameTexture: uint32;
}

// Low-res target size and how it maps onto the framebuffer.
export struct CampfireView {
	lowWidth: int32;
	lowHeight: int32;
	pixelScale: float32;
	offsetX: float32;
	offsetY: float32;
}

const UNIFORM_CAPACITY: int32 = 64;

// Billboard quad corners (x across, y up), two triangles; instances supply root and size.
const CORNERS: Vec<float32> = [
	-0.5, 0.0, 0.5, 0.0, 0.5, 1.0,
	-0.5, 0.0, 0.5, 1.0, -0.5, 1.0,
];

// One triangle covering clip space.
const FULLSCREEN_TRIANGLE: Vec<float32> = [
	-1.0, -1.0, 3.0, -1.0, -1.0, 3.0,
];

const NO_GLOBALS: Vec<UniformBlock> = [];

let context: DrawContext = DrawContext.withUniformCapacity(UNIFORM_CAPACITY);
let colorTarget: RenderTarget = unallocated(PixelFormat.Rgba8, true);
let normalTarget: RenderTarget = unallocated(PixelFormat.Rgba8, true);
let depthTarget: RenderTarget = unallocated(PixelFormat.Depth, false);
let postTarget: RenderTarget = unallocated(PixelFormat.Rgba8, true);
let pointSampler: Sampler = { filter: Filter.Nearest, wrap: Wrap.Clamp, handle: 0 };

// Attachments point at the targets' views, so resizeTargets rewrites them in place.
const sceneColors: Vec<ColorAttachment> = new Array(2);
let sceneDepth: DepthAttachment = NO_DEPTH;
const postColors: Vec<ColorAttachment> = new Array(1);
let sceneLayout: TargetLayout = SWAPCHAIN_LAYOUT;
let postLayout: TargetLayout = SWAPCHAIN_LAYOUT;

const sceneItems: Vec<DrawItem> = [];
const postItems: Vec<DrawItem> = [];
const blitItems: Vec<DrawItem> = [];
const sceneGlobals: Vec<UniformBlock> = [];
const FLAME_ITEM: int32 = 2;
let firstFlameMesh: int32 = 0;
let postMaterial: int32 = 0;
let blitMaterial: int32 = 0;
let cameraBlock: UniformBlock = NO_UNIFORMS;
let lightBlock: UniformBlock = NO_UNIFORMS;
let blitBlock: UniformBlock = NO_UNIFORMS;
const blitValues: Vec<float32> = new Array(BLIT_UNIFORM_LENGTH);

function unallocated(format: PixelFormat, sampled: boolean): RenderTarget {
	return {
		width: 0,
		height: 0,
		format: format,
		sampled: sampled,
		image: 0,
		attachment: 0,
		texture: 0,
	};
}

function item(mesh: int32, material: int32): DrawItem {
	return { mesh: mesh, material: material, world: identity() };
}

function reserve(slot: int32, length: int32): UniformBlock {
	return try reserveUniforms(context, slot, length) catch NO_UNIFORMS;
}

export function setupCampfirePasses(
	assets: CampfireAssets,
	flameBuffers: Span<uint32>,
	postParams: Span<float32>,
): void {
	pointSampler = Sampler.create(Filter.Nearest, Wrap.Clamp);
	const cornerBuffer: uint32 = makeVertexBuffer(CORNERS);
	const fullscreenBuffer: uint32 = makeVertexBuffer(FULLSCREEN_TRIANGLE);

	// The spike draws unculled, depth-tested with LessEqual; the screen passes have no depth.
	const scene: RenderState = RenderState.defaults()
		.withCulling(Face.None)
		.withDepth(true, Compare.LessEqual);
	const screen: RenderState = RenderState.defaults()
		.withCulling(Face.None)
		.withDepth(false, Compare.Always);

	cameraBlock = reserve(VERTEX_UNIFORM_SLOT, VERTEX_UNIFORM_LENGTH);
	lightBlock = reserve(LIGHT_UNIFORM_SLOT, LIGHT_UNIFORM_LENGTH);
	const postBlock: UniformBlock = reserve(POST_UNIFORM_SLOT, POST_UNIFORM_LENGTH);
	blitBlock = reserve(BLIT_UNIFORM_SLOT, BLIT_UNIFORM_LENGTH);
	writeUniforms(context, postBlock, postParams);
	sceneGlobals.push(cameraBlock);
	sceneGlobals.push(lightBlock);

	const litMaterial: int32 = addMaterial(context, {
		program: Program.Lit,
		pass: scene,
		texture0: 0,
		texture1: 0,
		sampler: 0,
		uniforms: NO_UNIFORMS,
	});
	const grassMaterial: int32 = addMaterial(context, {
		program: Program.Billboard,
		pass: scene,
		texture0: assets.grassTexture,
		texture1: 0,
		sampler: pointSampler.handle,
		uniforms: NO_UNIFORMS,
	});
	const flameMaterial: int32 = addMaterial(context, {
		program: Program.Billboard,
		pass: scene,
		texture0: assets.flameTexture,
		texture1: 0,
		sampler: pointSampler.handle,
		uniforms: NO_UNIFORMS,
	});
	// Their textures are the low-res targets, filled in by resizeTargets.
	postMaterial = addMaterial(context, {
		program: Program.Post,
		pass: screen,
		texture0: 0,
		texture1: 0,
		sampler: pointSampler.handle,
		uniforms: postBlock,
	});
	blitMaterial = addMaterial(context, {
		program: Program.Blit,
		pass: screen,
		texture0: 0,
		texture1: 0,
		sampler: pointSampler.handle,
		uniforms: blitBlock,
	});

	const litMesh: int32 = addMesh(context, {
		layout: VertexLayout.Lit,
		vertexBuffer: assets.sceneBuffer,
		instanceBuffer: 0,
		vertexCount: assets.sceneVertexCount,
		instanceCount: 1,
	});
	const grassMesh: int32 = addMesh(context, {
		layout: VertexLayout.Billboard,
		vertexBuffer: cornerBuffer,
		instanceBuffer: assets.grassBuffer,
		vertexCount: 6,
		instanceCount: assets.grassCount,
	});
	firstFlameMesh = context.meshes.length as int32;
	for (const flameBuffer of flameBuffers) {
		addMesh(context, {
			layout: VertexLayout.Billboard,
			vertexBuffer: cornerBuffer,
			instanceBuffer: flameBuffer,
			vertexCount: 6,
			instanceCount: 1,
		});
	}
	const fullscreenMesh: int32 = addMesh(context, {
		layout: VertexLayout.Fullscreen,
		vertexBuffer: fullscreenBuffer,
		instanceBuffer: 0,
		vertexCount: 3,
		instanceCount: 1,
	});

	sceneItems.push(item(litMesh, litMaterial));
	sceneItems.push(item(grassMesh, grassMaterial));
	sceneItems.push(item(firstFlameMesh, flameMaterial));
	postItems.push(item(fullscreenMesh, postMaterial));
	blitItems.push(item(fullscreenMesh, blitMaterial));
}

function resizeTargets(width: int32, height: int32): void {
	if (width == colorTarget.width && height == colorTarget.height && colorTarget.image != 0) {
		return;
	}
	colorTarget = colorTarget.resized(width, height);
	normalTarget = normalTarget.resized(width, height);
	depthTarget = depthTarget.resized(width, height);
	postTarget = postTarget.resized(width, height);

	const sceneClear: Vec4 = { x: 0.02, y: 0.02, z: 0.06, w: 0.0 };
	// Normal target: an up-facing normal at the far plane where nothing is drawn.
	const normalClear: Vec4 = { x: 0.5, y: 1.0, z: 0.5, w: 1.0 };
	const unused: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 0.0 };
	sceneColors[0] = colorTarget.asColor(LoadAction.Clear, sceneClear);
	sceneColors[1] = normalTarget.asColor(LoadAction.Clear, normalClear);
	sceneDepth = depthTarget.asDepth(LoadAction.Clear, 1.0);
	postColors[0] = postTarget.asColor(LoadAction.DontCare, unused);
	sceneLayout = layoutOf(sceneColors, sceneDepth);
	postLayout = layoutOf(postColors, NO_DEPTH);

	context.materials[postMaterial].texture0 = colorTarget.texture;
	context.materials[postMaterial].texture1 = normalTarget.texture;
	context.materials[blitMaterial].texture0 = postTarget.texture;
}

export function renderCampfire(
	view: CampfireView,
	flameFrame: int32,
	vertexParams: Span<float32>,
	lightParams: Span<float32>,
): void {
	resizeTargets(view.lowWidth, view.lowHeight);
	writeUniforms(context, cameraBlock, vertexParams);
	writeUniforms(context, lightBlock, lightParams);
	blitValues[0] = view.pixelScale;
	blitValues[1] = view.pixelScale;
	blitValues[2] = view.offsetX;
	blitValues[3] = view.offsetY;
	writeUniforms(context, blitBlock, blitValues);
	sceneItems[FLAME_ITEM].mesh = firstFlameMesh + flameFrame;

	beginPass(sceneColors, sceneDepth);
	drawItems(context, sceneItems, sceneLayout, sceneGlobals);
	endPass();

	beginPass(postColors, NO_DEPTH);
	drawItems(context, postItems, postLayout, NO_GLOBALS);
	endPass();

	const black: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
	beginScreenPass(black);
	drawItems(context, blitItems, SWAPCHAIN_LAYOUT, NO_GLOBALS);
	endPass();
	commit();
}
