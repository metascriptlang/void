// Stencil through the door: a pipeline's stencil state reaches the device, the reference is set per
// draw without making a pipeline, the pass clears the stencil to a value or loads it, and a stencil
// on a target with no stencil bits is refused naming the pipeline.

import { shaderProgram } from "../shader/program";
import { Vec2f, Vec4f, builtin, vec4f } from "../shader/std";
import { Compare, Face, RenderState, Stencil, StencilOp } from "../gpu/state";
import { PixelFormat, stencilTargetRefusal } from "../gpu/doorGpu.ms";
import { TargetLayout } from "../gpu/target";
import { DOOR_BINDING_LENGTH } from "../gpu/doorWords";
import { endPass, programLayout } from "../gpu/door";
import { PipelineKey, keyText, pipelineKey, prewarmRefusal } from "../gpu/pipeline";

struct QuadInput {
	position: Vec2f;
}

struct QuadVarying {
	@builtin(position) position: Vec4f;
}

function quadVs(input: QuadInput): QuadVarying {
	return { position: vec4f(input.position.x, input.position.y, 0.0, 1.0) };
}

function redFs(): Vec4f {
	return vec4f(1.0, 0.0, 0.0, 1.0);
}

function greenFs(): Vec4f {
	return vec4f(0.0, 1.0, 0.0, 1.0);
}

shaderProgram(red, quadVs, redFs);
shaderProgram(green, quadVs, greenFs);

function stencilOnly(): RenderState {
	return plain().withColorMask(false, false, false, false);
}

function maskWriter(reference: uint8, writeMask: uint8): Stencil {
	return Stencil.defaults()
		.withFunc(Compare.Always, 0xFF, writeMask)
		.withOps(StencilOp.Keep, StencilOp.Keep, StencilOp.Replace)
		.withReference(reference);
}

function maskTester(reference: uint8): Stencil {
	return Stencil.defaults()
		.withFunc(Compare.Equal, 0xFF, 0)
		.withOps(StencilOp.Keep, StencilOp.Keep, StencilOp.Keep)
		.withReference(reference);
}

function plain(): RenderState {
	return RenderState.defaults().withCulling(Face.None).withDepth(false, Compare.Always);
}

function offscreen(depth: PixelFormat): TargetLayout {
	return {
		color0: PixelFormat.Rgba8,
		color1: PixelFormat.None,
		color2: PixelFormat.None,
		color3: PixelFormat.None,
		depth,
		sampleCount: 1,
	};
}

test "a stencil on a target without stencil bits is refused, and the message names what is wrong" {
	assert stencilTargetRefusal(false, PixelFormat.Depth) == "";
	assert stencilTargetRefusal(false, PixelFormat.None) == "";
	assert stencilTargetRefusal(true, PixelFormat.DepthStencil) == "";
	assert stencilTargetRefusal(true, PixelFormat.Depth) ==
		"a stencil on a Depth target, which has no stencil bits; DepthStencil does";
	assert stencilTargetRefusal(true, PixelFormat.None) ==
		"a stencil on a None target, which has no stencil bits; DepthStencil does";
}

test "a prewarm of a stencil on a depth-only target is refused naming its key" {
	const state: RenderState = plain().withStencil(maskWriter(1, 0xFF));
	const depthOnly: PipelineKey = pipelineKey(
		red, programLayout(red), false, state, offscreen(PixelFormat.Depth),
	);
	assert prewarmRefusal(depthOnly) ==
		`prewarm of ${keyText(depthOnly)}: ` +
		"a stencil on a Depth target, which has no stencil bits; DepthStencil does";
	const withStencilBits: PipelineKey = pipelineKey(
		red, programLayout(red), false, state, offscreen(PixelFormat.DepthStencil),
	);
	assert prewarmRefusal(withStencilBits) == "";
}

when (voidDummy || (windows && !voidVulkan)) {
	import { Vec4 } from "../math/math3d";
	import {
		DOOR_BUFFER_VERTEX,
		doorApplyBindings,
		doorApplyPipeline,
		doorApplyStencilReference,
		doorDraw,
		doorMakeBufferOf,
		doorReadTexture,
		doorSetup,
		doorShutdown,
		LoadAction,
		StoreAction,
	} from "../gpu/doorGpu.ms";
	import { livePipelines } from "../gpu/door";
	import {
		ColorAttachment,
		DepthAttachment,
		RenderTarget,
		beginPass,
		layoutOf,
	} from "../gpu/target";
	import { PipelineCache, closePipelines, pipelineFor } from "../gpu/pipeline";
}
when (windows && !voidDummy && !voidVulkan) {
	import { warpDevice, warpContext } from "./d3d11Warp.h";
	@passL("-ld3d11");
}

