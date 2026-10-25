// expect forward.closed.prepareFrame: void3d: prepareFrame on a forward preset that was closed
// expect forward.closed.drawToScreen: void3d: drawToScreen on a forward preset that was closed
// expect forward.bloom.ldr: void3d: setBloom on a forward preset made by create; bloom needs createHdr
// expect forward.bloom.settings: void3d: setBloom with intensity -1
// expect pixelArt.closed.setSettings: void3d: setSettings on a pixel-art preset that was closed
// expect pixelArt.closed.setLook: void3d: setLook on a pixel-art preset that was closed
// expect pixelArt.closed.setPalette: void3d: setPalette on a pixel-art preset that was closed
// expect pixelArt.closed.viewFor: void3d: viewFor on a pixel-art preset that was closed
// expect pixelArt.closed.drawToScreen: void3d: drawToScreen on a pixel-art preset that was closed
// expect pixelArt.closed.closePixelArt: void3d: closePixelArt on a pixel-art preset that was closed
// expect pixelArt.bloom.ldr: void3d: setBloom on a pixel-art preset made by create; bloom needs createHdr
// expect pixelArt.fog.setLookEqual: void3d: setLook requires finite fog.start < fog.end
// expect pixelArt.fog.setLookReverse: void3d: setLook requires finite fog.start < fog.end
// expect pixelArt.fog.setLookNan: void3d: setLook requires finite fog.start < fog.end
// expect pixelArt.fog.setLookInfinite: void3d: setLook requires finite fog.start < fog.end
// expect pixelArt.fog.writeEqual: void3d: writePostParams requires finite fog.start < fog.end
// expect pixelArt.fog.writeReverse: void3d: writePostParams requires finite fog.start < fog.end
// expect pixelArt.fog.writeNan: void3d: writePostParams requires finite fog.start < fog.end
// expect pixelArt.fog.writeInfinite: void3d: writePostParams requires finite fog.start < fog.end
// expect renderer.closed.markChanged: void3d: markChanged on a renderer that was closed
// expect renderer.closed.beginFrame: void3d: beginFrame on a renderer that was closed
// expect renderer.closed.drawPassLists: void3d: drawPassLists on a renderer that was closed
// expect renderer.closed.drawPhase: void3d: drawPhase on a renderer that was closed
// expect renderer.closed.phaseCount: void3d: phaseCount on a renderer that was closed
// expect renderer.closed.drawScreen: void3d: drawScreen on a renderer that was closed
// expect renderer.closed.closeRenderer: void3d: closeRenderer on a renderer that was closed
// expect renderer.coreClosed.prepareFrame: void3d: prepareFrame on a renderer that was closed
// expect renderer.coreClosed.drawToScreen: void3d: drawToScreen on a renderer that was closed
// expect renderer.linear.intoEncoded: void3d: drawPhase writes linear colour into a Default target
// expect renderer.encoded.intoLinear: void3d: drawPhase writes encoded colour into a Rgba16f target
// expect shadow.foreign: void3d: attachShadow with a shadow map of another draw context
// expect shadow.closedAttach: void3d: attachShadow with a shadow map that was closed
// expect shadow.closedFrame: void3d: beginFrame with a shadow map that was closed
// expect shadow.closedTwice: void3d: closeDirShadow on a shadow map that was closed
// expect shadow.unlitReceiver: void3d: Core UnlitTextured has no shadowed variant
// expect closeInside.closeContext: void3d: closeContext with a pass open; endPass ends it
// expect closeInside.closeScene: void3d: closeScene with a pass open; endPass ends it
// expect closeInside.closeMeshFrames: void3d: closeMeshFrames with a pass open; endPass ends it
// expect closeInside.closeGltfAssets: void3d: closeGltfAssets with a pass open; endPass ends it
// expect closeInside.closePalette: void3d: closePalette with a pass open; endPass ends it
// expect closeInside.closeRenderer: void3d: closeRenderer with a pass open; endPass ends it
// expect closeInside.closePixelArt: void3d: closePixelArt with a pass open; endPass ends it
// expect contextClosed.rendererCreate: void3d: Renderer.createDrawing on a draw context that was closed
// expect contextClosed.forwardCreate: void3d: ForwardRenderer.create on a draw context that was closed
// expect contextClosed.pixelArtCreate: void3d: PixelArtRenderer.create on a draw context that was closed
// expect closeInside.closeForward: void3d: closeForward with a pass open; endPass ends it
// expect forward.closedTwice.closeForward: void3d: closeForward on a forward preset that was closed
// expect forward.closed.endPrepared: void3d: endPrepared on a forward preset that was closed
// expect forward.unprepared.endPrepared: void3d: endPrepared with no prepared frame; call prepareFrame first
// expect forward.preparedTwice.prepareFrame: void3d: prepareFrame on a frame no drawToScreen or endPrepared ended
// expect forward.insideScreen.prepareFrame: void3d: prepareFrame with a pass already open; it would nest inside it
// expect forward.noScreenPass.drawToScreen: void3d: drawToScreen outside a screen pass; open one with beginScreenPass
// expect forward.unprepared.drawToScreen: void3d: drawToScreen with no prepared frame; call prepareFrame first
// expect pixelArt.closed.endPrepared: void3d: endPrepared on a pixel-art preset that was closed
// expect pixelArt.closed.prepareFrame: void3d: prepareFrame on a pixel-art preset that was closed
// expect outline.blendNan: void3d: setOutlineBlend needs a finite blend in [0,1]
// expect outline.blendRange: void3d: setOutlineBlend needs a finite blend in [0,1]
// expect outline.closed.setOutlineBlend: void3d: setOutlineBlend on a forward preset that was closed
// expect outline.uniformBudget: void3d: setOutlineBlend needs FORWARD_OUTLINE_PASS_UNIFORM_LENGTH
import { argv } from "std/process";
import { gfxSetup } from "../../../src/sokol/gpu";
import { Vec4 } from "../../../src/math/math3d";
import { SWAPCHAIN_LAYOUT, beginScreenPass } from "../../../src/gpu/target";
import { PixelFormat } from "../../../src/gpu/door";
import {
	Preset,
	VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
	Program,
	ProgramKey,
} from "../../../src/void3d/gpu3d";
import { Phase } from "../../../src/void3d/material";
import {
	DrawContext,
	DrawItem,
	GpuMesh,
	MeshId,
	MeshUploadError,
	NO_MATERIAL,
	addMesh,
	closeContext,
} from "../../../src/void3d/draw";
import { Scene3D, closeScene } from "../../../src/void3d/scene";
import {
	AnimationClock,
	AnimationError,
	Interpolation,
	MeshFrameAnimation,
	closeMeshFrames,
} from "../../../src/void3d/animation";
import { GltfAssets, closeGltfAssets } from "../../../src/void3d/gltfScene";
import { PaletteLut, PaletteError, closePalette } from "../../../src/void3d/palette";
import { BloomSettings } from "../../../src/void3d/bloom";
import { LowResView, ViewError } from "../../../src/void3d/blit";
import {
	Renderer,
	RendererError,
	RENDERER_UNIFORM_LENGTH,
	markChanged,
	beginFrame,
	drawPassLists,
	drawPhase,
	drawScreen,
	closeRenderer,
	attachShadow,
} from "../../../src/void3d/renderer";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	FORWARD_HDR_UNIFORM_LENGTH,
	setBloom,
	setOutlineBlend,
	prepareFrame,
	drawToScreen,
	endPrepared,
	closeForward,
} from "../../../src/void3d/forwardRenderer";
import {
	PixelArtRenderer,
	PixelArtSettings,
	PixelArtLook,
	PixelArtError,
	PIXEL_ART_UNIFORM_LENGTH,
	POST_UNIFORM_LENGTH,
	writePostParams,
	setSettings,
	setLook,
	setPalette,
	closePixelArt,
	setBloom as setPixelArtBloom,
	prepareFrame as prepareFramePixelArt,
	drawToScreen as drawToScreenPixelArt,
	endPrepared as endPreparedPixelArt,
} from "../../../src/void3d/pixelArtRenderer";
import {
	DirShadowMap,
	ShadowError,
	DIR_SHADOW_UNIFORM_LENGTH,
	closeDirShadow,
} from "../../../src/void3d/dirShadowMap";
@include("../../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const BLACK: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
let chosen: string = (argv.length as int32) > 1 ? argv[1] : "";

function look(): PixelArtLook {
	return {
		background: BLACK,
		outline: {
			depthThreshold: 0.006,
			normalThreshold: 0.6,
			depthShade: 0.55,
			normalShade: 1.35,
		},
		fog: { start: 0.5, end: 0.8, strength: 0.0, color: BLACK },
		saturation: 0.0,
	};
}

function forwardOn(context: DrawContext): ForwardRenderer {
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, BLACK);
	if (!made.ok) { unreachable; }
	return made.value;
}

