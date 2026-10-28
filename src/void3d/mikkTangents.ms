import { sqrtf } from "../math/mat4";

// MikkTSpace (Morten S. Mikkelsen, 2011, zlib licence: mmikk/MikkTSpace 3e895b49) specialised to
// a mesh of triangles with one UV set, in the order and float32 arithmetic of mikktspace.c, so
// the tangents match the C bit for bit. A face is always a triangle, so the quad paths of the
// original (the diagonal choice, QUAD_ONE_DEGEN_TRI, the forced quad orientation) are absent;
// the C returned 0 when an allocation failed, which has no counterpart here.

const SORT_SEED: uint32 = 39871946;
const GRID_CELLS: int32 = 2048;
const FLT_MIN: float32 = 1.17549435e-38;
const MARK_DEGENERATE: int32 = 1;
const GROUP_WITH_ANY: int32 = 4;
const ORIENT_PRESERVING: int32 = 8;
const ATTRIBUTE_STRIDE: int32 = 8;
const INT32_MIN: int32 = -2147483648;

struct MikkVec3 {
	x: float32;
	y: float32;
	z: float32;
}

struct TriInfos {
	neighbors: Vec<int32>;
	assigned: Vec<int32>;
	vOs: Vec<MikkVec3>;
	vOt: Vec<MikkVec3>;
	magS: Vec<float32>;
	magT: Vec<float32>;
	orgFace: Vec<int32>;
	flags: Vec<int32>;
}

struct Groups {
	start: Vec<int32>;
	count: Vec<int32>;
	representative: Vec<int32>;
	orient: Vec<boolean>;
	members: Vec<int32>;
}

struct TSpace {
	vOs: MikkVec3;
	magS: float32;
	vOt: MikkVec3;
	magT: float32;
	counter: int32;
	orient: boolean;
}

struct EdgeRef {
	i0: int32;
	i1: int32;
	edge: int32;
}

function veq(a: MikkVec3, b: MikkVec3): boolean {
	return a.x == b.x && a.y == b.y && a.z == b.z;
}

function vadd(a: MikkVec3, b: MikkVec3): MikkVec3 {
	return { x: a.x + b.x, y: a.y + b.y, z: a.z + b.z };
}

function vsub(a: MikkVec3, b: MikkVec3): MikkVec3 {
	return { x: a.x - b.x, y: a.y - b.y, z: a.z - b.z };
}

function vscale(s: float32, v: MikkVec3): MikkVec3 {
	return { x: s * v.x, y: s * v.y, z: s * v.z };
}

function vdot(a: MikkVec3, b: MikkVec3): float32 {
	return a.x * b.x + a.y * b.y + a.z * b.z;
}

function magnitude(this v: MikkVec3): float32 {
	return sqrtf(v.x * v.x + v.y * v.y + v.z * v.z);
}

function normalized(this v: MikkVec3): MikkVec3 {
	return vscale(1 / v.magnitude(), v);
}

function notZero(x: float32): boolean {
	return Math.abs(x) > FLT_MIN;
}

function vNotZero(v: MikkVec3): boolean {
	return notZero(v.x) || notZero(v.y) || notZero(v.z);
}

function normalizedIfNotZero(this v: MikkVec3): MikkVec3 {
	return vNotZero(v) ? v.normalized() : v;
}

function projectedOff(v: MikkVec3, n: MikkVec3): MikkVec3 {
	return vsub(v, vscale(vdot(n, v), n)).normalizedIfNotZero();
}

function cornerOf(index: int32): int32 {
	return (index >> 2) * 3 + (index & 3);
}

function positionOf(attributes: Readonly<Span<float32>>, index: int32): MikkVec3 {
	const at = cornerOf(index) * ATTRIBUTE_STRIDE;
	return { x: attributes[at], y: attributes[at + 1], z: attributes[at + 2] };
}

function normalOf(attributes: Readonly<Span<float32>>, index: int32): MikkVec3 {
	const at = cornerOf(index) * ATTRIBUTE_STRIDE;
	return { x: attributes[at + 3], y: attributes[at + 4], z: attributes[at + 5] };
}

function texCoordOf(attributes: Readonly<Span<float32>>, index: int32): MikkVec3 {
	const at = cornerOf(index) * ATTRIBUTE_STRIDE;
	return { x: attributes[at + 6], y: attributes[at + 7], z: 1.0 };
}

function averagedTSpace(a: TSpace, b: TSpace): TSpace {
	if (a.magS == b.magS && a.magT == b.magT && veq(a.vOs, b.vOs) && veq(a.vOt, b.vOt)) {
		return { ...a, counter: 0, orient: false };
	}
	return {
		vOs: vadd(a.vOs, b.vOs).normalizedIfNotZero(),
		magS: 0.5 * (a.magS + b.magS),
		vOt: vadd(a.vOt, b.vOt).normalizedIfNotZero(),
		magT: 0.5 * (a.magT + b.magT),
		counter: 0,
		orient: false,
	};
}