const RGBA8 = 2;
const NO_DEPTH = 0;
const SIZE = 8;
const LEFT = 0;
const RIGHT = 6;
const FULL = 12;

when (voidDummy || (windows && !voidVulkan)) {
	struct Scene {
		color: RenderTarget;
		depth: RenderTarget;
		layout: TargetLayout;
		vertices: uint32;
		cache: PipelineCache;
	}

	function quads(): Vec<float32> {
		return [
			-1, -1, 0, -1, 0, 1, -1, -1, 0, 1, -1, 1,
			0, -1, 1, -1, 1, 1, 0, -1, 1, 1, 0, 1,
			-1, -1, 1, -1, 1, 1, -1, -1, 1, 1, -1, 1,
		];
	}

	function openScene(): Scene {
		when (voidDummy) {
			doorSetup(null, null, RGBA8, NO_DEPTH, 1);
		} else {
			doorSetup(warpDevice(), warpContext(), RGBA8, NO_DEPTH, 1);
		}
		const color: RenderTarget = RenderTarget.allocate(SIZE, SIZE, PixelFormat.Rgba8, false);
		const depth: RenderTarget = RenderTarget.allocate(SIZE, SIZE, PixelFormat.DepthStencil, false);
		const black: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
		return {
			color,
			depth,
			layout: layoutOf(
				[color.asColor(LoadAction.Clear, black)],
				depth.asDepth(LoadAction.Clear, 1.0, StoreAction.Store, null),
			),
			vertices: doorMakeBufferOf(DOOR_BUFFER_VERTEX, quads()),
			cache: PipelineCache.empty(),
		};
	}

	function closeScene(scene: Scene): void {
		closePipelines(scene.cache);
		scene.color.close();
		scene.depth.close();
		doorShutdown();
	}

	// The color is cleared to black on every pass; the stencil is cleared to `stencilClear`, or kept
	// when it is null.
	function beginStencilPass(scene: Scene, stencilClear: uint8 | null): void {
		const black: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
		const colors: Vec<ColorAttachment> = [scene.color.asColor(LoadAction.Clear, black)];
		const depth: DepthAttachment = scene.depth.asDepth(
			LoadAction.Clear, 1.0, StoreAction.Store, stencilClear,
		);
		beginPass(colors, depth);
	}

	function pipelineOf(scene: Scene, program: int32, state: RenderState): uint32 {
		return pipelineFor(scene.cache, program, programLayout(program), false, state, scene.layout);
	}

	// What a layer does per draw: apply the pipeline, then the state's reference.
	function drawQuad(scene: Scene, program: int32, state: RenderState, first: int32): void {
		doorApplyPipeline(pipelineOf(scene, program, state));
		let words: Vec<uint32> = [];
		for (let i = 0; i < DOOR_BINDING_LENGTH; i++) { words.push(0); }
		words[0] = scene.vertices;
		doorApplyBindings(words, [0]);
		const stencil: Stencil | null = state.stencil;
		if (stencil != null) { doorApplyStencilReference(stencil.reference); }
		doorDraw(first, 6, 1);
	}

	test "a reference change between two draws makes no pipeline and a stencil state makes one" {
		const scene: Scene = openScene();
		const before: int32 = livePipelines();
		const first: uint32 = pipelineOf(scene, red, plain().withStencil(maskWriter(1, 0xFF)));
		assert livePipelines() == before + 1;
		assert pipelineOf(scene, red, plain().withStencil(maskWriter(2, 0xFF))) == first;
		assert pipelineOf(scene, red, plain().withStencil(maskWriter(255, 0xFF))) == first;
		assert livePipelines() == before + 1;
		assert pipelineOf(scene, red, plain().withStencil(maskWriter(1, 0x0F))) != first;
		assert pipelineOf(scene, red, plain()) != first;
		assert livePipelines() == before + 3;
		closeScene(scene);
	}

	test "a depth bias makes its own pipeline and the same bias reuses it" {
		const scene: Scene = openScene();
		const before: int32 = livePipelines();
		const flat: uint32 = pipelineOf(scene, red, plain());
		const biased: uint32 = pipelineOf(scene, red, plain().withDepthBias(2, 1.5));
		assert biased != flat;
		assert pipelineOf(scene, red, plain().withDepthBias(2, 1.5)) == biased;
		assert pipelineOf(scene, red, plain().withDepthBias(2, 2.0)) != biased;
		assert livePipelines() == before + 3;
		closeScene(scene);
	}
}

