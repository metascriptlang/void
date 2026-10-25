// expect attachment.afterRelease: gpu door: beginPass on color attachment 0, whose view
// expect attachment.otherContext: gpu door: beginPass on color attachment 0 of GPU context 2; the context is now 1
// expect attachment.withoutView: gpu door: beginPass on color attachment 0, which has no view
// expect depth.withoutView: gpu door: beginPass on the depth attachment, which has no view
// expect pass.commitInside: gpu door: commit with a pass already open; endPass ends it
// expect pass.fiveColors: gpu door: beginPass takes at most 4 color attachments, given 5
// expect pass.foreignScreenTwice: gpu door: beginScreenPass with a pass already open; endPass ends it
// expect pass.foreignEndNone: gpu door: endPass with no pass open
// expect pass.screenTwice: gpu door: beginScreenPass with a pass already open; endPass ends it
// expect pass.targetTwice: gpu door: beginPass with a pass already open; endPass ends it
// expect sampler.afterRelease: gpu door: asHandle on a sampler that was released
// expect sampler.empty: gpu door: asHandle on a sampler with no handle
// expect target.closedTwice: gpu door: close on a render target that was closed
// expect target.otherContext: gpu door: asColor on a render target of GPU context 2; the context is now 1
// expect target.resizedAfterClose: gpu door: resize on a render target that was closed
// expect target.textureAfterClose: gpu door: asTexture on a render target that was closed
// expect target.textureUnallocated: gpu door: asTexture on a render target with no GPU objects
// expect target.viewDestroyed: gpu door: asTexture on a render target whose view
// expect pipelines.closedInside: gpu door: closePipelines with a pass already open; endPass ends it
// expect pipelines.closedThroughAlias: gpu door: pipelineFor on a pipeline cache that was closed
// expect pipelines.releasedInside: gpu door: releasePipelines with a pass already open; endPass ends it
// expect bindings.short: gpu door: applyBindings descriptor holds 17 of 18 words
// expect drawItem.foreignTexture: void3d: drawItem with a material whose texture is not the one it was added with
// expect drawItem.staleTexture: void3d: drawItem with a material whose texture is not the one it was added with
// expect drawItem.texturePastTable: void3d: drawItem with a material whose texture is not the one it was added with
// expect door.endPassNone: gpu door: endPass with no pass open
// expect door.fiveColorLayout: gpu door: layoutOf takes at most 4 color attachments, given 5
// expect door.unknownLayout: gpu door: unregistered layout id
// expect door.unknownProgram: gpu door: unregistered program id
// expect pipelines.closedTwice: gpu door: closePipelines on a pipeline cache that was closed
// expect pipelines.releasedAfterClose: gpu door: releasePipelines on a pipeline cache that was closed
// expect pipelines.shaderAfterClose: gpu door: shaderFor on a pipeline cache that was closed
// expect texture.closedAfterDetach: gpu door: close on a texture that was closed
// expect texture.detachedTwice: gpu door: detach on a texture that was closed
// expect view.idAfterRecreate: void: voidViewResize: view 33 was destroyed; a view id names one view only
// expect block.neverApplied: gpu door: draw with a pipeline that declares a uniform block at slot
// expect block.afterPipelineChange: gpu door: draw with a pipeline that declares a uniform block at slot
import { argv } from "std/process";
import { gfxSetup, viewCreate, viewResize, viewDestroy, ViewId } from "../../../src/sokol/gpu";
import { Vec4, identity } from "../../../src/math/math3d";
import { FilterMode, Wrap, Face, RenderState } from "../../../src/gpu/state";
import {
	PixelFormat,
	LoadAction,
	StoreAction,
	UNIFORM_SLOTS,
	destroyView,
	commit,
	endPass,
	layoutFloats,
	programLayout,
	uniformSlotMask,
} from "../../../src/gpu/door";
import { doorEndPass, doorBeginScreenPass } from "../../../src/gpu/door.h";
import {
	RenderTarget,
	Sampler,
	ColorAttachment,
	TargetLayout,
	NO_DEPTH,
	SWAPCHAIN_LAYOUT,
	beginPass,
	beginScreenPass,
	layoutOf,
} from "../../../src/gpu/target";
import {
	PipelineCache,
	closePipelines,
	releasePipelines,
	shaderFor,
	pipelineFor as doorPipelineFor,
} from "../../../src/gpu/pipeline";
import { Texture } from "../../../src/gpu/texture";
import { BINDING_LENGTH as GPU3D_BINDING_LENGTH } from "../../../src/gpu/draw";
import {
	Program,
	ProgramKey,
	VertexLayout,
	MATERIAL_UNIFORM_LENGTH,
	doorProgram,
	vertexLayoutOf,
	uniformBlockLength,
	applyPipeline,
	applyUniforms,
	applyBindings,
	draw,
	pipelineFor,
} from "../../../src/void3d/gpu3d";
import { Material, Phase, UniformBlock } from "../../../src/void3d/material";
import { TextureData, TextureId } from "../../../src/void3d/texture";
import {
	DrawContext,
	DrawItem,
	GpuMesh,
	addMesh,
	addMaterial,
	addTexture,
	releaseTexture,
	drawItem,
} from "../../../src/void3d/draw";
@include("../../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const RED: Vec4 = { x: 1.0, y: 0.0, z: 0.0, w: 1.0 };
const BLACK: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
const LIT: ProgramKey = ProgramKey.of(Program.Lit);
const NO_GLOBALS: Vec<UniformBlock> = [];
let chosen: string = (argv.length as int32) > 1 ? argv[1] : "";

function copyPipeline(cache: PipelineCache): uint32 {
	return pipelineFor(
		cache,
		ProgramKey.of(Program.Copy),
		VertexLayout.Fullscreen,
		false,
		RenderState.defaults(),
		SWAPCHAIN_LAYOUT,
	);
}

function litPipeline(cache: PipelineCache, state: RenderState): uint32 {
	return doorPipelineFor(
		cache, doorProgram(LIT), vertexLayoutOf(LIT), true, state, SWAPCHAIN_LAYOUT,
	);
}

function applyEveryBlock(): void {
	const mask: uint32 = uniformSlotMask(doorProgram(LIT));
	for (let slot = 0; slot < UNIFORM_SLOTS; slot++) {
		if ((mask & ((1 as uint32) << (slot as uint32))) == 0) { continue; }
		let zeros: Vec<float32> = new Array(uniformBlockLength(LIT, slot));
		for (let i = 0; i < (zeros.length as int32); i++) { zeros[i] = 0.0; }
		applyUniforms(slot, zeros);
	}
}

function texel(): TextureData {
	const pixels: Vec<uint32> = [0xff0000ff as uint32];
	return { pixels: pixels, width: 1, height: 1, filter: FilterMode.Nearest, wrap: Wrap.Clamp };
}

function textureOf(context: DrawContext): TextureId {
	const made = addTexture(context, texel());
	if (!made.ok) { unreachable; }
	return made.value;
}

function texturedDraw(name: string): boolean {
	if (name != "drawItem.foreignTexture" && name != "drawItem.staleTexture" &&
		name != "drawItem.texturePastTable") {
		return false;
	}
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	let other: DrawContext = DrawContext.withUniformCapacity(0);
	const mesh = addMesh(context, GpuMesh.fullscreen(0, 3));
	const own: TextureId = textureOf(context);
	const textured: Material = {
		...Material.plain(Program.LitTextured, RenderState.defaults(), Phase.Opaque),
		texture: own,
	};
	const material = addMaterial(context, textured);
	if (!mesh.ok || !material.ok) { unreachable; }
	if (name == "drawItem.foreignTexture") {
		context.materials[material.value.index].texture = textureOf(other);
	} else if (name == "drawItem.staleTexture") {
		const gone: TextureId = textureOf(context);
		if (!releaseTexture(context, gone).ok) { unreachable; }
		context.materials[material.value.index].texture = gone;
	} else {
		context.materials[material.value.index].texture =
			{ store: context.serial, index: 99, generation: 1 };
	}
	const item: DrawItem = { mesh: mesh.value, material: material.value, world: identity() };
	drawItem(context, item, ProgramKey.of(Program.LitTextured), SWAPCHAIN_LAYOUT, NO_GLOBALS);
	return true;
}

function plainCase(name: string): boolean {
	if (name == "door.endPassNone") {
		endPass();
	} else if (name == "door.fiveColorLayout") {
		let colors: Vec<ColorAttachment> = [];
		for (let i = 0; i < 5; i++) {
			colors.push({
				view: 0, format: PixelFormat.Rgba8, load: LoadAction.Clear,
				clear: { x: 0.0, y: 0.0, z: 0.0, w: 0.0 },
			});
		}
		const _layout: TargetLayout = layoutOf(colors, NO_DEPTH);
	} else if (name == "door.unknownLayout") {
		const floats: int32 = layoutFloats(1000000, 0);
		console.log(`unknown layout returned ${floats} floats`);
	} else if (name == "door.unknownProgram") {
		const _layout: int32 = programLayout(-1);
	} else if (name == "pipelines.closedTwice") {
		const cache: PipelineCache = PipelineCache.empty();
		closePipelines(cache);
		closePipelines(cache);
	} else if (name == "pipelines.releasedAfterClose") {
		const cache: PipelineCache = PipelineCache.empty();
		closePipelines(cache);
		releasePipelines(cache);
	} else if (name == "pipelines.shaderAfterClose") {
		const cache: PipelineCache = PipelineCache.empty();
		closePipelines(cache);
		const _shader = shaderFor(cache, 0);
	} else if (name == "texture.closedAfterDetach") {
		const texture: Texture = Texture.adopt(3, 9, 2, 2);
		const _handles = texture.detach();
		texture.close();
	} else if (name == "texture.detachedTwice") {
		const texture: Texture = Texture.adopt(3, 9, 2, 2);
		const _first = texture.detach();
		const _second = texture.detach();
	} else if (name == "view.idAfterRecreate") {
		const first: ViewId = viewCreate(0 as int64, 64 as int32, 64 as int32, 1.0);
		viewDestroy(first);
		const _second: ViewId = viewCreate(0 as int64, 64 as int32, 64 as int32, 1.0);
		viewResize(first, 32 as int32, 32 as int32, 1.0);
	} else {
		return false;
	}
	return true;
}

function attachmentCase(name: string): boolean {
	if (name == "attachment.afterRelease") {
		let target: RenderTarget = RenderTarget.allocate(8, 8, PixelFormat.Rgba8, false);
		const kept: Vec<ColorAttachment> = [target.asColor(LoadAction.Clear, RED)];
		target.close();
		beginPass(kept, NO_DEPTH);
	} else if (name == "attachment.otherContext") {
		const target: RenderTarget = RenderTarget.allocate(8, 8, PixelFormat.Rgba8, false);
		const color: ColorAttachment = target.asColor(LoadAction.Clear, RED);
		const stale: Vec<ColorAttachment> = [{ ...color, generation: color.generation + 1 }];
		beginPass(stale, NO_DEPTH);
	} else if (name == "attachment.withoutView") {
		const target: RenderTarget = RenderTarget.unallocated(PixelFormat.Rgba8, false);
		const colors: Vec<ColorAttachment> = [target.asColor(LoadAction.Clear, RED)];
		beginPass(colors, NO_DEPTH);
	} else if (name == "depth.withoutView") {
		const color: RenderTarget = RenderTarget.allocate(8, 8, PixelFormat.Rgba8, false);
		const depth: RenderTarget = RenderTarget.unallocated(PixelFormat.Depth, false);
		const colors: Vec<ColorAttachment> = [color.asColor(LoadAction.Clear, RED)];
		beginPass(colors, depth.asDepth(LoadAction.Clear, 1.0, StoreAction.DontCare));
	} else {
		return false;
	}
	return true;
}

function passCase(name: string): boolean {
	if (name == "pass.commitInside") {
		beginScreenPass(BLACK);
		commit();
	} else if (name == "pass.fiveColors") {
		let colors: Vec<ColorAttachment> = [];
		for (let i = 0; i < 5; i++) {
			const target: RenderTarget = RenderTarget.allocate(8, 8, PixelFormat.Rgba8, false);
			colors.push(target.asColor(LoadAction.Clear, RED));
		}
		beginPass(colors, NO_DEPTH);
	} else if (name == "pass.foreignScreenTwice") {
		doorBeginScreenPass(0.0, 0.0, 0.0, 1.0);
		doorBeginScreenPass(0.0, 0.0, 0.0, 1.0);
	} else if (name == "pass.foreignEndNone") {
		doorEndPass();
	} else if (name == "pass.screenTwice") {
		beginScreenPass(BLACK);
		beginScreenPass(BLACK);
	} else if (name == "pass.targetTwice") {
		let target: RenderTarget = RenderTarget.allocate(16, 16, PixelFormat.Rgba8, false);
		let colors: Vec<ColorAttachment> = [target.asColor(LoadAction.Clear, BLACK)];
		beginPass(colors, NO_DEPTH);
		beginPass(colors, NO_DEPTH);
	} else if (name == "bindings.short") {
		let bindings: Vec<uint32> = new Array(GPU3D_BINDING_LENGTH - 1);
		applyBindings(bindings);
	} else {
		return false;
	}
	return true;
}

function resourceCase(name: string): boolean {
	if (name == "sampler.afterRelease") {
		let sampler: Sampler = Sampler.create(FilterMode.Nearest, Wrap.Clamp);
		const copy: Sampler = sampler;
		sampler = sampler.released();
		const _handle = copy.asHandle();
	} else if (name == "sampler.empty") {
		let sampler: Sampler = Sampler.create(FilterMode.Nearest, Wrap.Clamp);
		sampler = sampler.released();
		const _handle = sampler.asHandle();
	} else if (name == "target.closedTwice") {
		let target: RenderTarget = RenderTarget.allocate(8, 8, PixelFormat.Rgba8, true);
		const copy: RenderTarget = target;
		target.close();
		copy.close();
	} else if (name == "target.otherContext") {
		const target: RenderTarget = RenderTarget.allocate(8, 8, PixelFormat.Rgba8, false);
		target.generation = target.generation + 1;
		const _color = target.asColor(LoadAction.Clear, BLACK);
	} else if (name == "target.resizedAfterClose") {
		let target: RenderTarget = RenderTarget.allocate(8, 8, PixelFormat.Rgba8, true);
		const copy: RenderTarget = target;
		target.close();
		copy.resize(8, 8);
	} else if (name == "target.textureAfterClose") {
		let target: RenderTarget = RenderTarget.allocate(8, 8, PixelFormat.Rgba8, true);
		const copy: RenderTarget = target;
		target.close();
		const _view = copy.asTexture();
	} else if (name == "target.textureUnallocated") {
		const target: RenderTarget = RenderTarget.unallocated(PixelFormat.Rgba8, true);
		const _view = target.asTexture();
	} else if (name == "target.viewDestroyed") {
		const target: RenderTarget = RenderTarget.allocate(8, 8, PixelFormat.Rgba8, true);
		destroyView(target.texture);
		const _view = target.asTexture();
	} else {
		return false;
	}
	return true;
}

function pipelineCase(name: string): boolean {
	const cache: PipelineCache = PipelineCache.empty();
	if (name == "pipelines.closedInside") {
		beginScreenPass(BLACK);
		closePipelines(cache);
	} else if (name == "pipelines.closedThroughAlias") {
		const context: DrawContext = DrawContext.withUniformCapacity(MATERIAL_UNIFORM_LENGTH);
		const _first: uint32 = copyPipeline(context.pipelines);
		const held: DrawContext = context;
		closePipelines(context.pipelines);
		const _again: uint32 = copyPipeline(held.pipelines);
	} else if (name == "pipelines.releasedInside") {
		const _made: uint32 = copyPipeline(cache);
		beginScreenPass(BLACK);
		releasePipelines(cache);
	} else if (name == "block.neverApplied" || name == "block.afterPipelineChange") {
		beginScreenPass(BLACK);
		applyPipeline(litPipeline(cache, RenderState.defaults()));
		if (name == "block.afterPipelineChange") {
			applyEveryBlock();
			applyPipeline(litPipeline(cache, RenderState.defaults().withCulling(Face.None)));
		}
		draw(0, 0, 1);
	} else {
		return false;
	}
	return true;
}

function init(): void { gfxSetup(); }

function frame(): void {
	const known: boolean = attachmentCase(chosen) || passCase(chosen) || resourceCase(chosen) ||
		pipelineCase(chosen) || texturedDraw(chosen);
	if (!known) {
		console.log(`no case named '${chosen}'`);
		process.exit(2);
	}
	console.log(`${chosen} returned`);
	process.exit(0);
}

if (plainCase(chosen)) {
	console.log(`${chosen} returned`);
} else {
	voidRun(64, 64, init, frame);
}
