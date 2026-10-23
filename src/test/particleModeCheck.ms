import { readFile } from "std/fs";
import { JsonValue } from "std/serialize/json/types";
import { Vec3, vec3, Mat4 } from "../math/math3d";
import {
	ParticleSystemAsset, RenderMode, RenderAlignment, SimulationSpace,
} from "../particles/asset";
import { constantCurve } from "../particles/curve";
import { ParticleSystem, playSystem, updateSystem } from "../particles/system";
import { vec3f, vec4f, mat4x4f, length } from "../shader/std";
import { AtlasTile } from "../void3d/billboard";
import {
	Camera3D, CameraBasis, CameraView, ProjectionKind, resolve, writeCameraBlock,
} from "../void3d/camera";
import {
	ParticleWriter3D, PARTICLE_VISUAL_INSTANCE_STRIDE, writeParticles,
} from "../void3d/particleWriter";
import { ParticleVisualAttributes, VertexBindings, particleVisualVs } from "../void3d/shader3d";

// Each p3d_ golden in tests/unity/goldens is one World-space particle seen by a placed camera,
// from a moved and turned emitter; Unity's BakeMesh gives its four world corners. The replay
// runs Void's simulation, writes the instance with the 3D writer and runs the ParticleVisual
// vertex function on the CPU, then compares its corners with Unity's. Unity is left-handed and
// Void right-handed, so every point and vector crosses with z negated: the picture and the
// clockwise rotation value are the same, the cross products of the rules change sign.

const GOLDEN_DIR: string = "tests/unity/goldens/";
const SEED: uint32 = 12345;
const TOL: float32 = 1e-3;
const TEXEL_WIDTH: int32 = 300;
const TEXEL_HEIGHT: int32 = 200;
// Unity splits a Simulate(dt) longer than 0.03 s into equal sub-steps; the replay does the same.
const MAX_PARTICLE_DT: float32 = 0.03;
const WHOLE: AtlasTile = { u: 0.0, v: 0.0, u2: 1.0, v2: 1.0 };
// BakeMesh's corners are top-left, top-right, bottom-right, bottom-left; these are the vertex
// indices of the same corners in PARTICLE_CORNERS.
const BAKED_VERTEX: int32[4] = [5, 2, 1, 0];

function golden(name: string): JsonValue {
	const text = readFile(`${GOLDEN_DIR}${name}.json`);
	if (!text.ok) { unreachable; }
	const parsed = JSON.parseValue(text.value);
	if (!parsed.ok) { unreachable; }
	return parsed.value;
}

function numberAt(v: JsonValue, k: int32): float32 {
	return v.at(k).asNumber() as float32;
}

function flipped(v: JsonValue): Vec3 {
	return vec3(numberAt(v, 0), numberAt(v, 1), -numberAt(v, 2));
}

// The settings write a vector as "[x, y, z]" or "(x, y, z)".
function triple(text: string): Vec3 {
	let digits: string = text.replace("[", "").replace("]", "").replace("(", "").replace(")", "");
	const parts = digits.split(",");
	return vec3(Number(parts[0].trim()) as float32, Number(parts[1].trim()) as float32,
		Number(parts[2].trim()) as float32);
}

function renderModeOf(name: string): RenderMode {
	if (name == "Billboard") { return RenderMode.Billboard; }
	if (name == "Stretch") { return RenderMode.Stretch; }
	if (name == "HorizontalBillboard") { return RenderMode.HorizontalBillboard; }
	if (name == "VerticalBillboard") { return RenderMode.VerticalBillboard; }
	console.log(`unity parity: render mode ${name} has no 3D case`);
	unreachable;
}

function alignmentOf(name: string): RenderAlignment {
	if (name == "View") { return RenderAlignment.View; }
	if (name == "World") { return RenderAlignment.World; }
	if (name == "Local") { return RenderAlignment.Local; }
	if (name == "Facing") { return RenderAlignment.Facing; }
	if (name == "Velocity") { return RenderAlignment.Velocity; }
	console.log(`unity parity: alignment ${name} has no 3D case`);
	unreachable;
}