when (windows && !voidDummy && !voidVulkan) {
	const BLACK: uint32 = 0xFF000000;
	const GREEN: uint32 = 0xFF00FF00;

	// The pixel of column `x` and row `y` as 0xAABBGGRR.
	function pixelAt(image: uint32, x: int32, y: int32): uint32 {
		let out: Vec<uint8> = new Array(SIZE * SIZE * 4);
		if (doorReadTexture(image, 0, 0, SIZE, SIZE, out) != 1) {
			console.log("doorStencilCheck: readTexture refused the target");
			unreachable;
		}
		const at: int32 = (y * SIZE + x) * 4;
		return (out[at] as uint32) | ((out[at + 1] as uint32) << 8) |
			((out[at + 2] as uint32) << 16) | ((out[at + 3] as uint32) << 24);
	}

	function leftAndRight(scene: Scene): Vec<uint32> {
		return [pixelAt(scene.color.image, 1, 4), pixelAt(scene.color.image, 6, 4)];
	}

	test "a draw tests the stencil against the reference it was given, and each reference takes effect" {
		const scene: Scene = openScene();
		const writer: RenderState = stencilOnly().withStencil(maskWriter(1, 0xFF));
		beginStencilPass(scene, 0);
		drawQuad(scene, red, writer, LEFT);
		drawQuad(scene, red, stencilOnly().withStencil(maskWriter(2, 0xFF)), RIGHT);
		endPass();
		beginStencilPass(scene, null);
		drawQuad(scene, green, plain().withStencil(maskTester(1)), FULL);
		endPass();
		let sides: Vec<uint32> = leftAndRight(scene);
		assert sides[0] == GREEN && sides[1] == BLACK;
		beginStencilPass(scene, null);
		drawQuad(scene, green, plain().withStencil(maskTester(2)), FULL);
		endPass();
		sides = leftAndRight(scene);
		assert sides[0] == BLACK && sides[1] == GREEN;
		beginStencilPass(scene, null);
		drawQuad(scene, green, plain().withStencil(maskTester(1)), FULL);
		drawQuad(scene, green, plain().withStencil(maskTester(2)), FULL);
		endPass();
		sides = leftAndRight(scene);
		assert sides[0] == GREEN && sides[1] == GREEN;
		beginStencilPass(scene, null);
		drawQuad(scene, green, plain().withStencil(maskTester(3)), FULL);
		endPass();
		sides = leftAndRight(scene);
		assert sides[0] == BLACK && sides[1] == BLACK;
		closeScene(scene);
	}

	test "a pass clears the stencil to the value it was given and loads it when it was given none" {
		const scene: Scene = openScene();
		beginStencilPass(scene, 2);
		drawQuad(scene, green, plain().withStencil(maskTester(2)), FULL);
		endPass();
		let sides: Vec<uint32> = leftAndRight(scene);
		assert sides[0] == GREEN && sides[1] == GREEN;
		beginStencilPass(scene, null);
		drawQuad(scene, green, plain().withStencil(maskTester(2)), FULL);
		endPass();
		sides = leftAndRight(scene);
		assert sides[0] == GREEN && sides[1] == GREEN;
		beginStencilPass(scene, 0);
		drawQuad(scene, green, plain().withStencil(maskTester(2)), FULL);
		endPass();
		sides = leftAndRight(scene);
		assert sides[0] == BLACK && sides[1] == BLACK;
		closeScene(scene);
	}

	test "a write mask of zero keeps the stencil and a full one replaces it" {
		const scene: Scene = openScene();
		beginStencilPass(scene, 1);
		drawQuad(scene, red, stencilOnly().withStencil(maskWriter(3, 0)), FULL);
		drawQuad(scene, green, plain().withStencil(maskTester(1)), FULL);
		endPass();
		let sides: Vec<uint32> = leftAndRight(scene);
		assert sides[0] == GREEN && sides[1] == GREEN;
		beginStencilPass(scene, 1);
		drawQuad(scene, red, stencilOnly().withStencil(maskWriter(3, 0xFF)), FULL);
		drawQuad(scene, green, plain().withStencil(maskTester(1)), FULL);
		endPass();
		sides = leftAndRight(scene);
		assert sides[0] == BLACK && sides[1] == BLACK;
		beginStencilPass(scene, 1);
		drawQuad(scene, red, stencilOnly().withStencil(maskWriter(3, 0xFF)), FULL);
		drawQuad(scene, green, plain().withStencil(maskTester(3)), FULL);
		endPass();
		sides = leftAndRight(scene);
		assert sides[0] == GREEN && sides[1] == GREEN;
		closeScene(scene);
	}
}
