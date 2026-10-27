import { Vec3, vec3, axisAngle } from "../math/math3d";
import { Camera3D, CameraView, ProjectionKind } from "../void3d/camera";
import {
	ClusterAssignment, ClusterConfig, ClusterLight, ClusterLightKind,
} from "../void3d/clusters";
import {
	ClusterFrame, ClusterFrameError, assignFrame, clusterLightsOf, recordCountOf,
} from "../void3d/clusterFrame";
import { clusterIndexOf } from "../void3d/clusterLookup";
import { RecordTexture, recordTexture } from "../void3d/clusterTextures";
import { DrawContext, DrawItem } from "../void3d/draw";
import {
	LIGHT_CLUSTER_FACTORS,
	LIGHT_CLUSTER_GRID,
	LIGHT_CLUSTER_SCREEN,
	LIGHT_CLUSTER_VIEW,
	LIGHT_RECORD_LENGTH,
	LIGHT_UNIFORM_LENGTH,
	VERTEX_UNIFORM_LENGTH,
} from "../void3d/gpu3d";
import { Renderer, RendererError, beginFrame, setCameraView } from "../void3d/renderer";
import {
	LightError, LightInstance, LightKind, Scene3D, Transform3D, addLightNode, collectLights,
} from "../void3d/scene";
import { vec2f, vec4f } from "../shader/std";
import { approx } from "./helpers";

const WIDTH: int32 = 320;
const HEIGHT: int32 = 240;

function viewOf(orthographic: boolean, x: float32): CameraView {
	const made: Camera3D = {
		position: vec3(x, 1.0, 4.0),
		yaw: 0.0,
		pitch: 0.0,
		projection: orthographic
			? { kind: ProjectionKind.Orthographic, worldPerTexel: 0.02, snap: false }
			: { kind: ProjectionKind.Perspective, fovY: 1.0 },
		nearPlane: 0.1,
		farPlane: 50.0,
	};
	const view = made.resolve(WIDTH, HEIGHT);
	if (!view.ok) { unreachable; }
	return view.value;
}

const POINT: LightInstance = {
	kind: LightKind.Point, color: vec3(1.0, 1.0, 1.0), radius: 3.0, power: 1.0, priority: 0,
};

function lightsOf(): Vec<float32> {
	let scene: Scene3D = Scene3D.create(DrawContext.withUniformCapacity(0));
	const _point = addLightNode(scene, scene.rootId(),
		Transform3D.fromTranslation(vec3(0.0, 0.0, -2.0)), POINT);
	const spot: LightInstance = {
		...POINT, kind: LightKind.Spot, radius: 5.0,
		shape: { ...POINT.shape, angle: 1.2, falloff: 0.2 },
	};
	const turned: Transform3D = {
		...Transform3D.fromTranslation(vec3(1.0, 0.0, -3.0)),
		rotation: axisAngle(vec3(0.0, 1.0, 0.0), -1.5707963268),
	};
	const _spot = addLightNode(scene, scene.rootId(), turned, spot);
	let lights: Vec<float32> = [];
	const collected: Result<int32, LightError> = collectLights(scene, lights);
	if (!collected.ok || collected.value != 2) { unreachable; }
	return move lights;
}

function near(a: Vec3, b: Vec3): boolean {
	return approx(a.x, b.x) && approx(a.y, b.y) && approx(a.z, b.z);
}

function headerOnly(): Vec<float32> {
	return new Array(LIGHT_UNIFORM_LENGTH);
}

test "the record count is what follows the header, and a torn record is refused" {
	const header: Vec<float32> = headerOnly();
	const none = recordCountOf(header);
	assert none.ok && none.value == 0;
	const two = recordCountOf(lightsOf());
	assert two.ok && two.value == 2;
	let torn: Vec<float32> = lightsOf();
	const _dropped = torn.pop();
	const refused = recordCountOf(torn);
	assert !refused.ok && refused.error == ClusterFrameError.RecordLength;
	const short: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH - 1);
	assert !recordCountOf(short).ok;
}

test "a spot record clusters by its cone and a point record by its range" {
	const lights: Vec<float32> = lightsOf();
	const made: Vec<ClusterLight> = clusterLightsOf(lights, 2);
	assert made[0].kind == ClusterLightKind.Point && approx(made[0].range, 3.0);
	assert near(made[0].position, vec3(0.0, 0.0, -2.0));
	assert made[1].kind == ClusterLightKind.Spot && approx(made[1].range, 5.0);
	assert near(made[1].position, vec3(1.0, 0.0, -3.0));
	assert near(made[1].direction, vec3(-1.0, 0.0, 0.0));
	assert approx(made[1].outerHalfAngle, 0.6);
}

