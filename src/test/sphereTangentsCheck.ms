import { vec3 } from "../math/math3d";
import { MeshData, Rgba, addSphere, addTangents } from "../void3d/meshData";
import { approx } from "./helpers";

const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };

function checkTangents(sectors: int32): boolean {
	let data = MeshData.withUvs();
	if (!addSphere(data, 2.0, WHITE, sectors, 6).ok || !addTangents(data).ok) { return false; }
	if (!data.hasTangents || !data.validIndices()) { return false; }
	for (let i = 0; i < data.vertexCount(); i++) {
		const at = i * data.stride();
		const normal = vec3(data.vertices[at + 3], data.vertices[at + 4], data.vertices[at + 5]);
		const tangent = vec3(data.vertices[at + 8], data.vertices[at + 9], data.vertices[at + 10]);
		if (!approx(tangent.length(), 1.0) || Math.abs(normal.dot(tangent)) >= 0.001) {
			return false;
		}
	}
	const previous = data.vertices.length;
	return !addSphere(data, 1.0, WHITE, 8, 6).ok && data.vertices.length == previous;
}

test "an 8 by 6 UV sphere reaches real Mikk tangents" {
	assert checkTangents(8);
}

test "a 16 by 6 UV sphere reaches real Mikk tangents" {
	assert checkTangents(16);
}
