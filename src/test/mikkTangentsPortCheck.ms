import { vec3 } from "../math/math3d";
import {
	MeshData,
	MeshError,
	Rgba,
	addSphere,
	addCylinderSides,
	addDisc,
	addGrid,
	addTexturedCube,
	addTexturedQuad,
} from "../void3d/meshData";
import { mikkTangents, mikkTangents32 } from "../void3d/mikkTangents";
import { sortKeyOf } from "../void3d/sortKey";

const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const STRIDE: int32 = 12;

export struct Soup {
	vertices: Vec<float32>;
	indices: Vec<uint16>;
	wideIndices: Vec<uint32>;
	wide: boolean;
}

function emptySoup(): Soup {
	return { vertices: [], indices: [], wideIndices: [], wide: false };
}

function addCorner(
	ref soup: Soup,
	position: Vec<float32>,
	normal: Vec<float32>,
	u: float32,
	v: float32,
): void {
	for (const x of position) { soup.vertices.push(x); }
	for (const x of normal) { soup.vertices.push(x); }
	soup.vertices.push(u);
	soup.vertices.push(v);
	for (let k = 0; k < 4; k++) { soup.vertices.push(1.0); }
}

function addTriangleCorners(
	ref soup: Soup,
	positions: Vec<float32>,
	normal: Vec<float32>,
	uvs: Vec<float32>,
): void {
	for (let k = 0; k < 3; k++) {
		addCorner(
			soup,
			[positions[k * 3], positions[k * 3 + 1], positions[k * 3 + 2]],
			normal,
			uvs[k * 2],
			uvs[k * 2 + 1],
		);
	}
}

function soupOf(data: Readonly<MeshData>): Soup {
	const wide = data.wideIndices;
	return {
		vertices: [...data.vertices],
		indices: [...data.indices],
		wideIndices: wide === null ? [] : [...wide],
		wide: wide !== null,
	};
}

function widened(soup: Soup): Soup {
	let wideIndices: Vec<uint32> = [];
	for (const index of soup.indices) { wideIndices.push(index as uint32); }
	return { vertices: [...soup.vertices], indices: [], wideIndices: wideIndices, wide: true };
}

function unindexed(soup: Soup): Soup {
	let out = emptySoup();
	const count = soup.wide ? soup.wideIndices.length : soup.indices.length;
	for (let c = 0; c < count; c++) {
		const vertex: int32 = soup.wide ? (soup.wideIndices[c] as int32) : (soup.indices[c] as int32);
		for (let k = 0; k < STRIDE; k++) { out.vertices.push(soup.vertices[vertex * STRIDE + k]); }
	}
	return out;
}

function cornerCountOf(soup: Soup): int32 {
	const indexCount: int32 = soup.wide ? soup.wideIndices.length as int32 : soup.indices.length as int32;
	const count: int32 = indexCount > 0 ? indexCount : (soup.vertices.length as int32) / STRIDE;
	return count - count % 3;
}

export function tangentsOf(soup: Soup): Vec<float32> {
	let corners: Vec<float32> = new Array(cornerCountOf(soup) * 4);
	if (soup.wide) {
		mikkTangents32(soup.vertices, STRIDE, soup.wideIndices, corners);
	} else {
		mikkTangents(soup.vertices, STRIDE, soup.indices, corners);
	}
	return corners;
}

function unit(state: uint32): float32 {
	return ((state >> 8) as float32) / 16777216.0;
}