function openForward(hdr: boolean): ForwardRenderer {
	let context: DrawContext = DrawContext.withUniformCapacity(FORWARD_HDR_UNIFORM_LENGTH);
	const made: Result<ForwardRenderer, ForwardError> = hdr ?
		ForwardRenderer.createHdrWhere(context, BLACK, true) :
		ForwardRenderer.create(context, BLACK);
	if (!made.ok) { unreachable; }
	return made.value;
}

function closedForward(): ForwardRenderer {
	let context: DrawContext = DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH);
	let forward: ForwardRenderer = forwardOn(context);
	closeForward(forward);
	return forward;
}

function pixelArtOn(context: DrawContext): PixelArtRenderer {
	const made: Result<PixelArtRenderer, PixelArtError> =
		PixelArtRenderer.create(context, PixelArtSettings.full(), look());
	if (!made.ok) { unreachable; }
	return made.value;
}

function closedPixelArt(): PixelArtRenderer {
	let context: DrawContext = DrawContext.withUniformCapacity(PIXEL_ART_UNIFORM_LENGTH);
	let pixelArt: PixelArtRenderer = pixelArtOn(context);
	closePixelArt(pixelArt);
	return pixelArt;
}

function coreOn(context: DrawContext): Renderer {
	const made: Result<Renderer, RendererError> = Renderer.create(context);
	if (!made.ok) { unreachable; }
	return made.value;
}

