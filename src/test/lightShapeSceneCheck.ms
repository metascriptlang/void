import { Vec3, Quat, vec3, axisAngle, identityQuat } from "../math/math3d";
import {
	Scene3D,
	NodeId3D,
	Transform3D,
	LightKind,
	LightInstance,
	LightShape,
	LightError,
	addLightNode,
	collectLights,
	closeScene,
} from "../void3d/scene";
import { DrawContext, DrawItem } from "../void3d/draw";
import {
	LIGHT_UNIFORM_LENGTH,
	LIGHT_RECORD_COLOR,
	LIGHT_RECORD_LENGTH,
	LIGHT_RECORD_SHAPE,
	VERTEX_UNIFORM_LENGTH,
} from "../void3d/gpu3d";
import { LowResView, lowResView } from "../void3d/blit";
import {
	PixelArtRenderer,
	PixelArtSettings,
	PixelArtError,
	PixelArtLook,
	PIXEL_ART_UNIFORM_LENGTH,
	renderFrame,
} from "../void3d/pixelArtRenderer";

const NO_SHAPE: LightShape = {
	angle: 0.0, verticalAngle: 0.0, falloff: 0.0, width: 0.0, height: 0.0, length: 0.0,
	capsuleRadius: 0.0,
};

function near(a: float32, b: float32): boolean {
	return Math.abs(a - b) <= 1e-5;
}

function block(): Vec<float32> {
	let values: Vec<float32> = [];
	for (let i = 0; i < LIGHT_UNIFORM_LENGTH; i++) { values.push(0); }
	return move values;
}

function lightOf(kind: LightKind, shape: LightShape): LightInstance {
	return {
		kind: kind, color: vec3(1, 0.5, 0.25), radius: 9, power: 2, priority: 0, shape: shape,
	};
}

function place(
	scene: Scene3D, light: LightInstance, position: Vec3, rotation: Quat, scale: Vec3,
): NodeId3D {
	return addLightNode(scene, scene.rootId(),
		{ position: position, rotation: rotation, scale: scale }, light);
}

function placeAt(scene: Scene3D, light: LightInstance): NodeId3D {
	return place(scene, light, vec3(1, 2, 3), identityQuat(), vec3(1, 1, 1));
}

function slot(values: Vec<float32>, array: int32, i: int32, k: int32): float32 {
	const record: int32 = LIGHT_UNIFORM_LENGTH + i * LIGHT_RECORD_LENGTH;
	return values[record + LIGHT_RECORD_SHAPE + array * 4 + k];
}

function holdsRecords(values: Vec<float32>, count: int32): boolean {
	return (values.length as int32) == LIGHT_UNIFORM_LENGTH + count * LIGHT_RECORD_LENGTH;
}

function errorOf(result: Result<int32, LightError>): LightError | null {
	return result.ok ? null : result.error;
}

const SPOT: LightShape = { ...NO_SHAPE, angle: 1.5707963268, falloff: 0.3490658504 };

test "the shape texels close a record and a point record leaves them zero" {
	assert LIGHT_RECORD_LENGTH == LIGHT_RECORD_SHAPE + 4 * 4;
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	defer closeScene(scene);
	placeAt(scene, lightOf(LightKind.Point, NO_SHAPE));
	let values = block();
	assert errorOf(collectLights(scene, values)) === null;
	assert holdsRecords(values, 1);
	for (let k = 0; k < 16; k++) { assert slot(values, 0, 0, k) == 0.0; }
}

test "a spot node packs its forward, its kind and the cosines of its cone" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	defer closeScene(scene);
	placeAt(scene, lightOf(LightKind.Spot, SPOT));
	let values = block();
	assert errorOf(collectLights(scene, values)) === null;
	const at: int32 = LIGHT_UNIFORM_LENGTH;
	assert holdsRecords(values, 1);
	assert values[at] == 1.0 && values[at + 1] == 2.0 && values[at + 2] == 3.0;
	assert values[at + 3] == 2.0 && values[at + LIGHT_RECORD_COLOR + 3] == 9.0;
	assert slot(values, 0, 0, 0) == 0.0 && slot(values, 0, 0, 1) == 0.0;
	assert near(slot(values, 0, 0, 2), 1.0) && slot(values, 0, 0, 3) == 1.0;
	assert near(slot(values, 1, 0, 0), 0.7071068) && near(slot(values, 1, 0, 1), 0.9396926);
}