function randomSoup(seed: uint32, vertexCount: int32, triangleCount: int32, lattice: boolean): Soup {
	let state = seed;
	let soup = emptySoup();
	for (let i = 0; i < vertexCount; i++) {
		let position: Vec<float32> = [];
		let normal: Vec<float32> = [0.0, 0.0, 0.0];
		let uv: Vec<float32> = [];
		for (let k = 0; k < 3; k++) {
			state = state ^ (state << 13);
			state = state ^ (state >> 17);
			state = state ^ (state << 5);
			position.push(lattice ? ((state >> 8) % 4) as float32 : unit(state) * 4.0 - 2.0);
		}
		for (let k = 0; k < 2; k++) {
			state = state ^ (state << 13);
			state = state ^ (state >> 17);
			state = state ^ (state << 5);
			uv.push(lattice ? ((state >> 8) % 3) as float32 : unit(state));
		}
		state = state ^ (state << 13);
		state = state ^ (state >> 17);
		state = state ^ (state << 5);
		if (lattice) {
			normal[(state >> 8) % 3] = (state & 1) == 0 ? 1.0 : -1.0;
		} else {
			state = state ^ (state << 13);
			state = state ^ (state >> 17);
			state = state ^ (state << 5);
			const nx = unit(state) - 0.5;
			state = state ^ (state << 13);
			state = state ^ (state >> 17);
			state = state ^ (state << 5);
			const ny = unit(state) - 0.5;
			const nz: float32 = 0.5;
			const inverse = (1.0 as float32) / (Math.sqrt((nx * nx + ny * ny + nz * nz) as float64) as float32);
			normal = [nx * inverse, ny * inverse, nz * inverse];
		}
		addCorner(soup, position, normal, uv[0], uv[1]);
	}
	for (let t = 0; t < triangleCount * 3; t++) {
		state = state ^ (state << 13);
		state = state ^ (state >> 17);
		state = state ^ (state << 5);
		soup.indices.push(((state >> 8) % (vertexCount as uint32)) as uint16);
	}
	return soup;
}

function built(result: Result<int32, MeshError>, name: string): void {
	if (!result.ok) { throw new Error("mikkTangentsPortCheck: " + name + " was refused"); }
}

function primitiveSoups(): Vec<Soup> {
	let soups: Vec<Soup> = [];
	let sphere = MeshData.withUvs();
	built(addSphere(sphere, 2.0, WHITE, 8, 6), "Sphere");
	soups.push(soupOf(sphere));
	let rounder = MeshData.withUvs();
	built(addSphere(rounder, 1.5, WHITE, 24, 14), "Sphere");
	soups.push(soupOf(rounder));
	let cylinder = MeshData.withUvs();
	built(addCylinderSides(cylinder, 1.0, 3.0, true, WHITE, 12), "CylinderSides");
	soups.push(soupOf(cylinder));
	let disc = MeshData.withUvs();
	built(addDisc(disc, 2.0, WHITE, 16), "Disc");
	soups.push(soupOf(disc));
	let grid = MeshData.withUvs();
	built(addGrid(grid, 5, 4, 1.0, 0.5, WHITE), "Grid");
	soups.push(soupOf(grid));
	let cube = MeshData.withUvs();
	built(addTexturedCube(cube, vec3(1.0, 2.0, 3.0), true, WHITE), "TexturedCube");
	soups.push(soupOf(cube));
	let quad = MeshData.withUvs();
	built(addTexturedQuad(
		quad, vec3(0.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0),
		vec3(0.0, 0.0, 1.0), WHITE,
	), "TexturedQuad");
	soups.push(soupOf(quad));
	return soups;
}

