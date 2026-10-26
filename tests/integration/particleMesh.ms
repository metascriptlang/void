import { gfxSetup, fbWidth, fbHeight } from "../../src/host/gpu";
import { Vec3, Vec4, vec3, identity } from "../../src/math/math3d";
import { FilterMode, Wrap, Face } from "../../src/gpu/state";
import {
	Program, VertexLayout, MATERIAL_UNIFORM_SLOT, UNLIT_MATERIAL_UNIFORM_LENGTH,
	VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH,
} from "../../src/void3d/gpu3d";
import { Material, MaterialKind } from "../../src/void3d/material";
import { MeshData, Rgba, addTexturedQuad } from "../../src/void3d/meshData";
import {
	DrawContext, DrawItem, MeshId, MaterialId, addMaterial, addMeshData, addStreamMesh,
	writeStream, addTexture, releaseTexture, releaseMaterial, releaseMesh, reserveUniforms,
	writeUniforms, closeContext,
} from "../../src/void3d/draw";
import { ParticleSystemAsset, SimulationSpace, RenderMode } from "../../src/particles/asset";
import { constantCurve, constantColor, rgbaColor } from "../../src/particles/curve";
import { ParticleSystem, playSystem, updateSystem, POS_X, POS_Y, POS_Z } from "../../src/particles/system";
import { ParticleWriter3D, PARTICLE_MESH_INSTANCE_STRIDE } from "../../src/void3d/particleWriter";
import {
	MeshDrawOrder, MeshRun, meshIndexOf, writeMeshParticles,
} from "../../src/void3d/particleMeshWriter";
import { Camera3D, CameraView, ProjectionKind } from "../../src/void3d/camera";
import { LowResView } from "../../src/void3d/blit";
import {
	ForwardRenderer, FORWARD_UNIFORM_LENGTH, closeForward, renderFrame as renderForward,
} from "../../src/void3d/forwardRenderer";
import {
	PixelArtRenderer, PixelArtSettings, PixelArtLook, PIXEL_ART_UNIFORM_LENGTH,
	closePixelArt, renderFrame as renderPixelArt,
} from "../../src/void3d/pixelArtRenderer";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureEnvInt, voidCaptureExit,
	voidCaptureWritePng,
} from "../capture/capture.h";