function closedCore(): Renderer {
	let context: DrawContext = DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH);
	let core: Renderer = coreOn(context);
	closeRenderer(core);
	return core;
}

function openCore(linearOutput: boolean): Renderer {
	let context: DrawContext = DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH);
	let core: Renderer = coreOn(context);
	core.linearOutput = linearOutput;
	return core;
}

function forwardWithClosedCore(): ForwardRenderer {
	let context: DrawContext = DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH);
	let forward: ForwardRenderer = forwardOn(context);
	let core: Renderer = forward.core;
	closeRenderer(core);
	return forward;
}

function mapOn(context: DrawContext): DirShadowMap {
	const made: Result<DirShadowMap, ShadowError> = DirShadowMap.create(context, 64);
	if (!made.ok) { unreachable; }
	return made.value;
}

function forwardCase(name: string): boolean {
	let items: Vec<DrawItem> = [];
	let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
	let blocks: Vec<float32> = [];
	if (name == "forward.closed.prepareFrame") {
		const _r: Result<int32, ForwardError> =
			prepareFrame(closedForward(), items, camera, lights, 32, 24);
	} else if (name == "forward.bloom.ldr") {
		setBloom(openForward(false), BloomSettings.natural());
	} else if (name == "forward.bloom.settings") {
		setBloom(openForward(true), { ...BloomSettings.natural(), intensity: -1.0 });
	} else if (name == "forward.closed.drawToScreen") {
		drawToScreen(closedForward());
	} else if (name == "forward.closedTwice.closeForward") {
		let forward: ForwardRenderer = closedForward();
		let alias: ForwardRenderer = forward;
		closeForward(alias);
	} else if (name == "forward.closed.endPrepared") {
		endPrepared(closedForward());
	} else if (name == "forward.unprepared.endPrepared") {
		endPrepared(openForward(false));
	} else if (name == "forward.preparedTwice.prepareFrame") {
		let forward: ForwardRenderer = openForward(false);
		forward.core.prepared = true;
		const _again: Result<int32, ForwardError> =
			prepareFrame(forward, items, blocks, blocks, 64, 64);
	} else if (name == "forward.noScreenPass.drawToScreen") {
		let forward: ForwardRenderer = openForward(false);
		forward.core.prepared = true;
		drawToScreen(forward);
	} else if (name == "forward.unprepared.drawToScreen") {
		drawToScreen(openForward(false));
	} else if (name == "outline.blendNan") {
		setOutlineBlend(openForward(false), NaN as float32);
	} else if (name == "outline.blendRange") {
		setOutlineBlend(openForward(false), 1.1);
	} else if (name == "outline.closed.setOutlineBlend") {
		setOutlineBlend(closedForward(), 0.5);
	} else if (name == "outline.uniformBudget") {
		setOutlineBlend(openForward(false), 1.0);
	} else {
		return false;
	}
	return true;
}

