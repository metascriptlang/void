// Real-renderer RGBA/visibility/width/motion/lifetime pins, never a phone performance claim.
import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Vec3, Vec4, vec3, identity, translation } from "../../src/math/math3d";
import { endPass, commit } from "../../src/gpu/door";
import { PipelineCache, pipelineFor, closePipelines } from "../../src/gpu/pipeline";
import { RenderTarget, NO_DEPTH, beginPass } from "../../src/gpu/target";
import { PixelFormat, LoadAction } from "../../src/gpu/door";
import { outlineReferenceProgram, outlineReferenceLayout, outlineReferenceDraw, outlineReferenceClose } from "./forwardOutlineReference.h";
import { SWAPCHAIN_LAYOUT, beginScreenPass } from "../../src/gpu/target";
import { drawScreen, closePrepare, openScreen } from "../../src/void3d/renderer";
import { screenState } from "../../src/void3d/screenFx";
import { RenderState } from "../../src/gpu/state";
import { MeshData, MeshError, Rgba, addQuad } from "../../src/void3d/meshData";
import { Material, Phase, UniformBlock } from "../../src/void3d/material";
import {
	Program, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH,
	VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import {
	DrawContext, DrawItem, MeshId, MaterialId, MaterialError, MeshUploadError,
	addMeshData, addMaterial, reserveUniforms, writeUniforms,
} from "../../src/void3d/draw";
import { UniformError } from "../../src/void3d/uniformPool";
import { Camera3D, CameraView, ProjectionKind } from "../../src/void3d/camera";
import { LowResView } from "../../src/void3d/blit";
import { ForwardOutlineSettings, OUTLINE_SCREEN_LAYOUT, fxaaCoverage } from "../../src/void3d/forwardOutline";
import {
	ForwardRenderer, ForwardError, FORWARD_OUTLINE_UNIFORM_LENGTH, renderFrame,
	setOutlineBlend, setOutlineSettings, closeForward,
} from "../../src/void3d/forwardRenderer";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureExit, voidCaptureEnvInt,
	voidCaptureWritePng,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const FACTOR: int32 = voidCaptureEnvInt("VOID_OUTLINE_FRAMEBUFFER_FACTOR", 1);
const WIDTH: int32 = 320 * FACTOR;
const HEIGHT: int32 = 240 * FACTOR;
const CLEAR: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 0.0 };
const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const LINE: Vec4 = { x: 1.0, y: 0.5, z: 0.0, w: 0.5 };
const context: DrawContext = DrawContext.withUniformCapacity(
	FORWARD_OUTLINE_UNIFORM_LENGTH + MATERIAL_UNIFORM_LENGTH,
);
let renderer: ForwardRenderer = makeRenderer();
let rawCopy: MaterialId = { store:0,index:0,generation:0 };
let seedBytes: Vec<uint8> = new Array(WIDTH*HEIGHT);
let widthBytes: Vec<uint8> = new Array(WIDTH*HEIGHT);
let referenceBytes: Vec<uint8> = new Array(WIDTH*HEIGHT);
let referenceTarget: RenderTarget = RenderTarget.unallocated(PixelFormat.Rgba8,true);
let referencePipelines: PipelineCache = PipelineCache.empty();
let material: MaterialId = { store: 0, index: 0, generation: 0 };
let front: MeshId = { store: 0, index: 0, generation: 0 };
let back: MeshId = { store: 0, index: 0, generation: 0 };
let axis: MeshId = { store: 0, index: 0, generation: 0 };
let roundedUp: MeshId = { store: 0, index: 0, generation: 0 };
let thin: MeshId = { store: 0, index: 0, generation: 0 };
const WIDTH_PINS: Vec<float32> = [1.0,1.5,2.0,2.5,3.0,4.0,8.0,16.0];
let motionProfile: Vec<int32> = new Array(17);
let motionChanges: int32 = 0;
let nonAxis: MeshId = { store: 0, index: 0, generation: 0 };
let controlErrors: int32 = 0;
let crease: MeshId = { store: 0, index: 0, generation: 0 };
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let baseline: Vec<int64> = new Array(WIDTH * HEIGHT);
let outlined: Vec<int64> = new Array(WIDTH * HEIGHT);
let stage: int32 = 0;
let thinMass: int32 = 0;
let thinProfile: int32 = 0;
let previousMotionMass: int32 = 0;
let maxMotionDelta: int32 = 0;
let partial: int32 = 0;
let epoch: int32 = 0;