test "a rotated spot's forward is the node's +Z and a spot with no falloff keeps cos 0 inner" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	defer closeScene(scene);
	place(scene, lightOf(LightKind.Spot, { ...NO_SHAPE, angle: 1.0471975512 }), vec3(0, 0, 0),
		axisAngle(vec3(0, 0, 1), 1.0), vec3(3, 3, 3));
	let values = block();
	assert errorOf(collectLights(scene, values)) === null;
	assert near(slot(values, 0, 0, 2), 1.0) && near(slot(values, 1, 0, 1), 1.0);
	assert near(slot(values, 1, 0, 0), 0.8660254);
}

test "a rectangle node packs right, up and half sizes scaled by its own axes, and the two cones" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	defer closeScene(scene);
	const shape: LightShape = {
		...NO_SHAPE, angle: 1.5707963268, verticalAngle: 1.0471975512, falloff: 0.0,
		width: 2.0, height: 1.0,
	};
	place(scene, lightOf(LightKind.Rectangle, shape), vec3(0, 3, 0), identityQuat(), vec3(2, 3, 1));
	let values = block();
	assert errorOf(collectLights(scene, values)) === null;
	assert slot(values, 0, 0, 3) == 2.0 && near(slot(values, 0, 0, 2), 1.0);
	assert slot(values, 1, 0, 0) == 1.0 && slot(values, 1, 0, 1) == 0.0;
	assert near(slot(values, 1, 0, 3), 2.0);
	assert slot(values, 2, 0, 1) == 1.0 && near(slot(values, 2, 0, 3), 1.5);
	assert near(slot(values, 3, 0, 0), 0.7071068) && slot(values, 3, 0, 1) == 1.0;
	assert near(slot(values, 3, 0, 2), 0.8660254) && slot(values, 3, 0, 3) == 1.0;
}

test "a capsule node packs its axis, half length and radius capped at its range" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	defer closeScene(scene);
	const shape: LightShape = { ...NO_SHAPE, length: 4.0, capsuleRadius: 20.0 };
	place(scene, lightOf(LightKind.Capsule, shape), vec3(0, 2, 0), identityQuat(), vec3(2, 2, 2));
	let values = block();
	assert errorOf(collectLights(scene, values)) === null;
	assert slot(values, 0, 0, 3) == 3.0 && near(slot(values, 0, 0, 2), 1.0);
	assert slot(values, 1, 0, 0) == 2.0 && slot(values, 1, 0, 1) == 9.0;
}

test "spot, rectangle, capsule and point lights share one record layout in scene order" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	defer closeScene(scene);
	const rectangle: LightShape = {
		...NO_SHAPE, angle: 1.0, verticalAngle: 1.0, width: 1.0, height: 1.0,
	};
	placeAt(scene, lightOf(LightKind.Point, NO_SHAPE));
	placeAt(scene, { ...lightOf(LightKind.Capsule, { ...NO_SHAPE, length: 1.0 }), priority: 3 });
	placeAt(scene, lightOf(LightKind.Rectangle, rectangle));
	placeAt(scene, { ...lightOf(LightKind.Spot, SPOT), priority: 5 });
	let values = block();
	assert errorOf(collectLights(scene, values)) === null;
	assert holdsRecords(values, 4);
	assert slot(values, 0, 0, 3) == 0.0 && slot(values, 0, 1, 3) == 3.0;
	assert slot(values, 0, 2, 3) == 2.0 && slot(values, 0, 3, 3) == 1.0;
}

test "a fifth positioned light of any shape is collected like the first four" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	defer closeScene(scene);
	for (let i = 0; i < 4; i++) { placeAt(scene, lightOf(LightKind.Spot, SPOT)); }
	placeAt(scene, lightOf(LightKind.Point, NO_SHAPE));
	let values = block();
	assert errorOf(collectLights(scene, values)) === null;
	assert holdsRecords(values, 5);
	assert slot(values, 0, 3, 3) == 1.0 && slot(values, 0, 4, 3) == 0.0;
}

function refused(light: LightInstance, scale: Vec3, rotation: Quat): boolean {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	defer closeScene(scene);
	place(scene, light, vec3(0, 0, 0), rotation, scale);
	let values = block();
	return errorOf(collectLights(scene, values)) == LightError.BadLightShape;
}

const UNIT: Vec3 = vec3(1, 1, 1);

