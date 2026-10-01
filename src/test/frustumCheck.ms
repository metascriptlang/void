import { Mat4, identity, translation, scaling, vec3 } from "../math/math3d";
import { Bounds3D } from "../void3d/bounds";
import { Frustum3D } from "../void3d/frustum";
import { MeshData } from "../void3d/meshData";
import { DrawItem } from "../void3d/draw";
import { Material, Phase } from "../void3d/material";
import { Program } from "../void3d/gpu3d";
import { RenderState } from "../gpu/state";
import { PassList, collect, filterFrustum, sortBackToFront } from "../void3d/passList";

function cube(): Bounds3D {
	return Bounds3D.fromValues(-0.25, -0.25, -0.25, 0.5, 0.5, 0.5);
}

function point(): Bounds3D {
	return Bounds3D.fromPoints(vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0));
}

function perspective(): Mat4 {
	return {
		m11: 1.0, m12: 0.0, m13: 0.0, m14: 0.0,
		m21: 0.0, m22: 1.0, m23: 0.0, m24: 0.0,
		m31: 0.0, m32: 0.0, m33: -1.125, m34: -1.0,
		m41: 0.0, m42: 0.0, m43: -1.125, m44: 0.0,
	};
}

function item(mesh: int32, material: int32, x: float32, z: float32): DrawItem {
	return {
		mesh: { store: 0, index: mesh, generation: 1 },
		material: { store: 0, index: material, generation: 1 },
		world: translation(x, 0.0, z),
	};
}

function bounded(): MeshData {
	return { vertices: [], indices: [], bounds: cube() };
}

function materials(): Vec<Material> {
	return [
		Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque),
		Material.plain(Program.Lit, RenderState.defaults(), Phase.Alpha),
		Material.plain(Program.Lit, RenderState.defaults(), Phase.Additive),
	];
}

test "frustum keeps touching bounds but rejects outside each of its six planes" {
	let frustum: Frustum3D = Frustum3D.fromMatrix(identity());
	let touching: Vec<Mat4> = [
		translation(-1.25, 0.0, 0.5), translation(1.25, 0.0, 0.5),
		translation(0.0, -1.25, 0.5), translation(0.0, 1.25, 0.5),
		translation(0.0, 0.0, -0.25), translation(0.0, 0.0, 1.25),
	];
	let outside: Vec<Mat4> = [
		translation(-1.26, 0.0, 0.5), translation(1.26, 0.0, 0.5),
		translation(0.0, -1.26, 0.5), translation(0.0, 1.26, 0.5),
		translation(0.0, 0.0, -0.26), translation(0.0, 0.0, 1.26),
	];
	for (let i = 0; i < 6; i++) {
		assert frustum.intersectsBounds(cube(), touching[i]);
		assert !frustum.intersectsBounds(cube(), outside[i]);
	}
}

test "transformed local bounds keep reflected nonuniform scale and shear extents" {
	let frustum: Frustum3D = Frustum3D.fromMatrix(identity());
	assert frustum.intersectsBounds(cube(), scaling(-2.0, 0.5, 1.0) * translation(1.4, 0.0, 0.5));
	assert !frustum.intersectsBounds(cube(), scaling(-2.0, 0.5, 1.0) * translation(1.6, 0.0, 0.5));
	let shear: Mat4 = { ...identity(), m21: 2.0 };
	assert frustum.intersectsBounds(cube(), shear * translation(1.7, 0.0, 0.5));
	assert !frustum.intersectsBounds(cube(), shear * translation(1.8, 0.0, 0.5));
	assert frustum.intersectsBounds(cube(), scaling(0.0, 0.0, 0.0) * translation(1.0, 0.0, 0.5));
	assert !frustum.intersectsBounds(cube(), scaling(0.0, 0.0, 0.0) * translation(1.1, 0.0, 0.5));
}

test "rotated off-center bounds transform their center and local axes" {
	let frustum: Frustum3D = Frustum3D.fromMatrix(identity());
	let rotate: Mat4 = { ...identity(), m11: 0.0, m12: 1.0, m21: -1.0, m22: 0.0 };
	let bounds: Bounds3D = Bounds3D.fromValues(1.0, -0.1, -0.1, 1.6, 0.2, 0.2);
	assert frustum.intersectsBounds(bounds, rotate * translation(0.0, -0.1, 0.5));
	assert !frustum.intersectsBounds(bounds, rotate * translation(0.0, 0.1, 0.5));
}