function fail(message: string): void {
	console.log(`FAIL forward outline: stage ${stage}: ${message}`);
	voidCaptureExit(1);
}

function makeRenderer(): ForwardRenderer {
	const made = ForwardRenderer.create(context, CLEAR);
	if (!made.ok) { unreachable; }
	return made.value;
}

function quad(ref mesh: MeshData, left: float32, right: float32, bottom: float32,
	top: float32, z: float32, normal: Vec3): void {
	const built: Result<int32, MeshError> = addQuad(mesh,
		vec3(left, bottom, z), vec3(right, bottom, z), vec3(right, top, z),
		vec3(left, top, z), normal, WHITE);
	if (!built.ok) { unreachable; }
}

function upload(mesh: MeshData): MeshId {
	const added: Result<MeshId, MeshUploadError> = addMeshData(context, mesh);
	if (!added.ok) { unreachable; }
	return added.value;
}

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	if (FACTOR != 1 && FACTOR != 2) { fail("framebuffer factor needs 1 or 2"); }
	gfxSetup();
	const block: Result<UniformBlock, UniformError> =
		reserveUniforms(context, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
	if (!block.ok) { unreachable; }
	const values: Vec<float32> = [1.0, 0.0, 0.0, 0.0];
	if (!writeUniforms(context, block.value, values).ok) { unreachable; }
	const added: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque), uniforms: block.value,
	});
	if (!added.ok) { unreachable; }
	material = added.value;
	const copy = addMaterial(context, Material.plain(Program.Copy,screenState(),Phase.Opaque));
	if (!copy.ok) { unreachable; }
	rawCopy = copy.value;
	let face: MeshData = MeshData.empty();
	quad(face, -1.0, 1.0, -0.75, 0.75, 0.0, vec3(0.0, 0.0, 1.0));
	front = upload(face);
	let hidden: MeshData = MeshData.empty();
	quad(hidden, -0.6, 0.6, -0.4, 0.4, -0.5, vec3(0.0, 0.0, 1.0));
	back = upload(hidden);
	let creased: MeshData = MeshData.empty();
	const left = addQuad(creased, vec3(-1.0, -0.75, 0.0), vec3(0.0, -0.75, 0.0),
		vec3(0.3, 0.75, 0.0), vec3(-0.7, 0.75, 0.0), vec3(0.0, 0.0, 1.0), WHITE);
	const right = addQuad(creased, vec3(0.0, -0.75, 0.0), vec3(1.0, -0.75, 0.0),
		vec3(1.3, 0.75, 0.0), vec3(0.3, 0.75, 0.0), vec3(0.8, 0.0, 0.6), WHITE);
	if (!left.ok || !right.ok) { unreachable; }
	crease = upload(creased);
	let straight: MeshData = MeshData.empty();
	quad(straight, -1.0, 0.0, -0.75, 0.75, 0.0, vec3(0.0, 0.0, 1.0));
	quad(straight, 0.0, 1.0, -0.75, 0.75, 0.0, vec3(0.8, 0.0, 0.6));
	axis = upload(straight);
	let tilted: MeshData = MeshData.empty();
	const built = addQuad(tilted, vec3(-1.0,-0.75,0.31448545), vec3(1.0,-0.75,-0.31448545),
		vec3(1.0,0.75,-0.31448545), vec3(-1.0,0.75,0.31448545), vec3(0.3,0.0,0.9539392), WHITE);
	if (!built.ok) { unreachable; }
	nonAxis = upload(tilted);
	let up: MeshData = MeshData.empty();
	const addedUp = addQuad(up, vec3(-1.0,-0.75,1.0), vec3(1.0,-0.75,-1.0),
		vec3(1.0,0.75,-1.0), vec3(-1.0,0.75,1.0), vec3(0.70710678,0.0,0.70710678), WHITE);
	if (!addedUp.ok) { unreachable; }
	roundedUp = upload(up);
	let narrow: MeshData = MeshData.empty();
	quad(narrow,-0.01,0.01,-0.25,0.25,0.0,vec3(0.0,0.0,1.0));
	thin = upload(narrow);
	items = [item(back), item(front)];
	// One directional light, no points/shadows/ambient.
	lights[6] = 1.0; lights[7] = 1.0;
	lights[8] = 1.0; lights[9] = 1.0; lights[10] = 1.0;
	setOutlineSettings(renderer, { ...ForwardOutlineSettings.defaults(), color: LINE });
}