// The asset the capture builds: no shape, one particle at t = 0, drifting with a world velocity.
function assetOf(settings: JsonValue): ParticleSystemAsset {
	let a = ParticleSystemAsset.defaults();
	a.main.duration = 5.0;
	a.main.loop = true;
	a.main.startLifetime = constantCurve(5.0);
	a.main.startSpeed = constantCurve(0.0);
	a.main.maxParticles = 1000;
	a.main.simulationSpace = SimulationSpace.World;
	a.shape.enabled = false;
	a.emission.rateOverTime = constantCurve(0.0);
	a.emission.bursts = [{ time: 0.0, count: constantCurve(1.0), cycleCount: 1, repeatInterval: 0.01, probability: 1.0 }];
	const size: Vec3 = triple(settings.getDynamicField("startSize3D").asString());
	a.main.startSize3D = true;
	a.main.startSizeX = constantCurve(size.x);
	a.main.startSizeY = constantCurve(size.y);
	a.main.startSizeZ = constantCurve(size.z);
	a.main.startRotationZ = constantCurve(
		(settings.getDynamicField("startRotationDeg").asNumber() * 0.017453292519943295) as float32);
	const velocity: Vec3 = triple(settings.getDynamicField("velocity").asString());
	a.velocityOverLifetime.enabled = true;
	a.velocityOverLifetime.space = SimulationSpace.World;
	a.velocityOverLifetime.x = constantCurve(velocity.x);
	a.velocityOverLifetime.y = constantCurve(velocity.y);
	a.velocityOverLifetime.z = constantCurve(-velocity.z);
	a.renderer.renderMode = renderModeOf(settings.getDynamicField("renderMode").asString());
	a.renderer.alignment = alignmentOf(settings.getDynamicField("alignment").asString());
	a.renderer.pivot = triple(settings.getDynamicField("pivot").asString());
	a.renderer.lengthScale = settings.getDynamicField("lengthScale").asNumber() as float32;
	a.renderer.velocityScale = settings.getDynamicField("velocityScale").asNumber() as float32;
	a.renderer.cameraVelocityScale = settings.getDynamicField("cameraVelocityScale").asNumber() as float32;
	a.renderer.freeformStretching = settings.getDynamicField("freeformStretching").asBoolean();
	a.renderer.rotateWithStretchDirection = settings.getDynamicField("rotateWithStretchDirection").asBoolean();
	a.renderer.allowRoll = settings.getDynamicField("allowRoll").asBoolean();
	a.renderer.minParticleSize = settings.getDynamicField("minParticleSize").asNumber() as float32;
	a.renderer.maxParticleSize = settings.getDynamicField("maxParticleSize").asNumber() as float32;
	return a;
}

// The emitter's transform in Void's frame: its axes are the rows, its local +z is the negated
// mirror of Unity's forward.
function emitterWorld(e: JsonValue): Mat4 {
	const right: Vec3 = flipped(e.getDynamicField("right"));
	const up: Vec3 = flipped(e.getDynamicField("up"));
	const forward: Vec3 = flipped(e.getDynamicField("forward"));
	const at: Vec3 = flipped(e.getDynamicField("pos"));
	return {
		m11: right.x, m12: right.y, m13: right.z, m14: 0.0,
		m21: up.x, m22: up.y, m23: up.z, m24: 0.0,
		m31: -forward.x, m32: -forward.y, m33: -forward.z, m34: 0.0,
		m41: at.x, m42: at.y, m43: at.z, m44: 1.0,
	};
}

function viewOf(cam: JsonValue): CameraView {
	const orientation: CameraBasis = {
		right: flipped(cam.getDynamicField("right")),
		up: flipped(cam.getDynamicField("up")),
		forward: flipped(cam.getDynamicField("forward")),
	};
	const aspect: float32 = cam.getDynamicField("aspect").asNumber() as float32;
	let camera: Camera3D = {
		position: flipped(cam.getDynamicField("pos")), yaw: 0.0, pitch: 0.0,
		orientation: orientation, nearPlane: 0.1, farPlane: 200.0,
		projection: { kind: ProjectionKind.Perspective, fovY: 1.0 },
	};
	if (cam.getDynamicField("orthographic").asBoolean()) {
		const height: float32 = 2.0 * (cam.getDynamicField("orthographicSize").asNumber() as float32);
		camera.projection = {
			kind: ProjectionKind.Orthographic, worldPerTexel: height / (TEXEL_HEIGHT as float32), snap: false,
		};
	} else {
		camera.projection = {
			kind: ProjectionKind.Perspective,
			fovY: (cam.getDynamicField("fov").asNumber() * 0.017453292519943295) as float32,
		};
	}
	if (Math.abs((aspect as float64) - (TEXEL_WIDTH as float64) / (TEXEL_HEIGHT as float64)) > 1e-6) {
		console.log("unity parity: the capture's aspect is not the replay's target aspect");
		unreachable;
	}
	const resolved = camera.resolve(TEXEL_WIDTH, TEXEL_HEIGHT);
	if (!resolved.ok) { unreachable; }
	return resolved.value;
}

