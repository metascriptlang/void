import {
	Vec3, Vec4, Mat4, Quat, vec3, vec4, identity, translation, scaling,
	rotationX, rotationY, rotationZ, rotationEuler, composeTransform,
	identityQuat, axisAngle, eulerQuat, quatBetween, transformDirection, colorSaturated,
} from "../math/math3d";
import { approx } from "./helpers";

const HALF_PI: float32 = 1.5707963;

function near(a: Vec3, x: float32, y: float32, z: float32): boolean {
	return approx(a.x, x) && approx(a.y, y) && approx(a.z, z);
}

function sameMatrix(a: Mat4, b: Mat4): boolean {
	return approx(a.m11, b.m11) && approx(a.m12, b.m12) && approx(a.m13, b.m13) && approx(a.m14, b.m14)
		&& approx(a.m21, b.m21) && approx(a.m22, b.m22) && approx(a.m23, b.m23) && approx(a.m24, b.m24)
		&& approx(a.m31, b.m31) && approx(a.m32, b.m32) && approx(a.m33, b.m33) && approx(a.m34, b.m34)
		&& approx(a.m41, b.m41) && approx(a.m42, b.m42) && approx(a.m43, b.m43) && approx(a.m44, b.m44);
}

test "vec3 cross follows the right-hand rule" {
	const z: Vec3 = vec3(1.0, 0.0, 0.0).cross(vec3(0.0, 1.0, 0.0));
	assert near(z, 0.0, 0.0, 1.0);
}

test "vec3 normalized has unit length and keeps zero at zero" {
	assert approx(vec3(3.0, 4.0, 12.0).normalized().length(), 1.0);
	assert near(vec3(0.0, 0.0, 0.0).normalized(), 0.0, 0.0, 0.0);
}

test "point times translation moves it" {
	const p: Vec3 = vec3(1.0, 2.0, 3.0) * translation(10.0, 20.0, 30.0);
	assert near(p, 11.0, 22.0, 33.0);
}

test "direction ignores translation" {
	const d: Vec3 = vec3(1.0, 2.0, 3.0).transformDirection(translation(10.0, 20.0, 30.0));
	assert near(d, 1.0, 2.0, 3.0);
}

test "rotations turn the axes the Heaps way" {
	const aroundX: Vec3 = vec3(0.0, 1.0, 0.0) * rotationX(HALF_PI);
	const aroundY: Vec3 = vec3(0.0, 0.0, 1.0) * rotationY(HALF_PI);
	const aroundZ: Vec3 = vec3(1.0, 0.0, 0.0) * rotationZ(HALF_PI);
	assert near(aroundX, 0.0, 0.0, 1.0);
	assert near(aroundY, 1.0, 0.0, 0.0);
	assert near(aroundZ, 0.0, 1.0, 0.0);
}

test "a times b applies a first" {
	const m: Mat4 = scaling(2.0, 2.0, 2.0) * translation(1.0, 0.0, 0.0);
	const scaledFirst: Vec3 = vec3(1.0, 0.0, 0.0) * m;
	assert near(scaledFirst, 3.0, 0.0, 0.0);
	const n: Mat4 = translation(1.0, 0.0, 0.0) * scaling(2.0, 2.0, 2.0);
	const movedFirst: Vec3 = vec3(1.0, 0.0, 0.0) * n;
	assert near(movedFirst, 4.0, 0.0, 0.0);
}

test "affine product matches the full product on affine operands" {
	const a: Mat4 = rotationEuler(0.3, -0.7, 1.1) * translation(1.0, 2.0, 3.0);
	const b: Mat4 = scaling(2.0, 0.5, 3.0) * rotationY(0.4) * translation(-4.0, 0.0, 5.0);
	const full: Mat4 = a * b;
	assert sameMatrix(a.multiplyAffine(b), full);
}

test "inverse undoes the transform" {
	const m: Mat4 = scaling(2.0, 3.0, 4.0) * rotationEuler(0.3, -0.7, 1.1) * translation(5.0, -6.0, 7.0);
	const undone: Mat4 = m * m.inverse();
	assert sameMatrix(undone, identity());
	assert sameMatrix(m.inverseAffine(), m.inverse());
	const p: Vec3 = vec3(1.5, -2.5, 0.25);
	const moved: Vec3 = p * m;
	const back: Vec3 = moved * m.inverse();
	assert near(back, 1.5, -2.5, 0.25);
}