// The C casts a float to int; out of range or NaN it yields INT_MIN on x86-64.
function truncatedToInt32(f: float32): int32 {
	if (!(f >= -2147483648.0 && f < 2147483648.0)) { return INT32_MIN; }
	return f as int32;
}

function gridCellOf(fMin: float32, fMax: float32, fVal: float32): int32 {
	const fIndex: float32 = (GRID_CELLS as float32) * ((fVal - fMin) / (fMax - fMin));
	const index = truncatedToInt32(fIndex);
	return index < GRID_CELLS ? (index >= 0 ? index : 0) : GRID_CELLS - 1;
}

function weldVertices(
	triList: Span<int32>,
	attributes: Readonly<Span<float32>>,
	triangleCount: int32,
): void {
	const total = triangleCount * 3;
	let vMin = positionOf(attributes, 0);
	let vMax = vMin;
	for (let i = 1; i < total; i++) {
		const vP = positionOf(attributes, triList[i]);
		if (vMin.x > vP.x) { vMin.x = vP.x; } else if (vMax.x < vP.x) { vMax.x = vP.x; }
		if (vMin.y > vP.y) { vMin.y = vP.y; } else if (vMax.y < vP.y) { vMax.y = vP.y; }
		if (vMin.z > vP.z) { vMin.z = vP.z; } else if (vMax.z < vP.z) { vMax.z = vP.z; }
	}

	const vDim = vsub(vMax, vMin);
	let channel = 0;
	let fMin = vMin.x;
	let fMax = vMax.x;
	if (vDim.y > vDim.x && vDim.y > vDim.z) {
		channel = 1;
		fMin = vMin.y;
		fMax = vMax.y;
	} else if (vDim.z > vDim.x) {
		channel = 2;
		fMin = vMin.z;
		fMax = vMax.z;
	}

	let cellOfCorner: Vec<int32> = new Array(total);
	let hashCount: Vec<int32> = new Array(GRID_CELLS);
	for (let i = 0; i < total; i++) {
		const vP = positionOf(attributes, triList[i]);
		const fVal = channel == 0 ? vP.x : (channel == 1 ? vP.y : vP.z);
		const cell = gridCellOf(fMin, fMax, fVal);
		cellOfCorner[i] = cell;
		hashCount[cell] += 1;
	}

	let hashOffsets: Vec<int32> = new Array(GRID_CELLS);
	for (let k = 1; k < GRID_CELLS; k++) {
		hashOffsets[k] = hashOffsets[k - 1] + hashCount[k - 1];
	}

	let hashTable: Vec<int32> = new Array(total);
	let hashFilled: Vec<int32> = new Array(GRID_CELLS);
	for (let i = 0; i < total; i++) {
		const cell = cellOfCorner[i];
		hashTable[hashOffsets[cell] + hashFilled[cell]] = i;
		hashFilled[cell] += 1;
	}

	let maxCount = hashCount[0];
	for (let k = 1; k < GRID_CELLS; k++) {
		if (maxCount < hashCount[k]) { maxCount = hashCount[k]; }
	}
	let tmpVert: Vec<float32> = new Array(maxCount * 3);
	let tmpIndex: Vec<int32> = new Array(maxCount);

	for (let k = 0; k < GRID_CELLS; k++) {
		const entries = hashCount[k];
		if (entries < 2) { continue; }
		const tableAt = hashOffsets[k];
		for (let e = 0; e < entries; e++) {
			const i = hashTable[tableAt + e];
			const vP = positionOf(attributes, triList[i]);
			tmpVert[e * 3] = vP.x;
			tmpVert[e * 3 + 1] = vP.y;
			tmpVert[e * 3 + 2] = vP.z;
			tmpIndex[e] = i;
		}
		mergeVertsFast(triList, tmpVert, tmpIndex, attributes, 0, entries - 1);
	}
}

function swapTmpVerts(tmpVert: Span<float32>, tmpIndex: Span<int32>, a: int32, b: int32): void {
	for (let c = 0; c < 3; c++) {
		const swapped = tmpVert[a * 3 + c];
		tmpVert[a * 3 + c] = tmpVert[b * 3 + c];
		tmpVert[b * 3 + c] = swapped;
	}
	const swappedIndex = tmpIndex[a];
	tmpIndex[a] = tmpIndex[b];
	tmpIndex[b] = swappedIndex;
}

