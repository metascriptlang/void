import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec4, vec3, identity } from "../../src/math/math3d";
import { Rgba } from "../../src/void3d/meshData";
import { Material, MaterialKind, UniformBlock } from "../../src/void3d/material";
import {
	Program, MATERIAL_UNIFORM_SLOT, LINE_UNIFORM_LENGTH, VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import {
	DrawContext, DrawItem, MeshId, MaterialId, MaterialError, MeshUploadError,
	addMeshData, addMaterial, reserveUniforms, writeUniforms,
} from "../../src/void3d/draw";
import { UniformError } from "../../src/void3d/uniformPool";
import { Camera3D, CameraView, CameraError, ProjectionKind } from "../../src/void3d/camera";
import {
	Graphics3D, GraphicsError, lineStyle, moveTo, lineTo, writeLineBlock,
} from "../../src/void3d/graphics3d";
import {
	ForwardRenderer, ForwardError, FORWARD_UNIFORM_LENGTH, renderFrame,
} from "../../src/void3d/forwardRenderer";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const WIDTH: int32 = 320;
const HEIGHT: int32 = 240;
const GREY: Vec4 = { x: 0.2, y: 0.2, z: 0.2, w: 1.0 };
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const NEAR_DEPTH: float32 = 2.5;
const FAR_DEPTH: float32 = 10.0;

// Each stage draws one line 2.5 units ahead, above the centre, and one 10 units ahead, below it,
// both level and spanning the same columns; LineShader keeps both `width` pixels tall.
struct Stage {
	width: float32;
	name: string;
}

const STAGES: Vec<Stage> = [
	{ width: 6.0, name: "six pixels" },
	{ width: 2.0, name: "two pixels" },
];

let context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + (STAGES.length as int32) * LINE_UNIFORM_LENGTH,
);
let forward: ForwardRenderer = makeForward();
let lines: Vec<MaterialId> = [];
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let stage: int32 = 0;

function fail(message: string): void {
	console.log(`FAIL graphicsLine: stage ${stage}: ${message}`);
	voidCaptureExit(1);
}

function makeForward(): ForwardRenderer {
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, GREY);
	if (made.ok) { return made.value; }
	unreachable;
}

function camera(): Camera3D {
	return {
		position: vec3(0.0, 0.0, 0.0), yaw: 0.0, pitch: 0.0, orientation: null,
		nearPlane: 0.5, farPlane: 20.0,
		projection: { kind: ProjectionKind.Perspective, fovY: 1.0471976 },
	};
}

function viewOf(): CameraView {
	const view: Result<CameraView, CameraError> = camera().resolve(WIDTH, HEIGHT);
	if (view.ok) { return view.value; }
	unreachable;
}

function drawn(result: Result<void, GraphicsError>, what: string): void {
	if (!result.ok) { fail(`${what} was refused: ${result.error.toString()}`); }
}

function graphicsOf(width: float32): Graphics3D {
	let graphics: Graphics3D = Graphics3D.create();
	drawn(lineStyle(graphics, width, 0xff0000, 1.0), "lineStyle");
	drawn(moveTo(graphics, -1.0, 0.5, -NEAR_DEPTH), "the near moveTo");
	drawn(lineTo(graphics, 1.0, 0.5, -NEAR_DEPTH), "the near lineTo");
	drawn(moveTo(graphics, -4.0, -2.0, -FAR_DEPTH), "the far moveTo");
	drawn(lineTo(graphics, 4.0, -2.0, -FAR_DEPTH), "the far lineTo");
	return graphics;
}

function reserved(values: Readonly<Span<float32>>): UniformBlock {
	const block: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, LINE_UNIFORM_LENGTH);
	if (!block.ok) { unreachable; }
	if (!writeUniforms(context, block.value, values).ok) { unreachable; }
	return block.value;
}