test "perspective frustum side slopes widen with distance and retain near far touching" {
	let frustum: Frustum3D = Frustum3D.fromMatrix(perspective());
	let sides: Vec<Mat4> = [
		translation(-2.0, 0.0, -2.0), translation(2.0, 0.0, -2.0),
		translation(0.0, -2.0, -2.0), translation(0.0, 2.0, -2.0),
	];
	let outside: Vec<Mat4> = [
		translation(-2.01, 0.0, -2.0), translation(2.01, 0.0, -2.0),
		translation(0.0, -2.01, -2.0), translation(0.0, 2.01, -2.0),
	];
	for (let i = 0; i < 4; i++) {
		assert frustum.intersectsBounds(point(), sides[i]);
		assert !frustum.intersectsBounds(point(), outside[i]);
	}
	assert frustum.intersectsBounds(point(), translation(3.0, 0.0, -4.0));
	assert !frustum.intersectsBounds(point(), translation(3.0, 0.0, -2.0));
	assert frustum.intersectsBounds(point(), translation(0.0, 0.0, -1.0));
	assert frustum.intersectsBounds(point(), translation(0.0, 0.0, -9.0));
	assert !frustum.intersectsBounds(point(), translation(0.0, 0.0, -0.99));
	assert !frustum.intersectsBounds(point(), translation(0.0, 0.0, -9.01));
	assert !frustum.intersectsBounds(point(), translation(0.0, 0.0, 1.0));
}

test "per-view filtering re-includes source items after camera movement and reads live bounds" {
	let items: Vec<DrawItem> = [
		item(0, 0, 0.0, 0.5), item(0, 0, 4.0, 0.5), item(1, 0, 99.0, 0.5),
	];
	let meshes: Vec<MeshData> = [bounded(), MeshData.empty()];
	let phases: Vec<Material> = materials();
	let first: PassList = PassList.forPhase(Phase.Opaque);
	let second: PassList = PassList.forPhase(Phase.Opaque);
	let origin: Frustum3D = Frustum3D.fromMatrix(identity());
	let moved: Frustum3D = Frustum3D.fromMatrix(translation(-4.0, 0.0, 0.0));
	collect(first, items, phases);
	assert filterFrustum(first, items, meshes, origin) == 1;
	assert first.count == 2 && first.indices[0] == 0 && first.indices[1] == 2;
	collect(second, items, phases);
	assert filterFrustum(second, items, meshes, moved) == 1;
	assert second.count == 2 && second.indices[0] == 1 && second.indices[1] == 2;
	assert first.count == 2 && first.indices[0] == 0;
	collect(first, items, phases);
	assert filterFrustum(first, items, meshes, moved) == 1;
	assert first.indices[0] == 1 && first.indices[1] == 2;
	assert items[0].world.m41 == 0.0 && items[1].world.m41 == 4.0 && items[2].world.m41 == 99.0;
	meshes[0].bounds = Bounds3D.fromValues(-5.0, -0.25, -0.25, 10.0, 0.5, 0.5);
	collect(first, items, phases);
	assert filterFrustum(first, items, meshes, origin) == 0;
	assert first.count == 3;
}

test "phase filtering counts exclusions across phases and preserves alpha depth order" {
	let items: Vec<DrawItem> = [
		item(0, 0, 4.0, 0.5), item(0, 1, 0.0, 0.2), item(0, 2, 4.0, 0.5),
		item(0, 1, 4.0, 0.9), item(0, 1, 0.0, 0.8), item(1, 2, 99.0, 0.5),
		item(0, 1, 0.0, 0.8),
	];
	let meshes: Vec<MeshData> = [bounded(), MeshData.empty()];
	let phases: Vec<Material> = materials();
	let opaque: PassList = PassList.forPhase(Phase.Opaque);
	let alpha: PassList = PassList.forPhase(Phase.Alpha);
	let additive: PassList = PassList.forPhase(Phase.Additive);
	collect(opaque, items, phases);
	collect(alpha, items, phases);
	collect(additive, items, phases);
	let frustum: Frustum3D = Frustum3D.fromMatrix(identity());
	let excluded: int32 = filterFrustum(opaque, items, meshes, frustum) +
		filterFrustum(alpha, items, meshes, frustum) +
		filterFrustum(additive, items, meshes, frustum);
	assert excluded == 3 && opaque.count == 0 && additive.count == 1 && additive.indices[0] == 5;
	let camera: Vec<float32> = [
		1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0,
		0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0,
	];
	sortBackToFront(alpha, items, camera);
	assert alpha.count == 3;
	assert alpha.indices[0] == 4 && alpha.indices[1] == 6 && alpha.indices[2] == 1;
}

test "perspective alpha sorting uses projected depth including behind-eye unbounded items" {
	let items: Vec<DrawItem> = [
		item(0, 1, 0.0, -2.0), item(0, 1, 0.0, 1.0),
		item(0, 1, 0.0, -8.0), item(0, 1, 0.0, 2.0),
	];
	let phases: Vec<Material> = materials();
	let alpha: PassList = PassList.forPhase(Phase.Alpha);
	collect(alpha, items, phases);
	let camera: Vec<float32> = [
		1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0,
		0.0, 0.0, -1.125, -1.0, 0.0, 0.0, -1.125, 0.0,
	];
	sortBackToFront(alpha, items, camera);
	assert alpha.indices[0] == 2 && alpha.indices[1] == 0;
	assert alpha.indices[2] == 3 && alpha.indices[3] == 1;
}