function mergeVertsFast(
	triList: Span<int32>,
	tmpVert: Span<float32>,
	tmpIndex: Span<int32>,
	attributes: Readonly<Span<float32>>,
	iLIn: int32,
	iRIn: int32,
): void {
	let fvMin: Vec<float32> = [tmpVert[iLIn * 3], tmpVert[iLIn * 3 + 1], tmpVert[iLIn * 3 + 2]];
	let fvMax: Vec<float32> = [fvMin[0], fvMin[1], fvMin[2]];
	for (let l = iLIn + 1; l <= iRIn; l++) {
		for (let c = 0; c < 3; c++) {
			if (fvMin[c] > tmpVert[l * 3 + c]) { fvMin[c] = tmpVert[l * 3 + c]; }
			if (fvMax[c] < tmpVert[l * 3 + c]) { fvMax[c] = tmpVert[l * 3 + c]; }
		}
	}

	const dx: float32 = fvMax[0] - fvMin[0];
	const dy: float32 = fvMax[1] - fvMin[1];
	const dz: float32 = fvMax[2] - fvMin[2];

	let channel = 0;
	if (dy > dx && dy > dz) { channel = 1; } else if (dz > dx) { channel = 2; }

	const fSep: float32 = 0.5 * (fvMax[channel] + fvMin[channel]);

	if (!Number.isFinite(fSep)) { return; }

	if (fSep >= fvMax[channel] || fSep <= fvMin[channel]) {
		for (let l = iLIn; l <= iRIn; l++) {
			const i = tmpIndex[l];
			const index = triList[i];
			const vP = positionOf(attributes, index);
			const vN = normalOf(attributes, index);
			const vT = texCoordOf(attributes, index);

			let notFound = true;
			let l2 = iLIn;
			let i2rec = -1;
			while (l2 < l && notFound) {
				const i2 = tmpIndex[l2];
				const index2 = triList[i2];
				const vP2 = positionOf(attributes, index2);
				const vN2 = normalOf(attributes, index2);
				const vT2 = texCoordOf(attributes, index2);
				i2rec = i2;

				if (vP.x == vP2.x && vP.y == vP2.y && vP.z == vP2.z &&
					vN.x == vN2.x && vN.y == vN2.y && vN.z == vN2.z &&
					vT.x == vT2.x && vT.y == vT2.y && vT.z == vT2.z) {
					notFound = false;
				} else {
					l2++;
				}
			}

			if (!notFound) { triList[i] = triList[i2rec]; }
		}
		return;
	}

	let iL = iLIn;
	let iR = iRIn;
	while (iL < iR) {
		let readyLeftSwap = false;
		let readyRightSwap = false;
		while (!readyLeftSwap && iL < iR) {
			readyLeftSwap = !(tmpVert[iL * 3 + channel] < fSep);
			if (!readyLeftSwap) { iL++; }
		}
		while (!readyRightSwap && iL < iR) {
			readyRightSwap = tmpVert[iR * 3 + channel] < fSep;
			if (!readyRightSwap) { iR--; }
		}

		if (readyLeftSwap && readyRightSwap) {
			swapTmpVerts(tmpVert, tmpIndex, iL, iR);
			iL++;
			iR--;
		}
	}

	if (iL == iR) {
		const readyRightSwap = tmpVert[iR * 3 + channel] < fSep;
		if (readyRightSwap) { iL++; } else { iR--; }
	}

	if (iLIn < iR) { mergeVertsFast(triList, tmpVert, tmpIndex, attributes, iLIn, iR); }
	if (iL < iRIn) { mergeVertsFast(triList, tmpVert, tmpIndex, attributes, iL, iRIn); }
}



function newTriInfos(count: int32): TriInfos {
	let tris: TriInfos = {
		neighbors: new Array(count * 3),
		assigned: new Array(count * 3),
		vOs: [],
		vOt: [],
		magS: new Array(count),
		magT: new Array(count),
		orgFace: new Array(count),
		flags: new Array(count),
	};
	for (let f = 0; f < count; f++) {
		tris.vOs.push({ x: 0.0, y: 0.0, z: 0.0 });
		tris.vOt.push({ x: 0.0, y: 0.0, z: 0.0 });
	}
	for (let i = 0; i < count * 3; i++) {
		tris.neighbors[i] = -1;
		tris.assigned[i] = -1;
	}
	return tris;
}

function markDegenerates(
	ref tris: TriInfos,
	triList: Readonly<Span<int32>>,
	attributes: Readonly<Span<float32>>,
	triangleCount: int32,
): int32 {
	let degenerates = 0;
	for (let t = 0; t < triangleCount; t++) {
		const p0 = positionOf(attributes, triList[t * 3]);
		const p1 = positionOf(attributes, triList[t * 3 + 1]);
		const p2 = positionOf(attributes, triList[t * 3 + 2]);
		if (veq(p0, p1) || veq(p0, p2) || veq(p1, p2)) {
			tris.flags[t] |= MARK_DEGENERATE;
			degenerates++;
		}
	}
	return degenerates;
}

function swapTriangles(ref tris: TriInfos, triList: Span<int32>, a: int32, b: int32): void {
	for (let i = 0; i < 3; i++) {
		const index = triList[a * 3 + i];
		triList[a * 3 + i] = triList[b * 3 + i];
		triList[b * 3 + i] = index;
	}
	const face = tris.orgFace[a];
	tris.orgFace[a] = tris.orgFace[b];
	tris.orgFace[b] = face;
	const flag = tris.flags[a];
	tris.flags[a] = tris.flags[b];
	tris.flags[b] = flag;
}