test "the record texture starts at the first record, past the header" {
	const lights: Vec<float32> = lightsOf();
	const texture: RecordTexture = recordTexture(lights, LIGHT_UNIFORM_LENGTH);
	for (let i = 0; i < 2 * LIGHT_RECORD_LENGTH; i++) {
		assert texture.floats[i] == lights[LIGHT_UNIFORM_LENGTH + i];
	}
	assert texture.floats[2 * LIGHT_RECORD_LENGTH] == 0.0;
}

test "a frame with no record needs no view and lists one empty cluster" {
	let frame: ClusterFrame = ClusterFrame.create(ClusterConfig.defaults());
	let block: Vec<float32> = headerOnly();
	const assigned = assignFrame(frame, block, null, true, block);
	assert assigned.ok;
	if (!assigned.ok) { return; }
	assert assigned.value.counts.length == 1 && assigned.value.lightIndices.length == 0;
	assert block[LIGHT_CLUSTER_GRID] == 1.0 && block[LIGHT_CLUSTER_GRID + 3] == 1.0;
	assert block[LIGHT_CLUSTER_SCREEN] == 1.0 && block[LIGHT_CLUSTER_SCREEN + 2] == 0.0;
	const g: int32 = LIGHT_CLUSTER_GRID;
	const f: int32 = LIGHT_CLUSTER_FACTORS;
	assert clusterIndexOf(vec2f(5.0, 7.0), 0.0,
		vec4f(block[g], block[g + 1], block[g + 2], block[g + 3]),
		vec4f(block[f], block[f + 1], block[f + 2], block[f + 3])) == 0;
}

test "a frame with records and no view is refused" {
	let frame: ClusterFrame = ClusterFrame.create(ClusterConfig.defaults());
	let block: Vec<float32> = headerOnly();
	const refused = assignFrame(frame, lightsOf(), null, false, block);
	assert !refused.ok && refused.error == ClusterFrameError.NoView;
}

test "the block carries the view's depth plane, its screen and its projection kind" {
	for (const orthographic of [false, true]) {
		let frame: ClusterFrame = ClusterFrame.create(ClusterConfig.defaults());
		const view: CameraView = viewOf(orthographic, 0.5);
		let block: Vec<float32> = headerOnly();
		const assigned: Result<ClusterAssignment, ClusterFrameError> =
			assignFrame(frame, lightsOf(), view, false, block);
		assert assigned.ok;
		assert block[LIGHT_CLUSTER_GRID + 3] == (orthographic ? 1.0 : 0.0);
		const forward: Vec3 = view.basis.forward;
		assert near(vec3(block[LIGHT_CLUSTER_VIEW], block[LIGHT_CLUSTER_VIEW + 1],
			block[LIGHT_CLUSTER_VIEW + 2]), forward);
		assert approx(block[LIGHT_CLUSTER_VIEW + 3], -forward.dot(view.eye));
		assert block[LIGHT_CLUSTER_SCREEN] == 0.0;
		assert block[LIGHT_CLUSTER_SCREEN + 1] == HEIGHT as float32;
		assert block[LIGHT_CLUSTER_SCREEN + 2] == 2.0;
	}
}

function beganWith(view: CameraView | null, drawn: CameraView): RendererError | null {
	const created: Result<Renderer, RendererError> =
		Renderer.create(DrawContext.withUniformCapacity(1024));
	if (!created.ok) { unreachable; }
	let core: Renderer = created.value;
	if (view !== null) { setCameraView(core, view); }
	const items: Vec<DrawItem> = [];
	let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	drawn.writeCameraBlock(camera);
	const began: Result<boolean, RendererError> = beginFrame(core, items, camera, lightsOf());
	return began.ok ? null : began.error;
}

test "a lit frame is refused with no camera view, or one that is not the camera drawn" {
	const drawn: CameraView = viewOf(false, 0.0);
	assert beganWith(null, drawn) == RendererError.ClusterViewUnset;
	assert beganWith(viewOf(false, 0.5), drawn) == RendererError.ClusterViewStale;
}