function degenerateSoups(): Vec<Soup> {
	const forward: Vec<float32> = [0.0, 0.0, 1.0];
	let soups: Vec<Soup> = [];

	let zeroArea = emptySoup();
	addTriangleCorners(zeroArea, [0, 0, 0, 1, 0, 0, 2, 0, 0], forward, [0, 0, 1, 0, 0, 1]);
	addTriangleCorners(zeroArea, [0, 0, 0, 1, 0, 0, 0, 1, 0], forward, [0, 0, 1, 0, 0, 1]);
	soups.push(zeroArea);

	let repeated = emptySoup();
	addTriangleCorners(repeated, [0, 0, 0, 1, 0, 0, 1, 0, 0], forward, [0, 0, 1, 0, 0, 1]);
	addTriangleCorners(repeated, [0, 0, 0, 1, 0, 0, 0, 1, 0], forward, [0, 0, 1, 0, 0, 1]);
	addTriangleCorners(repeated, [0, 0, 0, 0, 0, 0, 0, 0, 0], forward, [0, 0, 1, 0, 0, 1]);
	addTriangleCorners(repeated, [1, 0, 0, 1, 1, 0, 0, 1, 0], forward, [1, 0, 1, 1, 0, 1]);
	soups.push(repeated);

	let zeroUv = emptySoup();
	addTriangleCorners(zeroUv, [0, 0, 0, 1, 0, 0, 0, 1, 0], forward, [0.5, 0.5, 0.5, 0.5, 0.5, 0.5]);
	addTriangleCorners(zeroUv, [0, 0, 0, 1, 0, 0, 0, 1, 0], forward, [0, 0, 1, 0, 0, 1]);
	addTriangleCorners(zeroUv, [1, 0, 0, 1, 1, 0, 0, 1, 0], forward, [0, 0, 1, 1, 0, 0]);
	soups.push(zeroUv);

	let mirrored = emptySoup();
	addTriangleCorners(mirrored, [0, 0, 0, 1, 0, 0, 1, 1, 0], forward, [0, 0, 1, 0, 1, 1]);
	addTriangleCorners(mirrored, [0, 0, 0, 1, 1, 0, 0, 1, 0], forward, [0, 0, 1, 1, 0, 1]);
	addTriangleCorners(mirrored, [1, 0, 0, 2, 0, 0, 2, 1, 0], forward, [1, 0, 0, 0, 0, 1]);
	addTriangleCorners(mirrored, [1, 0, 0, 2, 1, 0, 1, 1, 0], forward, [1, 0, 0, 1, 1, 1]);
	soups.push(mirrored);

	let single = emptySoup();
	addTriangleCorners(single, [0, 0, 0, 2, 0, 0, 0, 2, 0], forward, [0, 0, 1, 0, 0, 1]);
	soups.push(single);

	let allSame = emptySoup();
	addTriangleCorners(allSame, [1, 1, 1, 1, 1, 1, 1, 1, 1], forward, [0, 0, 1, 0, 0, 1]);
	soups.push(allSame);

	let notANumber = emptySoup();
	addTriangleCorners(notANumber, [0, 0, 0, 1, 0, 0, 0, 1, 0], forward, [0, 0, 1, 0, 0, 1]);
	addTriangleCorners(notANumber, [0, 0, 0, 1, 0, 0, 0, 1, 0], forward, [0, 0, 1, 0, 0, 1]);
	notANumber.vertices[3 * STRIDE + 1] = (0.0 / 0.0) as float32;
	soups.push(notANumber);

	let flatNormal = emptySoup();
	addTriangleCorners(flatNormal, [0, 0, 0, 1, 0, 0, 0, 1, 0], [0.0, 0.0, 0.0], [0, 0, 1, 0, 0, 1]);
	soups.push(flatNormal);
	return soups;
}

// Every mesh both index widths see, indexed and not: the narrow soups, their wide copies, and
// the corners spelled out as a vertex soup.
export function allSoups(): Vec<Soup> {
	let base: Vec<Soup> = primitiveSoups();
	for (const soup of degenerateSoups()) { base.push(soup); }
	base.push(randomSoup(2463534242, 60, 200, false));
	base.push(randomSoup(88172645, 40, 150, true));
	base.push(randomSoup(1234567, 12, 40, true));
	base.push(randomSoup(7654321, 300, 900, false));
	for (let n = 0; n < 40; n++) {
		base.push(randomSoup(1000 + (n as uint32) * 7919, 6 + n % 20, 8 + (n * 5) % 50, n % 2 == 0));
	}
	let all: Vec<Soup> = [];
	for (const soup of base) {
		all.push(soup);
		all.push(widened(soup));
		all.push(unindexed(soup));
	}
	return all;
}

function normalizedKey(x: float32): uint32 {
	return x != x ? 0x7FC00000 : sortKeyOf(x);
}

export function digestOf(corners: Readonly<Span<float32>>, seed: uint32): uint32 {
	let hash = seed;
	for (let i = 0; i < corners.length; i++) {
		hash = (((hash ^ normalizedKey(corners[i])) as uint64 * 16777619) & 0xFFFFFFFF) as uint32;
	}
	return hash;
}

// Pinned from the C version (mikktspace.c through the old glue): mikkTangents matched its output
// bit for bit on all 119520 floats of these 177 meshes, no NaN and no -0 among them. The C traps
// under its checked build on a mesh whose positions share one value on the grid axis (a float cast
// to int out of range, undefined in C); the port gives the cell the x86 conversion gave, 0.
test "mikkTangents over the primitives, degenerate cases and random meshes keeps its recorded digest" {
	const soups = allSoups();
	assert soups.length == 177;
	let hash: uint32 = 2166136261;
	for (const soup of soups) { hash = digestOf(tangentsOf(soup), hash); }
	assert hash == 2759679302;
}

test "a mirrored uv seam flips the written sign" {
	const soups = degenerateSoups();
	const corners = tangentsOf(soups[3]);
	assert corners[3] != corners[27];
}
