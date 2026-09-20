// Port of h3d.col.Bounds: an axis-aligned box, used for what a mesh occupies and later for
// culling and picking (M10). Heaps' Bounds is a class that mutates in place; here it is a
// value struct of two Vec3, so a bounds can be a field, returned, and compared without
// allocating. The mutating builders (addPoint, addPos, addBounds) take `ref`, because
// building a bounds over a vertex array is a loop over one accumulator.
//
// Empty is Heaps' empty(): min at +1e20, max at -1e20, so the first addPoint lands on both
// sides and an empty bounds answers false to every containment test.

import { Vec3, Mat4, vec3 } from "../math/math3d";

export struct Bounds {
	min: Vec3;
	max: Vec3;
}

// Heaps uses 1e20; float32 carries it exactly enough (max ~3.4e38) for the same role.
const EXTENT: float32 = 1e20;

export function empty(this typeof Bounds): Bounds {
	return { min: vec3(EXTENT, EXTENT, EXTENT), max: vec3(-EXTENT, -EXTENT, -EXTENT) };
}

export function all(this typeof Bounds): Bounds {
	return { min: vec3(-EXTENT, -EXTENT, -EXTENT), max: vec3(EXTENT, EXTENT, EXTENT) };
}

export function fromPoints(this typeof Bounds, min: Vec3, max: Vec3): Bounds {
	return { min: min, max: max };
}

// h3d.col.Bounds.fromValues(x, y, z, dx, dy, dz): a corner and a size.
export function fromValues(
	this typeof Bounds,
	x: float32,
	y: float32,
	z: float32,
	sizeX: float32,
	sizeY: float32,
	sizeZ: float32,
): Bounds {
	return { min: vec3(x, y, z), max: vec3(x + sizeX, y + sizeY, z + sizeZ) };
}

export function addPos(ref bounds: Bounds, x: float32, y: float32, z: float32): void {
	if (x < bounds.min.x) { bounds.min.x = x; }
	if (x > bounds.max.x) { bounds.max.x = x; }
	if (y < bounds.min.y) { bounds.min.y = y; }
	if (y > bounds.max.y) { bounds.max.y = y; }
	if (z < bounds.min.z) { bounds.min.z = z; }
	if (z > bounds.max.z) { bounds.max.z = z; }
}

export function addPoint(ref bounds: Bounds, point: Vec3): void {
	addPos(bounds, point.x, point.y, point.z);
}

// Heaps calls this `add`; that name is taken here by std's Set.add / HashSet.add, and a free
// function with a `ref` receiver takes part in that overload set (Compiler notes).
export function addBounds(ref bounds: Bounds, other: Bounds): void {
	if (other.isEmpty()) { return; }
	addPos(bounds, other.min.x, other.min.y, other.min.z);
	addPos(bounds, other.max.x, other.max.y, other.max.z);
}

export function isEmpty(this bounds: Bounds): boolean {
	return bounds.max.x < bounds.min.x ||
		bounds.max.y < bounds.min.y ||
		bounds.max.z < bounds.min.z;
}

// PENDING3D: bounds-empty-size-zero
export function size(this bounds: Bounds): Vec3 {
	if (bounds.isEmpty()) { return vec3(0.0, 0.0, 0.0); }
	return bounds.max - bounds.min;
}

export function center(this bounds: Bounds): Vec3 {
	if (bounds.isEmpty()) { return vec3(0.0, 0.0, 0.0); }
	return (bounds.min + bounds.max).scaled(0.5);
}

// Heaps' `add` merges axis by axis with no emptiness test, so adding an empty box drags the
// result out to ±1e20. This returns early instead — a divergence, and the reason `addBounds`
// over a mixed list of boxes gives the union of the non-empty ones.
// (continued below)

// Heaps' contains: min inclusive, max exclusive, so touching boxes do not both own a point.
export function contains(this bounds: Bounds, point: Vec3): boolean {
	return point.x >= bounds.min.x && point.x < bounds.max.x &&
		point.y >= bounds.min.y && point.y < bounds.max.y &&
		point.z >= bounds.min.z && point.z < bounds.max.z;
}

