// expect closeContext: void3d: closeContext with a pass open; endPass ends it
// expect closeScene: void3d: closeScene with a pass open; endPass ends it
// expect closeMeshFrames: void3d: closeMeshFrames with a pass open; endPass ends it
// expect closeGltfAssets: void3d: closeGltfAssets with a pass open; endPass ends it
// expect closePalette: void3d: closePalette with a pass open; endPass ends it
// expect closeRenderer: void3d: closeRenderer with a pass open; endPass ends it
// expect closePixelArt: void3d: closePixelArt with a pass open; endPass ends it
import { argv } from "std/process";
import { gfxSetup } from "../../../src/sokol/gpu";
import { Vec4 } from "../../../src/math/math3d";
import { beginScreenPass } from "../../../src/gpu/target";
import {
	DrawContext,
	GpuMesh,
	MeshId,
	MeshUploadError,
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
import {
	Renderer,
	RendererError,
	RENDERER_UNIFORM_LENGTH,
	closeRenderer,
} from "../../../src/void3d/renderer";
import {
	PixelArtRenderer,
	PixelArtSettings,
	PixelArtLook,
	PixelArtError,
	PIXEL_ART_UNIFORM_LENGTH,
	closePixelArt,
} from "../../../src/void3d/pixelArtRenderer";
@include("../../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const BLACK: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
let chosen: string = caseName();

function caseName(): string {
	return (argv.length as int32) > 1 ? argv[1] : "";
}

function look(): PixelArtLook {
	return {
		background: BLACK,
		outline: { depthThreshold: 0.006, normalThreshold: 0.6, depthShade: 0.55, normalShade: 1.35 },
		fog: { start: 0.5, end: 0.8, strength: 0.0, color: BLACK },
		saturation: 0.0,
	};
}

function closeInside(name: string, context: DrawContext): boolean {
	if (name == "closeContext") {
		beginScreenPass(BLACK);
		closeContext(context);
	} else if (name == "closeScene") {
		let scene: Scene3D = Scene3D.create(context);
		beginScreenPass(BLACK);
		closeScene(scene);
	} else if (name == "closeMeshFrames") {
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
	} else if (name == "closeGltfAssets") {
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
	} else if (name == "closePalette") {
		const made: Result<PaletteLut, PaletteError> = PaletteLut.withLevels(4);
		if (!made.ok) { unreachable; }
		beginScreenPass(BLACK);
		closePalette(made.value);
	} else if (name == "closeRenderer") {
		const made: Result<Renderer, RendererError> = Renderer.create(context);
		if (!made.ok) { unreachable; }
		beginScreenPass(BLACK);
		closeRenderer(made.value);
	} else if (name == "closePixelArt") {
		const made: Result<PixelArtRenderer, PixelArtError> =
			PixelArtRenderer.create(context, PixelArtSettings.full(), look());
		if (!made.ok) { unreachable; }
		beginScreenPass(BLACK);
		closePixelArt(made.value);
	} else {
		return false;
	}
	return true;
}

function init(): void { gfxSetup(); }

function frame(): void {
	let context: DrawContext =
		DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH + PIXEL_ART_UNIFORM_LENGTH);
	const known: boolean = closeInside(chosen, context);
	console.log(known ? `${chosen} returned inside a pass` : `no case named '${chosen}'`);
	process.exit(0);
}

voidRun(64, 64, init, frame);