function item(mesh: MeshId): DrawItem {
	return { mesh: mesh, material: material, world: identity() };
}

function channel(pixel: int64, shift: int32): int32 {
	return ((pixel >> (shift as int64)) & (255 as int64)) as int32;
}

function checkLine(pixel: int64): void {
	const alpha: int32 = channel(pixel, 0);
	const color: Vec4 = renderer.outlineSettings.color;
	if ((alpha == 0 && pixel != 0) ||
		Math.abs(channel(pixel,24) - (color.x * alpha)) > 1 ||
		Math.abs(channel(pixel,16) - (color.y * alpha)) > 1 ||
		Math.abs(channel(pixel,8) - (color.z * alpha)) > 1 || alpha > Math.ceil(color.w * 255.0)) {
		fail(`line RGBA not premultiplied once: ${pixel}`);
	}
}

function view(width: int32, height: int32, motion: float32): CameraView {
	const camera: Camera3D = {
		position: vec3(motion, 0.0, 4.0), yaw: 0.0, pitch: 0.0,
		nearPlane: stage == 25 ? 0.5 : 0.1, farPlane: stage == 25 ? 50.0 : 10.0,
		projection: stage == 26 ?
			{ kind: ProjectionKind.Orthographic, worldPerTexel: 0.01, snap: false } :
			{ kind: ProjectionKind.Perspective, fovY: stage == 25 ? 0.8 : 1.0471976 },
	};
	const resolved = camera.resolve(width, height);
	if (!resolved.ok) { unreachable; }
	return resolved.value;
}

function at(view: CameraView, point: Vec3, width: int32, height: int32): int64 {
	const screen: LowResView = {
		width: width, height: height, scale: 1, offsetX: 0.0, offsetY: 0.0,
	};
	const pixel: Vec3 = view.project(point, screen, true);
	return voidCapturePixel(0, pixel.x as int32, pixel.y as int32);
}

function profile(view: CameraView, width: int32, height: int32): int32 {
	const screen: LowResView = {
		width: width, height: height, scale: 1, offsetX: 0.0, offsetY: 0.0,
	};
	const p: Vec3 = view.project(vec3(-0.85, 0.0, 0.0), screen, true);
	let mass: int32 = 0;
	for (let dx = -10; dx <= 10; dx++) {
		mass += channel(voidCapturePixel(0, (p.x as int32) + dx, p.y as int32), 0);
	}
	return mass;
}

function hiddenProbe(view: CameraView, width: int32, height: int32): int64 {
	const screen: LowResView = {
		width: width, height: height, scale: 1, offsetX: 0.0, offsetY: 0.0,
	};
	const edge: Vec3 = view.project(vec3(-0.6, 0.0, -0.5), screen, true);
	const requested: float32 = renderer.outlineSettings.pixelWidth;
	const inset: float32 = requested * 0.5;
	const x: int32 = (edge.x + inset) as int32;
	const pixel: int64 = voidCapturePixel(0, x, edge.y as int32);
	console.log(`outline hidden control: factor${FACTOR} stage${stage} edge${edge.x},${edge.y} ` +
		`width${requested} inset${inset} pixel${x} rgba${pixel} alpha${channel(pixel,0)}`);
	return pixel;
}

function creaseProfile(view: CameraView, width: int32, height: int32): void {
	const screen: LowResView = {
		width: width, height: height, scale: 1, offsetX: 0.0, offsetY: 0.0,
	};
	const center: Vec3 = view.project(vec3(0.0,0.0,0.0), screen, true);
	let sum: int32 = 0;
	let peak: int32 = 0;
	for (let dx = -10; dx <= 10; dx++) {
		const alpha: int32 = channel(voidCapturePixel(0, (center.x as int32)+dx,
			center.y as int32), 0);
		sum += alpha;
		peak = Math.max(peak, alpha);
	}
	const requested: int32 = renderer.outlineSettings.pixelWidth as int32;
	console.log(`outline crease profile: factor${FACTOR} width${requested} sum${sum} peak${peak}`);
	if (peak < 127 || peak > 128 || sum < (requested == 2 ? 254 : 380) ||
		sum > (requested == 2 ? 256 : 386)) {
		controlErrors++;
		console.log("CONTROL FAIL forward outline: axis crease framebuffer width");
	}
}