export function containsBounds(this bounds: Bounds, other: Bounds): boolean {
	return bounds.min.x <= other.min.x && bounds.min.y <= other.min.y &&
		bounds.min.z <= other.min.z && bounds.max.x >= other.max.x &&
		bounds.max.y >= other.max.y && bounds.max.z >= other.max.z;
}

// Heaps' collide: overlap on all three axes, touching counts.
export function collide(this bounds: Bounds, other: Bounds): boolean {
	return !(bounds.min.x > other.max.x || bounds.min.y > other.max.y ||
		bounds.min.z > other.max.z || bounds.max.x < other.min.x ||
		bounds.max.y < other.min.y || bounds.max.z < other.min.z);
}

export function offsetBy(this bounds: Bounds, delta: Vec3): Bounds {
	return { min: bounds.min + delta, max: bounds.max + delta };
}

// h3d.col.Bounds.transform(m): the eight corners through the matrix, re-bounded. An empty
// bounds stays empty, as in Heaps, rather than collapsing onto the matrix translation.
// PENDING3D: bounds-transformed-or
export function transformed(this bounds: Bounds, matrix: Mat4): Bounds {
	if (bounds.isEmpty()) { return bounds; }
	let out: Bounds = Bounds.empty();
	for (let corner = 0; corner < 8; corner++) {
		const point: Vec3 = vec3(
			(corner & 1) == 0 ? bounds.min.x : bounds.max.x,
			(corner & 2) == 0 ? bounds.min.y : bounds.max.y,
			(corner & 4) == 0 ? bounds.min.z : bounds.max.z,
		);
		addPoint(out, point * matrix);
	}
	return out;
}

// The longest edge (Heaps' dimension), and the radius of the sphere around the box.
export function dimension(this bounds: Bounds): float32 {
	const extent: Vec3 = bounds.size();
	let longest: float32 = extent.x;
	if (extent.y > longest) { longest = extent.y; }
	if (extent.z > longest) { longest = extent.z; }
	return longest;
}

// Half the diagonal, computed on the extent scaled down by its longest edge. Heaps squares the
// edges directly (Bounds.hx getBoundingSphereRadius) because its floats are 64-bit; here
// Bounds.all() spans 2e20 per axis and (2e20)² is infinity in float32 long before the square
// root could bring it back.
// PENDING3D: bounds-sphere-rescale
export function boundingSphereRadius(this bounds: Bounds): float32 {
	if (bounds.isEmpty()) { return 0.0; }
	const longest: float32 = bounds.dimension();
	if (longest == 0.0) { return 0.0; }
	const one: float32 = 1.0;
	const half: float32 = 0.5;
	const unit: Vec3 = bounds.size().scaled(one / longest);
	return longest * unit.length() * half;
}

// Zero for an empty box, as `size` and `center` answer, rather than clamping to the +1e20
// corner — the distance from that overflows float32 to infinity, and M10 would read it as a
// very far hit instead of no hit. A picker still has to test `isEmpty` itself.
export function closestPoint(this bounds: Bounds, point: Vec3): Vec3 {
	if (bounds.isEmpty()) { return vec3(0.0, 0.0, 0.0); }
	return vec3(
		clamp(point.x, bounds.min.x, bounds.max.x),
		clamp(point.y, bounds.min.y, bounds.max.y),
		clamp(point.z, bounds.min.z, bounds.max.z),
	);
}

function clamp(value: float32, low: float32, high: float32): float32 {
	if (value < low) { return low; }
	if (value > high) { return high; }
	return value;
}

// `Bounds{min=(0, 0, 0) size=(1, 2, 3)}`, Heaps' toString in the same shape. Allocates, so it
// stays out of the frame loop.
export function toString(this bounds: Bounds): string {
	if (bounds.isEmpty()) { return "Bounds{empty}"; }
	const extent: Vec3 = bounds.size();
	return `Bounds{min=(${bounds.min.x}, ${bounds.min.y}, ${bounds.min.z}) ` +
		`size=(${extent.x}, ${extent.y}, ${extent.z})}`;
}