function degenPrologue(
	ref tris: TriInfos,
	triList: Span<int32>,
	goodCount: int32,
	totalCount: int32,
): void {
	let nextGood = 1;
	let t = 0;
	let stillFindingGoodOnes = true;
	while (t < goodCount && stillFindingGoodOnes) {
		if ((tris.flags[t] & MARK_DEGENERATE) == 0) {
			if (nextGood < t + 2) { nextGood = t + 2; }
		} else {
			let justADegenerate = true;
			while (justADegenerate && nextGood < totalCount) {
				if ((tris.flags[nextGood] & MARK_DEGENERATE) == 0) {
					justADegenerate = false;
				} else {
					nextGood++;
				}
			}

			const t1 = nextGood;
			nextGood++;
			if (!justADegenerate) {
				swapTriangles(tris, triList, t, t1);
			} else {
				stillFindingGoodOnes = false;
			}
		}

		if (stillFindingGoodOnes) { t++; }
	}
}

function initTriInfo(
	ref tris: TriInfos,
	triList: Span<int32>,
	attributes: Readonly<Span<float32>>,
	triangleCount: int32,
): void {
	for (let f = 0; f < triangleCount; f++) {
		tris.flags[f] |= GROUP_WITH_ANY;
	}

	for (let f = 0; f < triangleCount; f++) {
		const v1 = positionOf(attributes, triList[f * 3]);
		const v2 = positionOf(attributes, triList[f * 3 + 1]);
		const v3 = positionOf(attributes, triList[f * 3 + 2]);
		const t1 = texCoordOf(attributes, triList[f * 3]);
		const t2 = texCoordOf(attributes, triList[f * 3 + 1]);
		const t3 = texCoordOf(attributes, triList[f * 3 + 2]);

		const t21x: float32 = t2.x - t1.x;
		const t21y: float32 = t2.y - t1.y;
		const t31x: float32 = t3.x - t1.x;
		const t31y: float32 = t3.y - t1.y;
		const d1 = vsub(v2, v1);
		const d2 = vsub(v3, v1);

		const fSignedAreaSTx2: float32 = t21x * t31y - t21y * t31x;
		const vOs = vsub(vscale(t31y, d1), vscale(t21y, d2));
		const vOt = vadd(vscale(-t31x, d1), vscale(t21x, d2));

		if (fSignedAreaSTx2 > 0) { tris.flags[f] |= ORIENT_PRESERVING; }

		if (notZero(fSignedAreaSTx2)) {
			const fAbsArea = Math.abs(fSignedAreaSTx2 as float64) as float32;
			const fLenOs = vOs.magnitude();
			const fLenOt = vOt.magnitude();
			const fS: float32 = (tris.flags[f] & ORIENT_PRESERVING) == 0 ? -1.0 : 1.0;
			if (notZero(fLenOs)) { tris.vOs[f] = vscale(fS / fLenOs, vOs); }
			if (notZero(fLenOt)) { tris.vOt[f] = vscale(fS / fLenOt, vOt); }

			tris.magS[f] = fLenOs / fAbsArea;
			tris.magT[f] = fLenOt / fAbsArea;

			if (notZero(tris.magS[f]) && notZero(tris.magT[f])) {
				tris.flags[f] &= ~GROUP_WITH_ANY;
			}
		}
	}

	buildNeighbors(tris, triList, triangleCount);
}

function edgeOf(triList: Readonly<Span<int32>>, at: int32, i0In: int32, i1In: int32): EdgeRef {
	if (triList[at] == i0In || triList[at] == i1In) {
		if (triList[at + 1] == i0In || triList[at + 1] == i1In) {
			return { i0: triList[at], i1: triList[at + 1], edge: 0 };
		}
		return { i0: triList[at + 2], i1: triList[at], edge: 2 };
	}
	return { i0: triList[at + 1], i1: triList[at + 2], edge: 1 };
}

function swapEdges(edges: Span<int32>, a: int32, b: int32): void {
	for (let c = 0; c < 3; c++) {
		const swapped = edges[a * 3 + c];
		edges[a * 3 + c] = edges[b * 3 + c];
		edges[b * 3 + c] = swapped;
	}
}

function quickSortEdges(
	edges: Span<int32>,
	iLeft: int32,
	iRight: int32,
	channel: int32,
	seedIn: uint32,
): void {
	const elems = iRight - iLeft + 1;
	if (elems < 2) { return; }
	if (elems == 2) {
		if (edges[iLeft * 3 + channel] > edges[iRight * 3 + channel]) {
			swapEdges(edges, iLeft, iRight);
		}
		return;
	}

	const seed = nextSeed(seedIn);
	let iL = iLeft;
	let iR = iRight;
	const index = (seed % ((iR - iL + 1) as uint32)) as int32;
	const iMid = edges[(index + iL) * 3 + channel];

	do {
		while (edges[iL * 3 + channel] < iMid) { iL++; }
		while (edges[iR * 3 + channel] > iMid) { iR--; }

		if (iL <= iR) {
			swapEdges(edges, iL, iR);
			iL++;
			iR--;
		}
	} while (iL <= iR);

	if (iLeft < iR) { quickSortEdges(edges, iLeft, iR, channel, seed); }
	if (iL < iRight) { quickSortEdges(edges, iL, iRight, channel, seed); }
}

