import {
	Scene3D, NodeId3D, Transform3D, LightKind, LightInstance,
	addLightNode, setLightColor, setVisible, collectLights, closeScene,
} from "../void3d/scene";
import { DrawContext } from "../void3d/draw";
import { LIGHT_UNIFORM_LENGTH, MAX_POINT_LIGHTS } from "../void3d/gpu3d";
import { Vec3, vec3 } from "../math/math3d";

function light(scene: Scene3D, kind: LightKind, color: Vec3): NodeId3D {
	const value: LightInstance = {
		kind: kind, color: color, radius: 9, power: 2, priority: 7,
	};
	return addLightNode(scene, scene.rootId(),
		Transform3D.fromTranslation(vec3(1, 2, 3)), value);
}

function block(): Vec<float32> {
	let values: Vec<float32> = [];
	for (let i = 0; i < LIGHT_UNIFORM_LENGTH; i++) { values.push(0); }
	return move values;
}

test "point color edits reach the next light collection without changing attenuation or place" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	defer closeScene(scene);
	const id = light(scene, LightKind.Point, vec3(1, 0.5, 0.25));
	let values = block();
	assert collectLights(scene, values).ok;
	const colorAt: int32 = 12 + MAX_POINT_LIGHTS * 4;
	assert values[colorAt] == 1;
	setLightColor(scene, id, vec3(0.25, 1.5, 0.75));
	assert collectLights(scene, values).ok;
	assert values[colorAt] == 0.25 && values[colorAt + 1] == 1.5;
	assert values[colorAt + 2] == 0.75 && values[colorAt + 3] == 9;
	assert values[12] == 1 && values[13] == 2 && values[14] == 3 && values[15] == 2;
	assert scene.lights[0].kind == LightKind.Point && scene.lights[0].priority == 7;
}

test "directional color edits retain direction power and other point light color" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	defer closeScene(scene);
	const id = light(scene, LightKind.Directional, vec3(1, 1, 1));
	const _peer = light(scene, LightKind.Point, vec3(0.5, 0.25, 1));
	let values = block();
	assert collectLights(scene, values).ok;
	setLightColor(scene, id, vec3(-0.25, 2, 0.5));
	assert collectLights(scene, values).ok;
	assert values[8] == -0.25 && values[9] == 2 && values[10] == 0.5;
	assert values[4] == 0 && values[5] == 0 && values[6] == -1 && values[7] == 2;
	const colorAt: int32 = 12 + MAX_POINT_LIGHTS * 4;
	assert values[colorAt] == 0.5 && values[colorAt + 1] == 0.25;
	assert values[colorAt + 2] == 1;
}

test "light color remains a value and repeated edits replace only selected color" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	defer closeScene(scene);
	const id = light(scene, LightKind.Point, vec3(1, 1, 1));
	let color = vec3(0.25, 0.5, 0.75);
	setLightColor(scene, id, color);
	color.x = 9;
	assert scene.lights[0].color == vec3(0.25, 0.5, 0.75);
	setLightColor(scene, id, vec3(0, 0, 0));
	assert scene.lights[0].color == vec3(0, 0, 0);
	assert scene.lights[0].radius == 9 && scene.lights[0].power == 2;
}

test "hidden light retains its new color until visible collection resumes" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	defer closeScene(scene);
	const id = light(scene, LightKind.Point, vec3(1, 1, 1));
	setVisible(scene, id, false);
	setLightColor(scene, id, vec3(0.5, 0.25, 0.75));
	let values = block();
	const hidden = collectLights(scene, values);
	assert hidden.ok;
	if (hidden.ok) { assert hidden.value == 0; }
	setVisible(scene, id, true);
	const visible = collectLights(scene, values);
	assert visible.ok;
	if (visible.ok) { assert visible.value == 1; }
	const colorAt: int32 = 12 + MAX_POINT_LIGHTS * 4;
	assert values[colorAt] == 0.5 && values[colorAt + 1] == 0.25;
	assert values[colorAt + 2] == 0.75;
}
