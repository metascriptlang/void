// expect: void3d: orthoBounds asked of a perspective camera
import { Camera3D, ProjectionKind } from "../../src/void3d/camera";
import { vec3 } from "../../src/math/math3d";

let camera: Camera3D = {
	position: vec3(0.0, 0.0, 0.0),
	yaw: 0.0,
	pitch: 0.0,
	nearPlane: 0.1,
	farPlane: 100.0,
	projection: { kind: ProjectionKind.Perspective, fovY: 1.0 },
};
let bounds = camera.orthoBounds(320, 240);
console.log(bounds.minX);
