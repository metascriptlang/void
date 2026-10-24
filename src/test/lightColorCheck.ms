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