@include("../../src/host/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

// Two quads, a red and a blue mesh, drawn as Mesh-mode particles: grouped by mesh for an opaque
// material, in draw order with a run per mesh for a blended one (docs/PARTICLES-RENDER.md A.2.1).
// The control draws every run from the stream's first instance, which a run past the first
// shows as its particle missing.
const WIDTH: int32 = 320;
const HEIGHT: int32 = 240;
const CAPACITY: int32 = 2;
const GREY: Vec4 = { x: 0.2, y: 0.2, z: 0.2, w: 1 };
const SCREEN: LowResView = { width: WIDTH, height: HEIGHT, scale: 1, offsetX: 0, offsetY: 0 };
const RED: Rgba = { red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0 };
const BLUE: Rgba = { red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0 };
const AWAY: Vec3 = { x: 100.0, y: 0.0, z: 0.0 };
let pixelArt: boolean = voidCaptureEnvInt("VOID_PARTICLE_MESH_PIXEL_ART", 0) != 0;
let control: boolean = voidCaptureEnvInt("VOID_PARTICLE_MESH_CONTROL", 0) != 0;
let context = DrawContext.withUniformCapacity(
	FORWARD_UNIFORM_LENGTH + PIXEL_ART_UNIFORM_LENGTH + 2 * UNLIT_MATERIAL_UNIFORM_LENGTH,
);
let forward: ForwardRenderer | null = null;
let pixel: PixelArtRenderer | null = null;
let system: ParticleSystem = makeSystem();
let writer: ParticleWriter3D = ParticleWriter3D.create();
let meshes: Vec<MeshId> = [];
let materials: Vec<MaterialId> = [];
let stream: MeshId = { store: 0, index: -1, generation: 0 };
let instances: Vec<float32> = new Array(CAPACITY * PARTICLE_MESH_INSTANCE_STRIDE);
let runs: Vec<MeshRun> = [
	{ mesh: 0, count: 0 }, { mesh: 0, count: 0 }, { mesh: 0, count: 0 }, { mesh: 0, count: 0 },
];
let bounds: Vec<Vec3> = [vec3(1.0, 1.0, 0.0), vec3(1.0, 1.0, 0.0)];
let items: Vec<DrawItem> = [];
let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let redSlot: int32 = -1;
let blueSlot: int32 = -1;
let stage: int32 = 0;
let failedChecks: int32 = 0;

function fail(message: string): void {
	console.log(`FAIL particle mesh: pixelArt=${pixelArt} control=${control} stage=${stage}: ` +
		message);
	voidCaptureExit(1);
}

function makeSystem(): ParticleSystem {
	let a = ParticleSystemAsset.defaults();
	a.main.duration = 10.0;
	a.main.maxParticles = CAPACITY;
	a.main.startLifetime = constantCurve(5.0);
	a.main.startSpeed = constantCurve(0.0);
	a.main.simulationSpace = SimulationSpace.World;
	a.main.startSize3D = true;
	a.main.startSizeX = constantCurve(0.6);
	a.main.startSizeY = constantCurve(0.6);
	a.main.startSizeZ = constantCurve(0.6);
	a.main.startColor = constantColor(rgbaColor(1.0, 1.0, 1.0, 0.5));
	a.shape.enabled = false;
	a.emission.rateOverTime = constantCurve(1000.0);
	a.renderer.renderMode = RenderMode.Mesh;
	a.renderer.meshCount = 2;
	a.renderer.meshWeights = [1.0, 1.0, 0.0, 0.0];
	const made = ParticleSystem.create(a, 23);
	if (!made.ok) { unreachable; }
	let sys = made.value;
	sys.clock.fixedStep = 1.0 / 60.0;
	return sys;
}

function quad(color: Rgba): MeshId {
	let data: MeshData = MeshData.withUvs();
	const built = addTexturedQuad(
		data, vec3(-0.5, -0.5, 0.0), vec3(0.5, -0.5, 0.0), vec3(0.5, 0.5, 0.0),
		vec3(-0.5, 0.5, 0.0), vec3(0.0, 0.0, 1.0), color,
	);
	if (!built.ok) { fail("quad refused"); }
	const added = addMeshData(context, data);
	if (!added.ok) { fail("quad upload refused"); unreachable; }
	return added.value;
}

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	gfxSetup();
	if (pixelArt) {
		const settings: PixelArtSettings = {
			...PixelArtSettings.full(), lowResShortSide: HEIGHT, postPass: false,
		};
		const look: PixelArtLook = {
			background: GREY,
			outline: {
				depthThreshold: 0.006, normalThreshold: 0.6, depthShade: 0.55, normalShade: 1.35,
			},
			fog: { start: 0, end: 1, strength: 0, color: GREY }, saturation: 0,
		};
		const made = PixelArtRenderer.create(context, settings, look);
		if (!made.ok) { fail("pixel-art renderer refused"); }
		if (made.ok) { pixel = made.value; }
	} else {
		const made = ForwardRenderer.create(context, GREY);
		if (!made.ok) { fail("forward renderer refused"); }
		if (made.ok) { forward = made.value; }
	}
	const white = addTexture(context, {
		pixels: [0xFFFFFFFF], width: 1, height: 1, filter: FilterMode.Nearest, wrap: Wrap.Clamp,
	});
	if (!white.ok) { fail("texture refused"); unreachable; }
	const kinds: Vec<MaterialKind> = [MaterialKind.Opaque, MaterialKind.Alpha];
	for (const kind of kinds) {
		const block = reserveUniforms(context, MATERIAL_UNIFORM_SLOT, UNLIT_MATERIAL_UNIFORM_LENGTH);
		if (!block.ok) { fail("material block refused"); unreachable; }
		const uniforms: Vec<float32> = [0, 0, 0, 0, 1, 1, 1, 1];
		if (!writeUniforms(context, block.value, uniforms).ok) { fail("uniform write refused"); }
		const base = Material.ofKind(Program.UnlitTextured, kind);
		const added = addMaterial(context, {
			...base, program: base.program.withInstanced(),
			pass: { ...base.pass, culling: Face.None },
			texture: white.value, uniforms: block.value,
		});
		if (!added.ok) { fail("instanced material refused"); unreachable; }
		materials.push(added.value);
	}
	if (!releaseTexture(context, white.value).ok) { fail("texture caller lease refused"); }
	meshes.push(quad(RED));
	meshes.push(quad(BLUE));
	const made = addStreamMesh(context, CAPACITY, VertexLayout.InstancedLitTextured);
	if (!made.ok) { fail("instance stream refused"); unreachable; }
	stream = made.value;
	playSystem(system, identity());
	if (!updateSystem(system, 1.0 / 60.0, identity()).ok || system.count != CAPACITY) {
		fail("initial particle update refused");
	}
	for (let slot = 0; slot < CAPACITY; slot++) {
		const mesh: int32 = meshIndexOf(system.asset.renderer, system.seeds[slot]);
		if (mesh == 0 && redSlot < 0) { redSlot = slot; }
		if (mesh == 1 && blueSlot < 0) { blueSlot = slot; }
	}
	if (redSlot < 0 || blueSlot < 0) { fail("the seed draws one mesh for every particle"); }
}

function place(slot: int32, at: Vec3): void {
	const cap: int32 = system.capacity;
	system.data[POS_X * cap + slot] = at.x;
	system.data[POS_Y * cap + slot] = at.y;
	system.data[POS_Z * cap + slot] = at.z;
}