test "singular matrix inverts to zero" {
	const m: Mat4 = scaling(1.0, 0.0, 1.0);
	assert approx(m.inverse().m11, 0.0);
	assert approx(m.inverse().m44, 0.0);
}

test "normal matrix keeps normals perpendicular under non-uniform scale" {
	const m: Mat4 = scaling(4.0, 1.0, 1.0) * rotationZ(0.3);
	// a slanted surface in the xy plane, its tangent and normal
	const tangent: Vec3 = vec3(1.0, 1.0, 0.0);
	const normal: Vec3 = vec3(-1.0, 1.0, 0.0);
	const movedTangent: Vec3 = tangent.transformDirection(m);
	const movedNormal: Vec3 = normal.transformDirection(m.normalMatrix());
	assert approx(movedTangent.dot(movedNormal), 0.0);
	assert !approx(tangent.transformDirection(m).dot(normal.transformDirection(m)), 0.0);
	const flatNormal: Vec3 =
		vec3(0.0, 0.0, 1.0).transformDirection(scaling(1.0, 1.0, 0.0).normalMatrix());
	assert near(flatNormal, 0.0, 0.0, 1.0);
	const tinyNormal: Vec3 =
		vec3(0.0, 0.0, 1.0).transformDirection(scaling(1.0, 1.0, 1e-15).normalMatrix());
	assert near(tinyNormal, 0.0, 0.0, 1.0);
	const reflected: Mat4 = scaling(-1.0, 1.0, 1.0).normalMatrix();
	assert approx(reflected.m11, -1.0) && approx(reflected.m22, 1.0);
}

test "euler quat matches euler matrix" {
	const q: Quat = eulerQuat(0.3, -0.7, 1.1);
	assert sameMatrix(q.toMatrix(), rotationEuler(0.3, -0.7, 1.1));
}

test "axis-angle quat about y matches rotationY" {
	const q: Quat = axisAngle(vec3(0.0, 2.0, 0.0), 0.9);
	assert approx(q.dot(q), 1.0);
	assert sameMatrix(q.toMatrix(), rotationY(0.9));
}

test "quatBetween carries one unit vector onto another, shortest arc" {
	const zToX: Quat = quatBetween(vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0));
	assert sameMatrix(zToX.toMatrix(), rotationY(HALF_PI));
	const from: Vec3 = vec3(0.35, 0.9, 0.25).normalized();
	const to: Vec3 = vec3(-0.2, 0.4, -0.9).normalized();
	const carried: Vec3 = transformDirection(from, quatBetween(from, to).toMatrix());
	assert near(carried, to.x, to.y, to.z);
	assert near(transformDirection(to, quatBetween(to, to).toMatrix()), to.x, to.y, to.z);
}

test "quatBetween turns a vector onto its opposite through a perpendicular axis" {
	const flipped: Vec3 = transformDirection(
		vec3(0.0, 0.0, 1.0),
		quatBetween(vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, -1.0)).toMatrix(),
	);
	assert near(flipped, 0.0, 0.0, -1.0);
}

test "quatBetween answers a 180-degree turn when the dot rounds past -1" {
	const from: Vec3 = vec3(0.6, 0.64, 0.476).normalized();
	const to: Vec3 = from.scaled(-1.0000001);
	const q: Quat = quatBetween(from, to);
	assert q.w == 0.0;
	assert approx(q.x * q.x + q.y * q.y + q.z * q.z, 1.0);
	const carried: Vec3 = transformDirection(from, q.toMatrix());
	assert near(carried, -from.x, -from.y, -from.z);
}

test "quat product composes like h3d.Quat.multiply" {
	const a: Quat = eulerQuat(0.2, 0.0, 0.0);
	const b: Quat = eulerQuat(0.0, 0.5, 0.0);
	const product: Quat = a * b;
	const matrices: Mat4 = b.toMatrix() * a.toMatrix();
	assert sameMatrix(product.toMatrix(), matrices);
}

test "slerp and nlerp hit both ends and the halfway angle" {
	const a: Quat = identityQuat();
	const b: Quat = axisAngle(vec3(0.0, 1.0, 0.0), 1.2);
	assert sameMatrix(a.slerp(b, 0.0).toMatrix(), identity());
	assert sameMatrix(a.slerp(b, 1.0).toMatrix(), rotationY(1.2));
	assert sameMatrix(a.slerp(b, 0.5).toMatrix(), rotationY(0.6));
	assert sameMatrix(a.nlerp(b, 0.5).toMatrix(), rotationY(0.6));
}