function pixelArtCase(name: string): boolean {
	let colors: Vec<uint32> = [0xFF000000, 0xFFFFFFFF];
	if (name.startsWith("pixelArt.fog.")) {
		let style = look();
		style.fog.start = 1.0;
		style.fog.end = name.endsWith("Equal") ? 1.0 : 0.5;
		if (name.endsWith("Nan")) { style.fog.end = (0.0 / 0.0) as float32; }
		if (name.endsWith("Infinite")) { style.fog.end = (1.0 / 0.0) as float32; }
		if (name.startsWith("pixelArt.fog.setLook")) {
			let context = DrawContext.withUniformCapacity(PIXEL_ART_UNIFORM_LENGTH);
			setLook(pixelArtOn(context), style);
		} else {
			let values: Vec<float32> = new Array(POST_UNIFORM_LENGTH);
			style.writePostParams(PixelArtSettings.full(), 16, true, values);
		}
	} else if (name == "pixelArt.bloom.ldr") {
		let context: DrawContext = DrawContext.withUniformCapacity(PIXEL_ART_UNIFORM_LENGTH);
		setPixelArtBloom(pixelArtOn(context), BloomSettings.natural());
	} else if (name == "pixelArt.closed.setSettings") {
		setSettings(closedPixelArt(), PixelArtSettings.full());
	} else if (name == "pixelArt.closed.setLook") {
		setLook(closedPixelArt(), look());
	} else if (name == "pixelArt.closed.setPalette") {
		const _r: Result<int32, PaletteError> = setPalette(closedPixelArt(), colors);
	} else if (name == "pixelArt.closed.viewFor") {
		const _r: Result<LowResView, ViewError> = closedPixelArt().viewFor(320, 240, 0.0, 0.0);
	} else if (name == "pixelArt.closed.drawToScreen") {
		drawToScreenPixelArt(closedPixelArt());
	} else if (name == "pixelArt.closed.closePixelArt") {
		closePixelArt(closedPixelArt());
	} else if (name == "pixelArt.closed.endPrepared") {
		endPreparedPixelArt(closedPixelArt());
	} else if (name == "pixelArt.closed.prepareFrame") {
		let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
		let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
		let none: Vec<DrawItem> = [];
		const view: LowResView = { width: 32, height: 24, scale: 1, offsetX: 0.0, offsetY: 0.0 };
		const _drawn: Result<int32, PixelArtError> =
			prepareFramePixelArt(closedPixelArt(), none, camera, lights, view);
	} else {
		return false;
	}
	return true;
}

function rendererCase(name: string): boolean {
	let items: Vec<DrawItem> = [];
	let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
	if (name == "renderer.closed.markChanged") {
		markChanged(closedCore());
	} else if (name == "renderer.closed.beginFrame") {
		const _r: Result<boolean, RendererError> = beginFrame(closedCore(), items, camera, lights);
	} else if (name == "renderer.closed.drawPassLists") {
		drawPassLists(closedCore(), items, SWAPCHAIN_LAYOUT);
	} else if (name == "renderer.closed.drawPhase") {
		drawPhase(closedCore(), Phase.Alpha, items, SWAPCHAIN_LAYOUT);
	} else if (name == "renderer.closed.phaseCount") {
		const _count: int32 = closedCore().phaseCount(Phase.Alpha);
	} else if (name == "renderer.closed.drawScreen") {
		const _r: Result<int32, RendererError> =
			drawScreen(closedCore(), NO_MATERIAL, SWAPCHAIN_LAYOUT);
	} else if (name == "renderer.closed.closeRenderer") {
		closeRenderer(closedCore());
	} else if (name == "renderer.coreClosed.prepareFrame") {
		const _r: Result<int32, ForwardError> =
			prepareFrame(forwardWithClosedCore(), items, camera, lights, 32, 24);
	} else if (name == "renderer.coreClosed.drawToScreen") {
		drawToScreen(forwardWithClosedCore());
	} else if (name == "renderer.linear.intoEncoded") {
		drawPhase(openCore(true), Phase.Opaque, items, SWAPCHAIN_LAYOUT);
	} else if (name == "renderer.encoded.intoLinear") {
		drawPhase(openCore(false), Phase.Opaque, items,
			{ ...SWAPCHAIN_LAYOUT, color0: PixelFormat.Rgba16f });
	} else {
		return false;
	}
	return true;
}

function shadowCase(name: string): boolean {
	if (!name.startsWith("shadow.")) { return false; }
	let context: DrawContext =
		DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH + DIR_SHADOW_UNIFORM_LENGTH);
	let core: Renderer = coreOn(context);
	if (name == "shadow.foreign") {
		let other: DrawContext = DrawContext.withUniformCapacity(DIR_SHADOW_UNIFORM_LENGTH);
		attachShadow(core, mapOn(other));
	} else if (name == "shadow.closedAttach") {
		let map: DirShadowMap = mapOn(context);
		closeDirShadow(map);
		attachShadow(core, map);
	} else if (name == "shadow.closedFrame") {
		let map: DirShadowMap = mapOn(context);
		attachShadow(core, map);
		closeDirShadow(map);
		let items: Vec<DrawItem> = [];
		let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
		let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
		const _began: Result<boolean, RendererError> = beginFrame(core, items, camera, lights);
	} else if (name == "shadow.closedTwice") {
		let map: DirShadowMap = mapOn(context);
		closeDirShadow(map);
		closeDirShadow(map);
	} else if (name == "shadow.unlitReceiver") {
		const _key: ProgramKey = ProgramKey.of(Program.UnlitTextured).withShadowed();
	} else {
		return false;
	}
	return true;
}