function viewOf(): CameraView {
	const camera: Camera3D = {
		position: vec3(0, 0, 4), yaw: 0, pitch: 0, nearPlane: 0.1, farPlane: 10,
		projection: { kind: ProjectionKind.Orthographic, worldPerTexel: 0.02, snap: false },
	};
	const made = camera.resolve(WIDTH, HEIGHT);
	if (made.ok) { return made.value; }
	unreachable;
}

function probe(view: CameraView, at: Vec3): int64 {
	const screen = view.project(at, SCREEN, true);
	const rgba = voidCapturePixel(0, screen.x as int32, screen.y as int32);
	if (rgba < 0) { fail("readback probe missing"); }
	return rgba;
}

function red(rgba: int64): int64 { return (rgba >> 24) & 255; }
function blue(rgba: int64): int64 { return (rgba >> 8) & 255; }

// Stage 0, opaque, grouped by mesh: red at the left, blue at the right. Stage 1, blended, in
// draw order: the red particle behind the blue one at the centre, so blue is drawn last and wins.
function check(view: CameraView): string {
	if (stage == 0) {
		const left = probe(view, vec3(-1.0, 0.0, 0.0));
		const right = probe(view, vec3(1.0, 0.0, 0.0));
		if (red(left) < 200 || blue(left) > 60) { return "the red particle is not red"; }
		if (blue(right) < 200 || red(right) > 60) { return "the blue particle is not blue"; }
		return "";
	}
	const centre = probe(view, vec3(0.0, 0.0, 0.0));
	if (blue(centre) <= red(centre) + 20) { return "the nearer blue particle is not drawn last"; }
	return "";
}

function frame(): void {
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) { fail("framebuffer changed"); }
	for (let slot = 0; slot < CAPACITY; slot++) { place(slot, AWAY); }
	if (stage == 0) {
		place(redSlot, vec3(-1.0, 0.0, 0.0));
		place(blueSlot, vec3(1.0, 0.0, 0.0));
	} else {
		place(redSlot, vec3(0.0, 0.0, -1.0));
		place(blueSlot, vec3(0.0, 0.0, 1.0));
	}
	const order: MeshDrawOrder = stage == 0 ? MeshDrawOrder.ByMesh : MeshDrawOrder.AsDrawn;
	const written = writeMeshParticles(
		writer, system, vec3(0, 0, 4), vec3(0, 0, -1), vec3(0, 1, 0), bounds, order, instances,
		runs,
	);
	if (!written.ok) { fail("mesh instance write refused"); unreachable; }
	let total: int32 = 0;
	for (let r = 0; r < written.value; r++) { total = total + runs[r].count; }
	if (!writeStream(context, stream, instances, total).ok) { fail("stream upload refused"); }
	items = [];
	let first: int32 = 0;
	for (let r = 0; r < written.value; r++) {
		items.push({
			mesh: meshes[runs[r].mesh], material: materials[stage], world: identity(),
			instances: { stream: stream, first: control ? 0 : first, count: runs[r].count },
		});
		first = first + runs[r].count;
	}
	const view = viewOf();
	view.writeCameraBlock(cameraValues);
	const art = pixel;
	const fwd = forward;
	if (art !== null) {
		const drawn = renderPixelArt(art, items, cameraValues, lights, SCREEN);
		if (!drawn.ok) { fail(`pixel-art render refused: ${drawn.error.toString()}`); }
	}
	if (fwd !== null) {
		const drawn = renderForward(fwd, items, cameraValues, lights, WIDTH, HEIGHT);
		if (!drawn.ok) { fail(`forward render refused: ${drawn.error.toString()}`); }
	}
	if (voidCaptureGrab(0) == 0) { fail("capture refused"); }
	if (voidCaptureWritePng(0, `particleMesh${stage}.png`) == 0) { fail("PNG write refused"); }
	const verdict = check(view);
	if (verdict == "") {
		console.log(`PASS particle mesh: pixelArt=${pixelArt} stage=${stage}`);
	} else {
		failedChecks = failedChecks + 1;
		console.log(`FAIL particle mesh: pixelArt=${pixelArt} control=${control} ` +
			`stage=${stage}: ${verdict}`);
	}
	stage = stage + 1;
	if (stage == 2) {
		for (const id of materials) {
			if (!releaseMaterial(context, id).ok) { fail("material release refused"); }
		}
		for (const id of meshes) {
			if (!releaseMesh(context, id).ok) { fail("mesh release refused"); }
		}
		if (!releaseMesh(context, stream).ok) { fail("stream release refused"); }
		if (art !== null) { closePixelArt(art); }
		if (fwd !== null) { closeForward(fwd); }
		closeContext(context);
		voidCaptureExit(failedChecks == 0 ? 0 : 1);
	}
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