function nextSeed(seed: uint32): uint32 {
	const t: uint32 = seed & 31;
	const rotated: uint32 = (seed << t) | (seed >> ((32 - t) & 31));
	return seed + rotated + 3;
}

function buildNeighbors(
	ref tris: TriInfos,
	triList: Readonly<Span<int32>>,
	triangleCount: int32,
): void {
	let edges: Vec<int32> = new Array(triangleCount * 9);
	for (let f = 0; f < triangleCount; f++) {
		for (let i = 0; i < 3; i++) {
			const i0 = triList[f * 3 + i];
			const i1 = triList[f * 3 + (i < 2 ? i + 1 : 0)];
			edges[(f * 3 + i) * 3] = i0 < i1 ? i0 : i1;
			edges[(f * 3 + i) * 3 + 1] = !(i0 < i1) ? i0 : i1;
			edges[(f * 3 + i) * 3 + 2] = f;
		}
	}

	const entries = triangleCount * 3;
	quickSortEdges(edges, 0, entries - 1, 0, SORT_SEED);

	let curStartIndex = 0;
	for (let i = 1; i < entries; i++) {
		if (edges[curStartIndex * 3] != edges[i * 3]) {
			const iL = curStartIndex;
			curStartIndex = i;
			quickSortEdges(edges, iL, i - 1, 1, SORT_SEED);
		}
	}

	curStartIndex = 0;
	for (let i = 1; i < entries; i++) {
		if (edges[curStartIndex * 3] != edges[i * 3] ||
			edges[curStartIndex * 3 + 1] != edges[i * 3 + 1]) {
			const iL = curStartIndex;
			curStartIndex = i;
			quickSortEdges(edges, iL, i - 1, 2, SORT_SEED);
		}
	}

	for (let i = 0; i < entries; i++) {
		const i0 = edges[i * 3];
		const i1 = edges[i * 3 + 1];
		const f = edges[i * 3 + 2];

		const edgeA = edgeOf(triList, f * 3, i0, i1);
		if (tris.neighbors[f * 3 + edgeA.edge] != -1) { continue; }

		let j = i + 1;
		let notFound = true;
		let edgeNumB = 0;
		while (j < entries && i0 == edges[j * 3] && i1 == edges[j * 3 + 1] && notFound) {
			const t = edges[j * 3 + 2];
			const flipped = edgeOf(triList, t * 3, edges[j * 3], edges[j * 3 + 1]);
			edgeNumB = flipped.edge;
			const unassignedB = tris.neighbors[t * 3 + edgeNumB] == -1;
			if (edgeA.i0 == flipped.i1 && edgeA.i1 == flipped.i0 && unassignedB) {
				notFound = false;
			} else {
				j++;
			}
		}

		if (!notFound) {
			const t = edges[j * 3 + 2];
			tris.neighbors[f * 3 + edgeA.edge] = t;
			tris.neighbors[t * 3 + edgeNumB] = f;
		}
	}
}

function addTriToGroup(ref groups: Groups, g: int32, triIndex: int32): void {
	groups.members[groups.start[g] + groups.count[g]] = triIndex;
	groups.count[g] += 1;
}

function assignRecur(
	triList: Readonly<Span<int32>>,
	ref tris: TriInfos,
	ref groups: Groups,
	myTri: int32,
	g: int32,
): boolean {
	const vertRep = groups.representative[g];
	let i = -1;
	if (triList[3 * myTri] == vertRep) {
		i = 0;
	} else if (triList[3 * myTri + 1] == vertRep) {
		i = 1;
	} else if (triList[3 * myTri + 2] == vertRep) {
		i = 2;
	}
	if (i < 0) { throw new Error("mikkTangents: a group's vertex is not on its triangle"); }

	if (tris.assigned[myTri * 3 + i] == g) { return true; }
	if (tris.assigned[myTri * 3 + i] != -1) { return false; }
	if ((tris.flags[myTri] & GROUP_WITH_ANY) != 0) {
		if (tris.assigned[myTri * 3] == -1 &&
			tris.assigned[myTri * 3 + 1] == -1 &&
			tris.assigned[myTri * 3 + 2] == -1) {
			tris.flags[myTri] &= ~ORIENT_PRESERVING;
			if (groups.orient[g]) { tris.flags[myTri] |= ORIENT_PRESERVING; }
		}
	}
	const orient = (tris.flags[myTri] & ORIENT_PRESERVING) != 0;
	if (orient != groups.orient[g]) { return false; }

	addTriToGroup(groups, g, myTri);
	tris.assigned[myTri * 3 + i] = g;

	const neighL = tris.neighbors[myTri * 3 + i];
	const neighR = tris.neighbors[myTri * 3 + (i > 0 ? i - 1 : 2)];
	if (neighL >= 0) { assignRecur(triList, tris, groups, neighL, g); }
	if (neighR >= 0) { assignRecur(triList, tris, groups, neighR, g); }

	return true;
}

