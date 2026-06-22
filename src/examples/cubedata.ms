// Cube geometry in MetaScript. float32[]/uint16[] are PACKED native-size arrays
// (codegen: float32[] → MS_ARRAY(float), uint16[] → MS_ARRAY(uint16) — types.ms:152-156),
// so the array's own backing store is the exact byte layout sokol wants — no repack.

export const cubeVertices: Vec<float32> = [
	-0.5, -0.5,  0.5, 0.0, 1.0,   0.5, -0.5,  0.5, 1.0, 1.0,   0.5,  0.5,  0.5, 1.0, 0.0,  -0.5,  0.5,  0.5, 0.0, 0.0,
	 0.5, -0.5, -0.5, 0.0, 1.0,  -0.5, -0.5, -0.5, 1.0, 1.0,  -0.5,  0.5, -0.5, 1.0, 0.0,   0.5,  0.5, -0.5, 0.0, 0.0,
	-0.5,  0.5,  0.5, 0.0, 1.0,   0.5,  0.5,  0.5, 1.0, 1.0,   0.5,  0.5, -0.5, 1.0, 0.0,  -0.5,  0.5, -0.5, 0.0, 0.0,
	-0.5, -0.5, -0.5, 0.0, 1.0,   0.5, -0.5, -0.5, 1.0, 1.0,   0.5, -0.5,  0.5, 1.0, 0.0,  -0.5, -0.5,  0.5, 0.0, 0.0,
	 0.5, -0.5,  0.5, 0.0, 1.0,   0.5, -0.5, -0.5, 1.0, 1.0,   0.5,  0.5, -0.5, 1.0, 0.0,   0.5,  0.5,  0.5, 0.0, 0.0,
	-0.5, -0.5, -0.5, 0.0, 1.0,  -0.5, -0.5,  0.5, 1.0, 1.0,  -0.5,  0.5,  0.5, 1.0, 0.0,  -0.5,  0.5, -0.5, 0.0, 0.0,
];

export const cubeIndices: Vec<uint16> = [
	 0,  1,  2,  0,  2,  3,    4,  5,  6,  4,  6,  7,    8,  9, 10,  8, 10, 11,
	12, 13, 14, 12, 14, 15,   16, 17, 18, 16, 18, 19,   20, 21, 22, 20, 22, 23,
];

export const cubeVertexBytes: int32 = 480;
export const cubeIndexBytes: int32 = 72;
export const cubeIndexCount: int32 = 36;