function bindingsOf(view: CameraView): VertexBindings {
	let b: Vec<float32> = new Array(28);
	view.writeCameraBlock(b);
	return {
		vertexParams: {
			viewProj: mat4x4f(vec4f(b[0], b[1], b[2], b[3]), vec4f(b[4], b[5], b[6], b[7]),
				vec4f(b[8], b[9], b[10], b[11]), vec4f(b[12], b[13], b[14], b[15])),
			cameraRight: vec4f(b[16], b[17], b[18], b[19]),
			cameraUp: vec4f(b[20], b[21], b[22], b[23]),
			cameraPosition: vec4f(b[24], b[25], b[26], b[27]),
		},
	};
}

function attributesOf(out: Vec<float32>, vertex: int32): ParticleVisualAttributes {
	return {
		root: vec4f(out[0], out[1], out[2], out[3]), shape: vec4f(out[4], out[5], out[6], out[7]),
		tile: vec4f(out[8], out[9], out[10], out[11]), color: vec4f(out[12], out[13], out[14], out[15]),
		velocity: vec3f(out[16], out[17], out[18]),
		look: vec4f(out[19], out[20], out[21], out[22]), scale: vec4f(out[23], out[24], out[25], out[26]),
		pull: vec3f(out[27], out[28], out[29]),
		emitterRight: vec3f(out[30], out[31], out[32]), emitterUp: vec3f(out[33], out[34], out[35]),
		index: vertex as uint32,
	};
}

// Replays `name` with the camera moving at `cameraVelocity`; returns how many frames or corners
// disagree, printing the first, and leaves in `measured` the last frame's distance from the first
// vertex to the second (a stretched quad's length).
function replayMoving(name: string, cameraVelocity: Vec3, report: boolean, ref measured: float32): int32 {
	const g = golden(name);
	const dt: float64 = g.getDynamicField("dt").asNumber();
	const frames = g.getDynamicField("frames");
	const settings = g.getDynamicField("settings");
	const substeps: int32 = Math.ceil(((dt as float32) / MAX_PARTICLE_DT) as float64) as int32;
	const made = ParticleSystem.create(assetOf(settings), SEED);
	if (!made.ok) { unreachable; }
	let sys = made.value;
	sys.clock.fixedStep = dt / (substeps as float64);
	sys.clock.maxFrameTime = 1.0;
	let writer = ParticleWriter3D.create();
	let out: Vec<float32> = new Array(PARTICLE_VISUAL_INSTANCE_STRIDE);
	let bad: int32 = 0;
	for (let k = 0; k < (frames.length() as int32); k++) {
		const frame = frames.at(k);
		const pose = frame.getDynamicField("pose");
		const world: Mat4 = emitterWorld(pose.getDynamicField("emitter"));
		if (k == 0) {
			playSystem(sys, world);
			continue;
		}
		for (let s = 0; s < substeps; s++) {
			const done = updateSystem(sys, dt / (substeps as float64), world);
			if (!done.ok) { unreachable; }
		}
		const view = viewOf(pose.getDynamicField("camera"));
		const written = writeParticles(writer, sys, [WHOLE], view.eye, view.basis.forward, cameraVelocity, out);
		if (!written.ok || written.value != 1) {
			console.log(`unity parity: ${name} frame ${k}: the writer wrote ${written.ok ? written.value : -1} instances`);
			bad = bad + 1;
			continue;
		}
		const bindings = bindingsOf(view);
		const head = particleVisualVs(attributesOf(out, 0), bindings).worldPosition;
		const tail = particleVisualVs(attributesOf(out, 1), bindings).worldPosition;
		measured = length(head - tail);
		const baked = frame.getDynamicField("bakedQuads").at(0).getDynamicField("pos");
		for (let j = 0; j < 4; j++) {
			const want: Vec3 = flipped(baked.at(j));
			const got = particleVisualVs(attributesOf(out, BAKED_VERTEX[j]), bindings).worldPosition;
			const off: float32 = Math.max(Math.abs(got.x - want.x),
				Math.max(Math.abs(got.y - want.y), Math.abs(got.z - want.z))) as float32;
			if (!(off <= TOL)) {
				bad = bad + 1;
				if (bad == 1 && report) {
					console.log(`unity parity: ${name} frame ${k} corner ${j}: unity ${want.x}, ${want.y}, ${want.z}; void ${got.x}, ${got.y}, ${got.z}`);
				}
			}
		}
	}
	return bad;
}