function build4RuleGroups(
	ref tris: TriInfos,
	ref groups: Groups,
	triList: Readonly<Span<int32>>,
	triangleCount: int32,
): int32 {
	let activeGroups = 0;
	let offset = 0;
	for (let f = 0; f < triangleCount; f++) {
		for (let i = 0; i < 3; i++) {
			if ((tris.flags[f] & GROUP_WITH_ANY) != 0 || tris.assigned[f * 3 + i] != -1) {
				continue;
			}

			const g = activeGroups;
			tris.assigned[f * 3 + i] = g;
			groups.start.push(offset);
			groups.count.push(0);
			groups.representative.push(triList[f * 3 + i]);
			groups.orient.push((tris.flags[f] & ORIENT_PRESERVING) != 0);
			activeGroups++;

			addTriToGroup(groups, g, f);
			const neighL = tris.neighbors[f * 3 + i];
			const neighR = tris.neighbors[f * 3 + (i > 0 ? i - 1 : 2)];
			if (neighL >= 0) { assignRecur(triList, tris, groups, neighL, g); }
			if (neighR >= 0) { assignRecur(triList, tris, groups, neighR, g); }

			offset += groups.count[g];
		}
	}
	return activeGroups;
}

function quickSortMembers(members: Span<int32>, iLeft: int32, iRight: int32, seedIn: uint32): void {
	const seed = nextSeed(seedIn);
	let iL = iLeft;
	let iR = iRight;
	const index = (seed % ((iR - iL + 1) as uint32)) as int32;
	const iMid = members[index + iL];

	do {
		while (members[iL] < iMid) { iL++; }
		while (members[iR] > iMid) { iR--; }

		if (iL <= iR) {
			const swapped = members[iL];
			members[iL] = members[iR];
			members[iR] = swapped;
			iL++;
			iR--;
		}
	} while (iL <= iR);

	if (iLeft < iR) { quickSortMembers(members, iLeft, iR, seed); }
	if (iL < iRight) { quickSortMembers(members, iL, iRight, seed); }
}

function evalTSpace(
	faceIndices: Readonly<Span<int32>>,
	faceCount: int32,
	triList: Readonly<Span<int32>>,
	tris: Readonly<TriInfos>,
	attributes: Readonly<Span<float32>>,
	vertexRepresentative: int32,
): TSpace {
	let resOs: MikkVec3 = { x: 0.0, y: 0.0, z: 0.0 };
	let resOt: MikkVec3 = { x: 0.0, y: 0.0, z: 0.0 };
	let resMagS: float32 = 0;
	let resMagT: float32 = 0;
	let angleSum: float32 = 0;

	for (let face = 0; face < faceCount; face++) {
		const f = faceIndices[face];
		if ((tris.flags[f] & GROUP_WITH_ANY) != 0) { continue; }

		let i = -1;
		if (triList[3 * f] == vertexRepresentative) {
			i = 0;
		} else if (triList[3 * f + 1] == vertexRepresentative) {
			i = 1;
		} else if (triList[3 * f + 2] == vertexRepresentative) {
			i = 2;
		}
		if (i < 0) { throw new Error("mikkTangents: a subgroup's vertex is not on its triangle"); }

		const n = normalOf(attributes, triList[3 * f + i]);
		const vOs = projectedOff(tris.vOs[f], n);
		const vOt = projectedOff(tris.vOt[f], n);

		const i2 = triList[3 * f + (i < 2 ? i + 1 : 0)];
		const i1 = triList[3 * f + i];
		const i0 = triList[3 * f + (i > 0 ? i - 1 : 2)];

		const p0 = positionOf(attributes, i0);
		const p1 = positionOf(attributes, i1);
		const p2 = positionOf(attributes, i2);
		const v1 = projectedOff(vsub(p0, p1), n);
		const v2 = projectedOff(vsub(p2, p1), n);

		let fCos: float32 = vdot(v1, v2);
		fCos = fCos > 1 ? 1 : (fCos < -1 ? -1 : fCos);
		const fAngle = Math.acos(fCos as float64) as float32;
		const fMagS = tris.magS[f];
		const fMagT = tris.magT[f];

		resOs = vadd(resOs, vscale(fAngle, vOs));
		resOt = vadd(resOt, vscale(fAngle, vOt));
		resMagS += fAngle * fMagS;
		resMagT += fAngle * fMagT;
		angleSum += fAngle;
	}

	resOs = resOs.normalizedIfNotZero();
	resOt = resOt.normalizedIfNotZero();
	if (angleSum > 0) {
		resMagS /= angleSum;
		resMagT /= angleSum;
	}

	return { vOs: resOs, magS: resMagS, vOt: resOt, magT: resMagT, counter: 0, orient: false };
}