function contextClosedCase(name: string): boolean {
	if (!name.startsWith("contextClosed.")) { return false; }
	let context: DrawContext = DrawContext.withUniformCapacity(8);
	closeContext(context);
	if (name == "contextClosed.rendererCreate") {
		const _r: Result<Renderer, RendererError> = Renderer.createDrawing(context, Preset.Core);
	} else if (name == "contextClosed.forwardCreate") {
		const _r: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, BLACK);
	} else if (name == "contextClosed.pixelArtCreate") {
		const _r: Result<PixelArtRenderer, PixelArtError> =
			PixelArtRenderer.create(context, PixelArtSettings.full(), look());
	} else {
		return false;
	}
	return true;
}

function passOpenCase(name: string, context: DrawContext): boolean {
	if (name == "closeInside.closeContext") {
		beginScreenPass(BLACK);
		closeContext(context);
	} else if (name == "closeInside.closeScene") {
		let scene: Scene3D = Scene3D.create(context);
		beginScreenPass(BLACK);
		closeScene(scene);
	} else if (name == "closeInside.closeMeshFrames") {
		const mesh: Result<MeshId, MeshUploadError> = addMesh(context, GpuMesh.fullscreen(0, 3));
		if (!mesh.ok) { unreachable; }
		let meshes: Vec<MeshId> = [mesh.value];
		const clock: Result<AnimationClock, AnimationError> =
			AnimationClock.forFrames(1, 12.0, Interpolation.Step);
		if (!clock.ok) { unreachable; }
		const made: Result<MeshFrameAnimation, AnimationError> =
			MeshFrameAnimation.forMeshes(context, clock.value, "frames", meshes);
		if (!made.ok) { unreachable; }
		beginScreenPass(BLACK);
		closeMeshFrames(made.value);
	} else if (name == "closeInside.closeGltfAssets") {
		let assets: GltfAssets = {
			context: context,
			bindings: [],
			meshes: [],
			materials: [],
			textures: [],
			closed: false,
		};
		beginScreenPass(BLACK);
		closeGltfAssets(assets);
	} else if (name == "closeInside.closePalette") {
		const made: Result<PaletteLut, PaletteError> = PaletteLut.withLevels(4);
		if (!made.ok) { unreachable; }
		beginScreenPass(BLACK);
		closePalette(made.value);
	} else if (name == "closeInside.closeRenderer") {
		let core: Renderer = coreOn(context);
		beginScreenPass(BLACK);
		closeRenderer(core);
	} else if (name == "closeInside.closePixelArt") {
		let pixelArt: PixelArtRenderer = pixelArtOn(context);
		beginScreenPass(BLACK);
		closePixelArt(pixelArt);
	} else if (name == "closeInside.closeForward") {
		let forward: ForwardRenderer = forwardOn(context);
		beginScreenPass(BLACK);
		closeForward(forward);
	} else if (name == "forward.insideScreen.prepareFrame") {
		let forward: ForwardRenderer = forwardOn(context);
		let items: Vec<DrawItem> = [];
		let blocks: Vec<float32> = [];
		beginScreenPass(BLACK);
		const _prepared: Result<int32, ForwardError> =
			prepareFrame(forward, items, blocks, blocks, 640, 360);
	} else {
		return false;
	}
	return true;
}

function init(): void { gfxSetup(); }

function frame(): void {
	let context: DrawContext = DrawContext.withUniformCapacity(
		RENDERER_UNIFORM_LENGTH + PIXEL_ART_UNIFORM_LENGTH + FORWARD_UNIFORM_LENGTH,
	);
	if (!passOpenCase(chosen, context)) {
		console.log(`no case named '${chosen}'`);
		process.exit(2);
	}
	console.log(`${chosen} returned inside a pass`);
	process.exit(0);
}

if (forwardCase(chosen) || pixelArtCase(chosen) || rendererCase(chosen) || shadowCase(chosen) ||
	contextClosedCase(chosen)) {
	console.log(`${chosen} returned`);
} else {
	voidRun(64, 64, init, frame);
}