function lineMaterial(graphics: Graphics3D): MaterialId {
	let values: Vec<float32> = new Array(LINE_UNIFORM_LENGTH);
	writeLineBlock(graphics, camera(), viewOf(), WHITE, values);
	const id: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.ofKind(Program.Line, MaterialKind.Opaque),
		uniforms: reserved(values),
	});
	if (id.ok) { return id.value; }
	fail(`the line material was refused: ${id.error.toString()}`);
	unreachable;
}

function upload(graphics: Graphics3D): MeshId {
	const uploaded: Result<MeshId, MeshUploadError> = addMeshData(context, graphics.data);
	if (uploaded.ok) { return uploaded.value; }
	fail(`the lines' mesh was refused: ${uploaded.error.toString()}`);
	unreachable;
}

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	gfxSetup();
	for (const at of STAGES) {
		const graphics: Graphics3D = graphicsOf(at.width);
		lines.push(lineMaterial(graphics));
		items.push({ mesh: upload(graphics), material: lines[lines.length - 1],
			world: identity(), order: 0 });
	}
}

function channel(x: int32, y: int32, shift: int64): float32 {
	return ((voidCapturePixel(0, x, y) >> shift) & 255) as float32;
}

function isLine(x: int32, y: int32): boolean {
	return channel(x, y, 24) > 200.0 && channel(x, y, 16) < 50.0 && channel(x, y, 8) < 50.0;
}

// The rows of column `x` from `top` to `bottom` the line covers; they must run unbroken.
function coveredRows(x: int32, top: int32, bottom: int32, what: string): int32 {
	let first: int32 = -1;
	let last: int32 = -1;
	for (let y = top; y < bottom; y++) {
		if (!isLine(x, y)) { continue; }
		if (first < 0) { first = y; }
		if (last >= 0 && y != last + 1) { fail(`${what} at column ${x} breaks at row ${y}`); }
		last = y;
	}
	if (first < 0) { fail(`${what} drew nothing at column ${x}`); }
	return last - first + 1;
}

// A level line's pixel rows are its width at either depth, within the one row a rasterized edge
// can add or drop; the grey between the lines and past their ends stays the clear colour.
function check(at: Stage): void {
	const middle: int32 = HEIGHT / 2;
	for (const x of [WIDTH / 2, WIDTH / 2 - 60, WIDTH / 2 + 60]) {
		const near: int32 = coveredRows(x, 0, middle, "the near line");
		const far: int32 = coveredRows(x, middle, HEIGHT, "the far line");
		const width: int32 = at.width as int32;
		if (Math.abs(near - width) > 1 || Math.abs(far - width) > 1) {
			fail(`at column ${x} the near line is ${near} rows and the far ${far}, not ${width}`);
		}
	}
	const back: float32 = channel(10, middle, 16);
	if (Math.abs(back - channel(10, middle, 24)) > 3.0 || back < 20.0) {
		fail(`the clear colour drew green ${back}, not grey`);
	}
	if (isLine(WIDTH - 10, 78) || isLine(WIDTH - 10, 162)) { fail("a line ran past its end"); }
	console.log(`graphicsLine: ${at.name}: near ${coveredRows(WIDTH / 2, 0, middle, "near")} ` +
		`rows, far ${coveredRows(WIDTH / 2, middle, HEIGHT, "far")} rows`);
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("the framebuffer size changed"); }
	if (stage < (STAGES.length as int32)) {
		const at: Stage = STAGES[stage];
		viewOf().writeCameraBlock(cameraValues);
		let one: Vec<DrawItem> = [items[stage]];
		const done: Result<int32, ForwardError> =
			renderFrame(forward, one, cameraValues, lights, WIDTH, HEIGHT);
		if (!done.ok) { fail(`forward refused: ${done.error.toString()}`); }
		if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
		check(at);
		stage = stage + 1;
		return;
	}
	console.log("PASS graphicsLine: Graphics3D's lines keep their width in pixels near and far, " +
		"in lineStyle's colour, and stop at their ends");
	voidCaptureExit(0);
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