function movingProfile(view: CameraView, width: int32, height: int32): void {
	const screen: LowResView = { width: width, height: height, scale: 1, offsetX:0.0, offsetY:0.0 };
	const center: Vec3 = view.project(vec3(0.15,0.0,0.0),screen,true);
	let sum: int32 = 0;
	let weighted: float32 = 0.0;
	let delta: int32 = 0;
	for (let dx = -8; dx <= 8; dx++) {
		const x: int32 = (width / 2) + 8 * FACTOR + dx;
		const alpha: int32 = channel(voidCapturePixel(0,x,center.y as int32),0);
		sum += alpha;
		weighted += (alpha * x) as float32;
		if (stage > 16) { delta += Math.abs(alpha-motionProfile[dx+8]) as int32; }
		motionProfile[dx+8] = alpha;
	}
	if (delta > 0) { motionChanges++; }
	console.log(`outline moving AA: factor${FACTOR} stage${stage} ideal${center.x} ` +
		`centroid${sum > 0 ? weighted / (sum as float32) : 0.0} profileByteDelta${delta}`);
}

function copyCapture(view: uint32): void {
	context.materials[rawCopy.index].texture0 = view;
	context.materials[rawCopy.index].sampler0 = renderer.sampler.asHandle();
	closePrepare(renderer.core);
	beginScreenPass(CLEAR);
	openScreen(renderer.core);
	if (!drawScreen(renderer.core,rawCopy,SWAPCHAIN_LAYOUT).ok) { fail("raw Copy refused"); }
	endPass();
	commit();
	if (voidCaptureGrab(1) == 0) { fail("raw Copy readback refused"); }
}

function rawSample(data: Vec<uint8>, x: float32, y: float32): float32 {
	const left: int32 = Math.floor(x) as int32;
	const top: int32 = Math.floor(y) as int32;
	const fx: float32 = x - (left as float32);
	const fy: float32 = y - (top as float32);
	const x0: int32 = Math.max(0,Math.min(WIDTH-1,left)) as int32;
	const x1: int32 = Math.max(0,Math.min(WIDTH-1,left+1)) as int32;
	const y0: int32 = Math.max(0,Math.min(HEIGHT-1,top)) as int32;
	const y1: int32 = Math.max(0,Math.min(HEIGHT-1,top+1)) as int32;
	const a: float32 = (data[y0*WIDTH+x0] as float32) / 255.0;
	const b: float32 = (data[y0*WIDTH+x1] as float32) / 255.0;
	const c: float32 = (data[y1*WIDTH+x0] as float32) / 255.0;
	const d: float32 = (data[y1*WIDTH+x1] as float32) / 255.0;
	return (a+(b-a)*fx)*(1.0-fy)+(c+(d-c)*fx)*fy;
}

function byteLower(value: float32): int32 {
	return Math.max(0,Math.ceil(value-1.0)) as int32;
}
function byteUpper(value: float32): int32 {
	return Math.min(255,Math.floor(value+1.0)) as int32;
}