test "slerp takes the short way when quats point apart" {
	const a: Quat = identityQuat();
	const b: Quat = axisAngle(vec3(0.0, 1.0, 0.0), 0.8);
	const flipped: Quat = { x: -b.x, y: -b.y, z: -b.z, w: -b.w };
	assert sameMatrix(a.slerp(flipped, 0.5).toMatrix(), rotationY(0.4));
}

test "composeTransform is scale then rotate then translate" {
	const q: Quat = eulerQuat(0.0, 0.0, HALF_PI);
	const m: Mat4 = composeTransform(vec3(10.0, 0.0, 0.0), q, vec3(2.0, 2.0, 2.0));
	const expected: Mat4 = scaling(2.0, 2.0, 2.0) * rotationZ(HALF_PI) * translation(10.0, 0.0, 0.0);
	assert sameMatrix(m, expected);
	const placed: Vec3 = vec3(1.0, 0.0, 0.0) * m;
	assert near(placed, 10.0, 2.0, 0.0);
}

test "writeTo lays the fields out in upload order" {
	const out: Vec<float32> = new Array(20);
	translation(7.0, 8.0, 9.0).writeTo(out, 2);
	assert approx(out[2], 1.0);
	assert approx(out[7], 1.0);
	assert approx(out[14], 7.0);
	assert approx(out[15], 8.0);
	assert approx(out[16], 9.0);
	assert approx(out[17], 1.0);
}

function luma(this c: Vec4): float32 {
	const weighted: float32 = c.x * 0.212671 + c.y * 0.71516 + c.z * 0.072169;
	return weighted;
}

function within(a: float32, b: float32): boolean {
	let d: float32 = a - b;
	if (d < 0.0) { d = -d; }
	return d < 0.000001;
}

test "colorSaturate at zero is the identity" {
	assert sameMatrix(identity().colorSaturated(0.0), identity());
}

test "colorSaturate at minus one turns a colour into its luma" {
	const c: Vec4 = vec4(0.9, 0.4, 0.1, 1.0);
	const grey: Vec4 = c * identity().colorSaturated(-1.0);
	const luma: float32 = c.luma();
	if (!(within(grey.x, luma) && within(grey.y, luma) && within(grey.z, luma))) {
		console.log(grey.x, grey.y, grey.z, luma);
	}
	assert within(grey.x, luma) && within(grey.y, luma) && within(grey.z, luma);
	assert grey.w == 1.0;
}

test "the scalar form rgb * keep + luma * (1 - keep) is colorSaturate" {
	const amounts: Vec<float32> = [-1.0, -0.5, -0.25, 0.3];
	const colors: Vec<Vec4> = [vec4(0.9, 0.4, 0.1, 1.0), vec4(0.05, 0.6, 0.95, 1.0)];
	const one: float32 = 1.0;
	for (const amount of amounts) {
		for (const c of colors) {
			const byMatrix: Vec4 = c * identity().colorSaturated(amount);
			const keep: float32 = amount + one;
			const grey: float32 = c.luma() * (one - keep);
			const x: float32 = c.x * keep + grey;
			const y: float32 = c.y * keep + grey;
			const z: float32 = c.z * keep + grey;
			if (!(within(byMatrix.x, x) && within(byMatrix.y, y) && within(byMatrix.z, z))) {
				console.log(amount, byMatrix.x, x, byMatrix.y, y, byMatrix.z, z);
			}
			assert within(byMatrix.x, x) && within(byMatrix.y, y) && within(byMatrix.z, z);
		}
	}
}

test "colorSaturate applies after the matrix it composes with" {
	const redOnly: Vec4 = vec4(0.8, 0.5, 0.5, 1.0) * scaling(1.0, 0.0, 0.0).colorSaturated(-1.0);
	const luma: float32 = 0.8 * 0.212671;
	if (!(within(redOnly.x, luma) && within(redOnly.y, luma) && within(redOnly.z, luma))) {
		console.log(redOnly.x, redOnly.y, redOnly.z, luma);
	}
	assert within(redOnly.x, luma) && within(redOnly.y, luma) && within(redOnly.z, luma);
}
