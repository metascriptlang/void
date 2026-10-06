// expect: void3d: drawItem with a material whose texture is not the one it was added with
import { gfxSetup } from "../../src/sokol/gpu";
import { FilterMode, Wrap, RenderState } from "../../src/gpu/state";
import { SWAPCHAIN_LAYOUT } from "../../src/gpu/target";
import { identity } from "../../src/math/math3d";
import { Program, ProgramKey } from "../../src/void3d/gpu3d";
import { Material, Phase, UniformBlock } from "../../src/void3d/material";
import { TextureData, TextureId } from "../../src/void3d/texture";
import {
	DrawContext,
	DrawItem,
	GpuMesh,
	addMesh,
	addMaterial,
	addTexture,
	releaseTexture,
	drawItem,
} from "../../src/void3d/draw";
import { voidCaptureExit } from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const NO_GLOBALS: Vec<UniformBlock> = [];

function texel(): TextureData {
	const pixels: Vec<uint32> = [0xff0000ff as uint32];
	return { pixels: pixels, width: 1, height: 1, filter: FilterMode.Nearest, wrap: Wrap.Clamp };
}

function textureOf(context: DrawContext): TextureId {
	const made = addTexture(context, texel());
	if (!made.ok) { unreachable; }
	return made.value;
}

function init(): void {
	gfxSetup();
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
	const past: TextureId = { store: context.serial, index: 99, generation: 1 };
	context.materials[material.value.index].texture = past;
	const item: DrawItem = { mesh: mesh.value, material: material.value, world: identity() };
	drawItem(context, item, ProgramKey.of(Program.LitTextured), SWAPCHAIN_LAYOUT, NO_GLOBALS);
	console.log("the call returned");
	voidCaptureExit(0);
}

function frame(): void {}

voidRunConfigured(32, 32, 1, 0, init, frame);