function widthProfile(view: CameraView, width: int32, height: int32, variant: int32): void {
	const screen: LowResView = { width:width,height:height,scale:1,offsetX:0.0,offsetY:0.0 };
	const center: Vec3 = view.project(variant == 0 ? vec3(-1.0,0.0,0.0) :
		(variant == 1 ? vec3(0.0,0.0,0.0) : vec3(0.15,0.0,0.0)), screen, true);
	const requested: float32 = renderer.outlineSettings.pixelWidth;
	if (renderer.outline === null) { unreachable; }
	const pass = renderer.outline;
	copyCapture(pass.mask.asTexture());
	if (stage == 56 && voidCaptureBackend() == 1) {
		console.log(`outline sampler diagnostic: stage${stage} backend1 dims${WIDTH}x${HEIGHT} ` +
			`originTopLeft lineAlpha${LINE.w} width${requested} radius7 circles48 linearClamp mip0`);
		if (voidCaptureWritePng(1,`out/tmp/forwardOutline/referenceSampler/seedCurrentFactor${FACTOR}.png`) == 0) {
			fail("seed diagnostic PNG write refused");
		}
	}
	for (let y=0;y<HEIGHT;y++) {
		for (let x=0;x<WIDTH;x++) {
			const pixel: int64 = voidCapturePixel(1,x,y);
			const value: int32 = channel(pixel,24);
			if (value != 0 && value != 255) { fail("raw seed is not binary coverage"); }
			if (channel(pixel,16)!=value || channel(pixel,8)!=value || channel(pixel,0)!=value) {
				fail("raw seed RGBA is not scalar data");
			}
			seedBytes[y*WIDTH+x] = value as uint8;
		}
	}
	copyCapture(requested == 2.0 ? pass.mask.asTexture() : pass.width.asTexture());
	if (stage == 56 && voidCaptureBackend() == 1 &&
		voidCaptureWritePng(1,`out/tmp/forwardOutline/referenceSampler/widthCurrentFactor${FACTOR}.png`) == 0) {
		fail("width diagnostic PNG write refused");
	}
	for (let y=0;y<HEIGHT;y++) {
		for (let x=0;x<WIDTH;x++) {
			const pixel: int64 = voidCapturePixel(1,x,y);
			const value: int32 = channel(pixel,24);
			if (channel(pixel,16)!=value || channel(pixel,8)!=value || channel(pixel,0)!=value) {
				fail("raw width RGBA is not scalar data");
			}
			widthBytes[y*WIDTH+x] = value as uint8;
		}
	}
	const widened: (x:float32,y:float32)=>float32 = (x,y)=>rawSample(widthBytes,x,y);
	referenceTarget.resize(WIDTH,HEIGHT);
	const referencePipeline: uint32 = pipelineFor(referencePipelines,outlineReferenceProgram(),
		outlineReferenceLayout(),false,screenState(),OUTLINE_SCREEN_LAYOUT);
	const radius: float32 = (Math.abs(requested-2.0)*0.5) as float32;
	beginPass([referenceTarget.asColor(LoadAction.DontCare,CLEAR)],NO_DEPTH);
	outlineReferenceDraw(referencePipeline,pass.mask.asTexture(),pass.linearSampler.asHandle(),
		radius/(WIDTH as float32),radius/(HEIGHT as float32),requested<2.0?1.0:0.0);
	endPass();
	copyCapture(referenceTarget.asTexture());
	let referenceErrors: int32 = 0;
	for (let y=0;y<HEIGHT;y++) {
		for (let x=0;x<WIDTH;x++) {
			const pixel: int64 = voidCapturePixel(1,x,y);
			const value: int32 = channel(pixel,24);
			referenceBytes[y*WIDTH+x] = value as uint8;
			if (channel(pixel,16)!=value || channel(pixel,8)!=value || channel(pixel,0)!=value) {
				fail("independent reference RGBA not scalar");
			}
			if (widthBytes[y*WIDTH+x] != value) {
				if (referenceErrors < 8) {
					console.log(`outline independentGPU mismatch ${x},${y}: production${widthBytes[y*WIDTH+x]} ref${value}`);
				}
				referenceErrors++;
			}
		}
	}
	if (stage == 56) {
		const corrupted: Vec<float32> = [radius+1.0,0.0,0.0,0.0];
		if (!writeUniforms(context,pass.widthBlock,corrupted).ok) { unreachable; }
		pass.drawWidth(renderer.core);
		copyCapture(pass.width.asTexture());
		let negative: int32 = 0;
		for (let y=0;y<HEIGHT;y++) {
			for (let x=0;x<WIDTH;x++) {
				if (channel(voidCapturePixel(1,x,y),24) != referenceBytes[y*WIDTH+x]) { negative++; }
			}
		}
		if (negative == 0) { fail("production-only radius fault escaped independent reference"); }
		if (!writeUniforms(context,pass.widthBlock,pass.widthValues).ok) { unreachable; }
		pass.drawWidth(renderer.core);
		copyCapture(pass.width.asTexture());
		for (let y=0;y<HEIGHT;y++) {
			for (let x=0;x<WIDTH;x++) {
				if (channel(voidCapturePixel(1,x,y),24) != widthBytes[y*WIDTH+x]) {
					fail("production radius fault restore changed original width bytes");
				}
			}
		}
		console.log(`outline independentGPU negativecontrol: offaxiswidth16 productionradius+1 differences${negative}, restoredbyteexact`);
	}
	let sum: int32 = 0;
	let components: string = "";
	for (let dx=-20;dx<=20;dx++) {
		const x: int32 = (center.x as int32)+dx;
		const y: int32 = center.y as int32;
		const pixel: int64 = voidCapturePixel(0,x,y);
		const alpha: int32 = channel(pixel,0);
		const coverage: float32 = fxaaCoverage(widened,x as float32,y as float32);
		const value: float32 = coverage * LINE.w * 255.0;
		if ((coverage == 0.0 && pixel != 0) || alpha < byteLower(value) || alpha > byteUpper(value)) {
			console.log(`outline FXAA byte mismatch: ${x},${y} ref${value} actual${alpha}`);
			referenceErrors++;
		}
		sum += alpha;
		if (alpha > 0) { components += `${alpha},`; }
	}
	if (variant < 2) {
		const pin: int32 = (stage-33)%8;
		const lower: Vec<int32> = [126,190,254,316,380,508,1016,2032];
		const upper: Vec<int32> = [130,194,256,322,386,512,1024,2048];
		if (sum < lower[pin] || sum > upper[pin]) { referenceErrors++; }
	}
	console.log(`outline width reference: factor${FACTOR} variant${variant} requested${requested} ` +
		`sum${sum} components${components} errors${referenceErrors}`);
	if (referenceErrors > 0) {
		controlErrors++; console.log("CONTROL FAIL forward outline: reference width/FXAA bytes");
	}
	copyCapture(renderer.colorTarget.asTexture());
	for (let y=0;y<HEIGHT;y++) {
		for (let x=0;x<WIDTH;x++) {
			if (voidCapturePixel(1,x,y) != voidCapturePixel(0,x,y)) {
				fail("raw inspection did not restore final public image byte-identically");
			}
		}
	}
}