function generateTSpaces(
	ref tspaces: Vec<TSpace>,
	tris: Readonly<TriInfos>,
	groups: Readonly<Groups>,
	activeGroups: int32,
	triList: Readonly<Span<int32>>,
	thresCos: float32,
	attributes: Readonly<Span<float32>>,
): void {
	let maxFaces = 0;
	for (let g = 0; g < activeGroups; g++) {
		if (maxFaces < groups.count[g]) { maxFaces = groups.count[g]; }
	}
	if (maxFaces == 0) { return; }

	let tmpMembers: Vec<int32> = new Array(maxFaces);

	for (let g = 0; g < activeGroups; g++) {
		const groupStart = groups.start[g];
		const groupCount = groups.count[g];
		let uniStart: Vec<int32> = [];
		let uniCount: Vec<int32> = [];
		let uniMembers: Vec<int32> = [];
		let subGroupTSpace: Vec<TSpace> = [];

		for (let i = 0; i < groupCount; i++) {
			const f = groups.members[groupStart + i];
			let index = -1;
			if (tris.assigned[f * 3] == g) {
				index = 0;
			} else if (tris.assigned[f * 3 + 1] == g) {
				index = 1;
			} else if (tris.assigned[f * 3 + 2] == g) {
				index = 2;
			}
			if (index < 0) { throw new Error("mikkTangents: a group's triangle does not belong to it"); }

			const n = normalOf(attributes, triList[f * 3 + index]);
			const vOs = projectedOff(tris.vOs[f], n);
			const vOt = projectedOff(tris.vOt[f], n);
			const orgFace1 = tris.orgFace[f];

			let members = 0;
			for (let j = 0; j < groupCount; j++) {
				const t = groups.members[groupStart + j];
				const vOs2 = projectedOff(tris.vOs[t], n);
				const vOt2 = projectedOff(tris.vOt[t], n);

				const any = ((tris.flags[f] | tris.flags[t]) & GROUP_WITH_ANY) != 0;
				const sameOrgFace = orgFace1 == tris.orgFace[t];

				const fCosS = vdot(vOs, vOs2);
				const fCosT = vdot(vOt, vOt2);

				if (any || sameOrgFace || (fCosS > thresCos && fCosT > thresCos)) {
					tmpMembers[members] = t;
					members++;
				}
			}

			if (members > 1) { quickSortMembers(tmpMembers, 0, members - 1, SORT_SEED); }

			let found = false;
			let l = 0;
			while (l < uniStart.length && !found) {
				found = uniCount[l] == members;
				for (let m = 0; found && m < members; m++) {
					found = tmpMembers[m] == uniMembers[uniStart[l] + m];
				}
				if (!found) { l++; }
			}

			if (!found) {
				uniStart.push(uniMembers.length);
				uniCount.push(members);
				for (let m = 0; m < members; m++) { uniMembers.push(tmpMembers[m]); }
				subGroupTSpace.push(
					evalTSpace(tmpMembers, members, triList, tris, attributes, groups.representative[g]),
				);
			}

			const outAt = tris.orgFace[f] * 3 + index;
			const orient = groups.orient[g];
			if (tspaces[outAt].counter == 1) {
				let averaged = averagedTSpace(tspaces[outAt], subGroupTSpace[l]);
				averaged.counter = 2;
				averaged.orient = orient;
				tspaces[outAt] = averaged;
			} else {
				let copied = subGroupTSpace[l];
				copied.counter = 1;
				copied.orient = orient;
				tspaces[outAt] = copied;
			}
		}
	}
}

function degenEpilogue(
	ref tspaces: Vec<TSpace>,
	tris: Readonly<TriInfos>,
	triList: Readonly<Span<int32>>,
	goodCount: int32,
	totalCount: int32,
): void {
	for (let t = goodCount; t < totalCount; t++) {
		for (let i = 0; i < 3; i++) {
			const index1 = triList[t * 3 + i];
			let j = 0;
			while (j < 3 * goodCount && triList[j] != index1) { j++; }

			if (j < 3 * goodCount) {
				const srcAt = tris.orgFace[j / 3] * 3 + j % 3;
				const dstAt = tris.orgFace[t] * 3 + i;
				tspaces[dstAt] = tspaces[srcAt];
			}
		}
	}
}