// BakeMesh has no camera history, so the camera is not moving as far as it can tell.
function replay(name: string): int32 {
	let unused: float32 = 0.0;
	return replayMoving(name, vec3(0.0, 0.0, 0.0), true, unused);
}

function allAgree(names: Vec<string>): int32 {
	let bad: int32 = 0;
	for (const name of names) { bad = bad + replay(name); }
	return bad;
}

test "view billboards, with and without a pivot, under a perspective and an orthographic camera" {
	assert allAgree(["p3d_bb_view", "p3d_bb_view_pivot", "p3d_ortho_bb_view", "p3d_ortho_bb_view_pivot"]) == 0;
}

test "view billboards without roll stay upright on the world y axis" {
	assert allAgree(["p3d_bb_view_noroll", "p3d_bb_view_noroll_pivot", "p3d_ortho_bb_view_noroll", "p3d_ortho_bb_view_noroll_pivot"]) == 0;
}

test "world-aligned billboards lie on the world x and y axes, pivot.z along the world z" {
	assert allAgree(["p3d_bb_world", "p3d_bb_world_pivot", "p3d_ortho_bb_world", "p3d_ortho_bb_world_pivot", "p3d_bb_world_pivot_sizez3"]) == 0;
}

test "local-aligned billboards follow the emitter's right and up" {
	assert allAgree(["p3d_bb_local", "p3d_bb_local_pivot", "p3d_ortho_bb_local", "p3d_ortho_bb_local_pivot"]) == 0;
}

test "facing billboards turn to the camera's position, also under an orthographic camera" {
	assert allAgree(["p3d_bb_facing", "p3d_bb_facing_pivot", "p3d_ortho_bb_facing", "p3d_ortho_bb_facing_pivot"]) == 0;
}

test "velocity-aligned billboards take the particle's velocity as their normal" {
	assert allAgree(["p3d_bb_velocity", "p3d_bb_velocity_pivot", "p3d_ortho_bb_velocity", "p3d_ortho_bb_velocity_pivot"]) == 0;
}

test "pivot.z moves a billboard along its normal by that many widths, not heights or depths" {
	assert allAgree(["p3d_bb_view_pivot_sizez3", "p3d_bb_view_pz_size2x3"]) == 0;
}

test "stretched billboards run from the head along the velocity, as wide as the particle" {
	assert allAgree(["p3d_stretch", "p3d_stretch_pivot", "p3d_stretch_world", "p3d_ortho_stretch", "p3d_ortho_stretch_pivot", "p3d_ortho_stretch_world"]) == 0;
}

test "freeform stretching scales the facing quad along the velocity, with and without rotating into it" {
	assert allAgree(["p3d_stretch_freeform", "p3d_stretch_freeform_pivot", "p3d_stretch_freeform_rotwith",
		"p3d_ortho_stretch_freeform", "p3d_ortho_stretch_freeform_pivot", "p3d_ortho_stretch_freeform_rotwith"]) == 0;
}

test "a camera's velocity is invisible to BakeMesh, so the stretch ignores it as Unity's bake does" {
	assert allAgree(["p3d_stretch_cvs_static", "p3d_stretch_cvs_moving", "p3d_stretch_cvs0_moving"]) == 0;
}