function frame(): void {
	if (stage == 27) {
		closeForward(renderer);
		const fresh = ForwardRenderer.create(context, CLEAR);
		if (!fresh.ok) { fail("close did not release uniform holders"); unreachable; }
		renderer = fresh.value;
		setOutlineSettings(renderer, { ...ForwardOutlineSettings.defaults(), color: LINE });
		items = [item(back), item(front)];
	}
	if (stage == 28 || stage == 29) {
		items = [item(axis)];
		setOutlineSettings(renderer, { ...ForwardOutlineSettings.defaults(), color: LINE,
			pixelWidth: stage == 28 ? 2.0 : 3.0 });
	}
	if (stage == 30) {
		items = [item(nonAxis)];
		setOutlineSettings(renderer, { ...ForwardOutlineSettings.defaults(), color: LINE,
			normalThreshold: 0.9999, depthThreshold: 1.0 });
	}
	if (stage == 31 || stage == 32) {
		items = [{ ...item(front), world: translation(0.0,0.0,-5.9) }];
		setOutlineSettings(renderer, { ...ForwardOutlineSettings.defaults(), color: LINE });
	}
	if (stage >= 33 && stage < 57) {
		const variant: int32 = (stage-33) / 8;
		items = [item(variant == 0 ? front : (variant == 1 ? axis : crease))];
		setOutlineSettings(renderer, { ...ForwardOutlineSettings.defaults(), color: LINE,
			pixelWidth: WIDTH_PINS[(stage-33)%8] });
	}
	if (stage == 57 || stage == 58) {
		items = [item(stage == 57 ? nonAxis : roundedUp)];
		setOutlineSettings(renderer, { ...ForwardOutlineSettings.defaults(), color: LINE,
			normalThreshold: stage == 57 ? 1.0 : 0.9999, depthThreshold: 1.0 });
	}
	if (stage == 59 || stage == 60) {
		items = stage == 59 ? [item(back),item(front)] : [item(back)];
		setOutlineSettings(renderer, { ...ForwardOutlineSettings.defaults(), color: LINE, pixelWidth:16.0 });
	}
	if (stage >= 61) {
		items = [item(stage == 61 ? thin : front)];
		setOutlineSettings(renderer, { ...ForwardOutlineSettings.defaults(), pixelWidth:1.0,
			color: stage == 62 ? { x:1.0,y:0.5,z:0.0,w:0.0 } :
				(stage == 63 ? { x:0.0,y:0.0,z:0.0,w:0.5 } : LINE) });
	}
	if (stage == 0) { console.log(`FAIL forward outline diagnostic: factor${FACTOR} request${WIDTH}x${HEIGHT} actualfb${fbWidth()}x${fbHeight()}`); }
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("unexpected framebuffer size"); }
	let blend: float32 = 1.0;
	if (stage == 0 || stage == 1 || stage == 4 || stage == 31) { blend = 0.0; }
	if (stage == 3) { blend = 0.5; }
	if (stage != 0) { setOutlineBlend(renderer, blend); }
	if (stage == 5) { items = [item(back)]; }
	if (stage == 6) { items = [item(crease)]; }
	if (stage == 7) {
		setOutlineSettings(renderer, { ...renderer.outlineSettings, pixelWidth: 3.0 });
	}
	if (stage == 8) {
		setOutlineSettings(renderer, { ...renderer.outlineSettings, pixelWidth: 2.0 });
	}
	const resized: boolean = stage == 8;
	const width: int32 = resized ? WIDTH + 40 : WIDTH;
	const height: int32 = resized ? HEIGHT + 20 : HEIGHT;
	const motion: float32 = stage >= 9 && stage <= 24 ? ((stage - 9) as float32) * 0.002 : 0.0;
	const current: CameraView = view(width, height, motion);
	current.writeCameraBlock(cameraValues);
	const drawn: Result<int32, ForwardError> =
		renderFrame(renderer, items, cameraValues, lights, width, height);
	if (!drawn.ok) { fail(`frame refused: ${drawn.error.toString()}`); }
	if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
	let mass: int32 = 0;
	let innerEdges: int32 = 0;
	for (let y = 0; y < HEIGHT; y++) {
		for (let x = 0; x < WIDTH; x++) {
			const i: int32 = y * WIDTH + x;
			const pixel: int64 = voidCapturePixel(0, x, y);
			if (stage == 0) { baseline[i] = pixel; }
			if ((stage == 1 || stage == 4) && pixel != baseline[i]) {
				fail("unused/zero/re-disabled frame is not byte-identical");
			}
			if (stage == 2) { outlined[i] = pixel; }
			if (stage == 3) {
				for (const shift of [0, 8, 16, 24]) {
					const expected: int32 = (channel(baseline[i], shift) +
						channel(outlined[i], shift)) / 2;
					if (Math.abs(channel(pixel, shift) - expected) > 1) {
						fail("intermediate output is not straight full-RGBA mix");
					}
				}
			}
			if (blend == 1.0) {
				checkLine(pixel);
				const alpha: int32 = channel(pixel, 0);
				mass += alpha;
				if (alpha > 0 && alpha < 120) { partial++; }
				if (x > WIDTH / 2 - 20 && x < WIDTH / 2 + 20 &&
					y > HEIGHT / 2 - 20 && y < HEIGHT / 2 + 20) { innerEdges += alpha; }
			}
		}
	}
	if (stage == 0 && channel(at(current, vec3(-0.4, 0.0, 0.0), width, height), 0) != 255) {
		fail("opaque baseline control absent");
	}
	if (stage == 2) {
		if (mass == 0 || innerEdges != 0 ||
			at(current, vec3(-0.4, 0.0, 0.0), width, height) != 0) {
			fail("flat faces not transparent, hidden back edge leaked, or silhouette absent");
		}
	}
	const hidden: int64 = stage == 2 || stage == 5 ? hiddenProbe(current, width, height) : 0;
	if (stage == 2 && hidden != 0) { fail("back edge emitted through invisible front face"); }
	if (stage == 5 && (mass == 0 || channel(hidden, 0) == 0)) {
		fail("removing occluder did not expose pinned back edge");
	}
	if (stage == 6) {
		if (innerEdges == 0) { fail("normal crease producer/extractor inactive"); }
		thinMass = mass;
		thinProfile = profile(current, width, height);
		console.log(`outline silhouette profile: factor${FACTOR} width2 mass${thinProfile}`);
		if (thinProfile < 128 || thinProfile > 448) { fail("2px framebuffer profile wrong"); }
	}
	if (stage == 7) {
		console.log(`outline silhouette profile: factor${FACTOR} width3 mass${profile(current,width,height)}`);
	}
	if (stage == 7 && (mass <= thinMass || profile(current, width, height) <= thinProfile)) { fail("framebuffer pixel width did not widen lines"); }
	if (stage == 8) {
		if (renderer.targetEpoch <= epoch || renderer.colorTarget.width != width || mass == 0 ||
			Math.abs(profile(current, width, height) - thinProfile) > 128) {
			fail("resize did not renew full-frame output/resources");
		}
	}
	if (stage >= 9 && stage <= 24) {
		if (mass == 0) { fail("slow-motion lines disappeared"); }
		if (previousMotionMass > 0) {
			maxMotionDelta = Math.max(maxMotionDelta, Math.abs(mass - previousMotionMass) as int32);
			if (Math.abs(mass - previousMotionMass) > previousMotionMass / 3) {
				fail("slow-motion coverage mass jumps over one third");
			}
		}
		previousMotionMass = mass;
	}
	if (stage >= 25 && stage < 30 && (mass == 0 || voidCapturePixel(0, 0, 0) != 0)) {
		fail("projection/recreate variant lost lines or leaked alpha into uncovered pixels");
	}
	if (stage == 27 && renderer.targetEpoch != 1) { fail("fresh issuer did not allocate anew"); }
	if (stage == 2 && renderer.outline !== null && renderer.outline.width.image != 0) {
		fail("basewidth2 allocated extra width target");
	}
	if (stage == 28 || stage == 29) { creaseProfile(current,width,height); }
	if (stage >= 33 && stage < 57) { widthProfile(current,width,height,(stage-33)/8); }
	if (stage >= 16 && stage <= 24) {
		movingProfile(current,width,height);
		widthProfile(current,width,height,2);
	}
	if (stage == 57 || stage == 58) {
		const flat: int64 = at(current,vec3(0.0,0.0,0.0),width,height);
		console.log(`outline flat identity: factor${FACTOR} stage${stage} rgba${flat}`);
		if (flat != 0) { controlErrors++; console.log("CONTROL FAIL forward outline: flat identity"); }
	}
	if (stage == 59 || stage == 60) {
		const hidden: int64 = hiddenProbe(current,width,height);
		if ((stage == 59 && hidden != 0) || (stage == 60 && channel(hidden,0) == 0)) {
			controlErrors++; console.log("CONTROL FAIL forward outline: wide hidden/removal control");
		}
	}
	if ((stage == 61 && mass == 0) || (stage == 62 && mass != 0) || (stage == 63 && mass == 0)) {
		controlErrors++; console.log("CONTROL FAIL forward outline: thin/zeroalpha/blackcolor");
	}
	if (stage == 30) {
		const flat: int64 = at(current, vec3(0.0,0.0,0.0), width,height);
		console.log(`outline non-axis flat: factor${FACTOR} normal0.3,0,0.9539392 dotThreshold0.9999 rgba${flat} mass${mass}`);
		if (flat != 0) {
			controlErrors++;
			console.log("CONTROL FAIL forward outline: quantized non-axis flat normal");
		}
	}
	if (stage == 31) {
		const alpha: int32 = channel(at(current,vec3(0.0,0.0,-5.9),width,height),0);
		console.log(`outline far opaque baseline: factor${FACTOR} distance9.9 alpha${alpha}`);
		if (alpha != 255) { fail("far opaque baseline control absent"); }
	}
	if (stage == 32) {
		console.log(`outline far silhouette: factor${FACTOR} distance9.9 near0.1 far10 mass${mass}`);
		if (mass == 0) {
			controlErrors++;
			console.log("CONTROL FAIL forward outline: far opaque occupancy silhouette");
		}
	}
	epoch = renderer.targetEpoch;
	stage++;
	if (stage < 64) { return; }
	referenceTarget.close();
	closePipelines(referencePipelines);
	outlineReferenceClose();
	if (controlErrors > 0) { fail(`independent raster controls failed: ${controlErrors}`); }
	if (partial == 0) { fail("AA coverage control has no partial-alpha pixels"); }
	closeForward(renderer);
		console.log(`PASS forward outline: factor ${FACTOR}, disabled byte identity, RGBA mix, ` +
		`nearest-opaque visibility, crease, width, resize/close/recreate; partial ${partial}, ` +
		`motion mass maxdelta ${maxMotionDelta} (not a temporal/phone performance verdict)`);
	voidCaptureExit(0);
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