function generateTangentCorners(
	attributes: Readonly<Span<float32>>,
	faceCount: int32,
	corners: Span<float32>,
): void {
	let tris = newTriInfos(faceCount);
	let triList: Vec<int32> = new Array(faceCount * 3);
	for (let f = 0; f < faceCount; f++) {
		tris.orgFace[f] = f;
		tris.flags[f] = 0;
		for (let v = 0; v < 3; v++) { triList[f * 3 + v] = (f << 2) | v; }
	}

	weldVertices(triList, attributes, faceCount);

	const degenerates = markDegenerates(tris, triList, attributes, faceCount);
	const goodCount = faceCount - degenerates;
	degenPrologue(tris, triList, goodCount, faceCount);
	initTriInfo(tris, triList, attributes, goodCount);

	let groups: Groups = {
		start: [],
		count: [],
		representative: [],
		orient: [],
		members: new Array(goodCount * 3),
	};
	const activeGroups = build4RuleGroups(tris, groups, triList, goodCount);

	let tspaces: Vec<TSpace> = [];
	for (let t = 0; t < faceCount * 3; t++) {
		tspaces.push({
			vOs: { x: 1.0, y: 0.0, z: 0.0 },
			magS: 1.0,
			vOt: { x: 0.0, y: 1.0, z: 0.0 },
			magT: 1.0,
			counter: 0,
			orient: false,
		});
	}

	const thresholdRadians: float32 = (180.0 * (Math.PI as float32)) / 180.0;
	const thresCos = Math.cos(thresholdRadians as float64) as float32;
	generateTSpaces(tspaces, tris, groups, activeGroups, triList, thresCos, attributes);
	degenEpilogue(tspaces, tris, triList, goodCount, faceCount);

	for (let at = 0; at < faceCount * 3; at++) {
		const space = tspaces[at];
		corners[at * 4] = space.vOs.x;
		corners[at * 4 + 1] = space.vOs.y;
		corners[at * 4 + 2] = space.vOs.z;
		corners[at * 4 + 3] = space.orient ? -1.0 : 1.0;
	}
}

function fillAttributes(
	vertices: Readonly<Span<float32>>,
	stride: int32,
	cornerVertex: Readonly<Span<int32>>,
): Vec<float32> {
	let attributes: Vec<float32> = new Array(cornerVertex.length * ATTRIBUTE_STRIDE);
	for (let c = 0; c < cornerVertex.length; c++) {
		for (let k = 0; k < ATTRIBUTE_STRIDE; k++) {
			attributes[c * ATTRIBUTE_STRIDE + k] = vertices[cornerVertex[c] * stride + k];
		}
	}
	return attributes;
}

function checkedCornerCount(
	vertexFloats: int32,
	stride: int32,
	indexCount: int32,
	cornerFloats: int32,
): int32 {
	if (stride < 8 || vertexFloats % stride != 0 || cornerFloats % 12 != 0) {
		throw new Error("mikkTangents: the vertex stride or the corner count is invalid");
	}
	const cornerCount = cornerFloats / 4;
	const available = indexCount > 0 ? indexCount : vertexFloats / stride;
	if (cornerCount > available) { throw new Error("mikkTangents: more corners than indices"); }
	return cornerCount;
}

// Writes, per triangle corner c (vertex indices[c], or c itself with no indices), the tangent
// xyz and the negated MikkTSpace sign into corners[c * 4..]. A vertex is position 3, normal 3,
// uv 2, then whatever else, `stride` floats apart.
export function mikkTangents(
	vertices: Readonly<Span<float32>>,
	stride: int32,
	indices: Readonly<Span<uint16>>,
	corners: Span<float32>,
): void {
	const cornerCount = checkedCornerCount(
		vertices.length as int32, stride, indices.length as int32, corners.length as int32,
	);
	if (cornerCount == 0) { return; }
	const vertexCount = (vertices.length as int32) / stride;
	let cornerVertex: Vec<int32> = new Array(cornerCount);
	for (let c = 0; c < cornerCount; c++) {
		const vertex = indices.length > 0 ? (indices[c] as int32) : c;
		if (vertex >= vertexCount) { throw new Error("mikkTangents: an index is out of range"); }
		cornerVertex[c] = vertex;
	}
	generateTangentCorners(fillAttributes(vertices, stride, cornerVertex), cornerCount / 3, corners);
}

export function mikkTangents32(
	vertices: Readonly<Span<float32>>,
	stride: int32,
	indices: Readonly<Span<uint32>>,
	corners: Span<float32>,
): void {
	const cornerCount = checkedCornerCount(
		vertices.length as int32, stride, indices.length as int32, corners.length as int32,
	);
	if (cornerCount == 0) { return; }
	const vertexCount = (vertices.length as int32) / stride;
	let cornerVertex: Vec<int32> = new Array(cornerCount);
	for (let c = 0; c < cornerCount; c++) {
		const index = indices.length > 0 ? indices[c] : (c as uint32);
		if (index >= (vertexCount as uint32)) { throw new Error("mikkTangents: an index is out of range"); }
		cornerVertex[c] = index as int32;
	}
	generateTangentCorners(fillAttributes(vertices, stride, cornerVertex), cornerCount / 3, corners);
}