test "a spot whose angle, falloff or range cannot make a cone is refused by name" {
	assert !refused(lightOf(LightKind.Spot, SPOT), UNIT, identityQuat());
	assert refused(lightOf(LightKind.Spot, NO_SHAPE), UNIT, identityQuat());
	assert refused(lightOf(LightKind.Spot, { ...SPOT, angle: 3.141592653589793 }), UNIT,
		identityQuat());
	assert refused(lightOf(LightKind.Spot, { ...SPOT, angle: 4.0 }), UNIT, identityQuat());
	assert refused(lightOf(LightKind.Spot, { ...SPOT, angle: -1.0 }), UNIT, identityQuat());
	assert refused(lightOf(LightKind.Spot, { ...SPOT, falloff: -0.1 }), UNIT, identityQuat());
	assert refused(lightOf(LightKind.Spot, { ...SPOT, falloff: 0.9 }), UNIT, identityQuat());
	assert refused({ ...lightOf(LightKind.Spot, SPOT), radius: 0.0 }, UNIT, identityQuat());
	assert refused({ ...lightOf(LightKind.Spot, SPOT), radius: -2.0 }, UNIT, identityQuat());
	const notANumber: float32 = (0.0 / 0.0) as float32;
	assert refused({ ...lightOf(LightKind.Spot, SPOT), radius: notANumber }, UNIT, identityQuat());
	assert refused(lightOf(LightKind.Spot, { ...SPOT, angle: notANumber }), UNIT, identityQuat());
}

test "a rectangle with a bad size, angle or sheared axes is refused by name" {
	const good: LightShape = {
		...NO_SHAPE, angle: 1.0, verticalAngle: 1.0, width: 2.0, height: 1.0,
	};
	assert !refused(lightOf(LightKind.Rectangle, good), UNIT, identityQuat());
	assert refused(lightOf(LightKind.Rectangle, { ...good, width: -1.0 }), UNIT, identityQuat());
	assert refused(lightOf(LightKind.Rectangle, { ...good, height: -1.0 }), UNIT, identityQuat());
	assert refused(lightOf(LightKind.Rectangle, { ...good, angle: 0.0 }), UNIT, identityQuat());
	assert refused(lightOf(LightKind.Rectangle, { ...good, verticalAngle: 7.0 }), UNIT,
		identityQuat());
	assert refused(lightOf(LightKind.Rectangle, { ...good, falloff: -1.0 }), UNIT, identityQuat());
	assert refused({ ...lightOf(LightKind.Rectangle, good), radius: 0.0 }, UNIT, identityQuat());
	assert refused(lightOf(LightKind.Rectangle, good), vec3(0, 1, 1), identityQuat());
}

test "a capsule with no length or a negative radius is refused by name" {
	const good: LightShape = { ...NO_SHAPE, length: 2.0, capsuleRadius: 0.5 };
	assert !refused(lightOf(LightKind.Capsule, good), UNIT, identityQuat());
	assert refused(lightOf(LightKind.Capsule, { ...good, length: 0.0 }), UNIT, identityQuat());
	assert refused(lightOf(LightKind.Capsule, { ...good, capsuleRadius: -0.5 }), UNIT,
		identityQuat());
	assert refused({ ...lightOf(LightKind.Capsule, good), radius: -1.0 }, UNIT, identityQuat());
}

function look(): PixelArtLook {
	return {
		background: { x: 0.0, y: 0.0, z: 0.0, w: 0.0 },
		outline: {
			depthThreshold: 0.006, normalThreshold: 0.6, depthShade: 0.55, normalShade: 1.35,
		},
		fog: { start: 0.5, end: 0.8, strength: 0.85, color: { x: 0.02, y: 0.02, z: 0.07, w: 0.0 } },
		saturation: 0.0,
	};
}

test "the pixel-art preset refuses a shaped slot instead of toon-lighting it as a point" {
	const context: DrawContext = DrawContext.withUniformCapacity(PIXEL_ART_UNIFORM_LENGTH);
	const created: Result<PixelArtRenderer, PixelArtError> =
		PixelArtRenderer.create(context, PixelArtSettings.full(), look());
	assert created.ok;
	if (!created.ok) { return; }
	const renderer: PixelArtRenderer = created.value;
	let items: Vec<DrawItem> = [];
	const empty: LowResView = { width: 0, height: 0, scale: 0, offsetX: 0.0, offsetY: 0.0 };
	const drawn: LowResView = try lowResView(1080, 2400, 360, 1, 0) catch empty;
	const camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	for (let kind = 1; kind <= 3; kind++) {
		let lights: Vec<float32> = block();
		for (let i = 0; i < LIGHT_RECORD_LENGTH; i++) { lights.push(0); }
		lights[LIGHT_UNIFORM_LENGTH + LIGHT_RECORD_SHAPE + 3] = kind as float32;
		const refusal: Result<int32, PixelArtError> =
			renderFrame(renderer, items, camera, lights, drawn);
		assert !refusal.ok && refusal.error == PixelArtError.ShapedLight;
	}
	assert renderer.core.generation == 0 && renderer.view.width == 0;
}