test "horizontal billboards lie flat on x and z with the unit-diagonal corners" {
	assert allAgree(["p3d_horizontal", "p3d_horizontal_pivot", "p3d_ortho_horizontal", "p3d_ortho_horizontal_pivot",
		"p3d_diag_horizontal_base", "p3d_diag_horizontal_rot25", "p3d_diag_horizontal_emyaw30", "p3d_diag_horizontal_emroll40",
		"p3d_diag_horizontal_camroll12", "p3d_diag_horizontal_camyaw30", "p3d_diag_horizontal_campitch20",
		"p3d_diag_horizontal_size2x3", "p3d_diag_horizontal_px_size2x3", "p3d_diag_horizontal_py_size2x3",
		"p3d_diag_horizontal_pz_size2x3", "p3d_diag_horizontal_px_size2x3_rot25", "p3d_diag_horizontal_py_size2x3_rot25",
		"p3d_diag_horizontal_pz_size2x3_rot25"]) == 0;
}

test "vertical billboards stand on the world y axis, facing the camera's yaw" {
	assert allAgree(["p3d_vertical", "p3d_vertical_pivot", "p3d_ortho_vertical", "p3d_ortho_vertical_pivot",
		"p3d_diag_vertical_base", "p3d_diag_vertical_rot25", "p3d_diag_vertical_emyaw30", "p3d_diag_vertical_emroll40",
		"p3d_diag_vertical_camroll12", "p3d_diag_vertical_camyaw30", "p3d_diag_vertical_campitch20",
		"p3d_diag_vertical_size2x3", "p3d_diag_vertical_px_size2x3", "p3d_diag_vertical_py_size2x3",
		"p3d_diag_vertical_pz_size2x3", "p3d_diag_vertical_px_size2x3_rot25", "p3d_diag_vertical_py_size2x3_rot25",
		"p3d_diag_vertical_pz_size2x3_rot25"]) == 0;
}

test "maxParticleSize and minParticleSize are fractions of the viewport width at the particle's depth" {
	assert allAgree(["p3d_clamp_max_near", "p3d_clamp_max_mid", "p3d_clamp_max_far",
		"p3d_clamp_max_wide_near", "p3d_clamp_max_wide_mid", "p3d_clamp_max_wide_far",
		"p3d_clamp_min_near", "p3d_clamp_min_mid", "p3d_clamp_min_far", "p3d_clamp_inside"]) == 0;
}

test "a stretched billboard's size limit narrows its width and leaves its length" {
	assert allAgree(["p3d_stretch_clamp_max_near", "p3d_stretch_clamp_max_mid", "p3d_stretch_clamp_max_far"]) == 0;
}

test "every mode holds from a second placement of the camera and the emitter" {
	assert allAgree(["p3d_pose2_bb_view", "p3d_pose2_bb_world", "p3d_pose2_bb_local", "p3d_pose2_bb_facing",
		"p3d_pose2_bb_velocity", "p3d_pose2_bb_view_noroll", "p3d_pose2_stretch",
		"p3d_pose2_stretch_freeform_rotwith", "p3d_pose2_horizontal", "p3d_pose2_vertical"]) == 0;
}

// Unity's bake cannot see a camera's velocity, so cameraVelocityScale has no measurement. The
// rule here is the documented one, the stretch vector minus the camera's velocity times the
// scale, and this pins only that the vertex stage applies it.
test "cameraVelocityScale shortens a stretch by the camera's velocity along it (documented, not measured)" {
	let still: float32 = 0.0;
	let moving: float32 = 0.0;
	assert replayMoving("p3d_stretch_cvs_static", vec3(0.0, 0.0, 0.0), true, still) == 0;
	// The particle drifts at (1.5, 0.5, -1) in Void's frame, 2 units tall, lengthScale 1.5 and
	// velocityScale 0.4; a camera moving at half its velocity takes that off the stretch vector.
	const velocity: Vec3 = vec3(1.5, 0.5, -1.0);
	const along: Vec3 = velocity.scaled(1.0 / velocity.length());
	const stretch: Vec3 = along.scaled(2.0 * 1.5) + velocity.scaled(0.4);
	const camera: Vec3 = velocity.scaled(0.5);
	replayMoving("p3d_stretch_cvs_static", camera, false, moving);
	assert Math.abs(((still as float64) - (stretch.length() as float64))) < 1e-3;
	assert Math.abs(((moving as float64) - ((stretch - camera).length() as float64))) < 1e-3;
}
