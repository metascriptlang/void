#include "mikkTangents.h"
#include "../../deps/mikktspace/mikktspace.c"

typedef struct {
	const float *vertices;
	int32_t stride;
	const uint16_t *indices;
	const uint32_t *wideIndices;
	int64_t cornerCount;
	float *corners;
} MikkMesh;

static int vertexOf(const SMikkTSpaceContext *context, int face, int vert) {
	const MikkMesh *mesh = (const MikkMesh *)context->m_pUserData;
	int corner = face * 3 + vert;
	if (mesh->wideIndices) return (int)mesh->wideIndices[corner];
	return mesh->indices ? (int)mesh->indices[corner] : corner;
}

static int numFaces(const SMikkTSpaceContext *context) {
	return (int)(((const MikkMesh *)context->m_pUserData)->cornerCount / 3);
}

static int numVerticesOfFace(const SMikkTSpaceContext *context, const int face) {
	(void)context;
	(void)face;
	return 3;
}

static void readAt(const SMikkTSpaceContext *context, float out[], int face, int vert, int at,
	int count) {
	const MikkMesh *mesh = (const MikkMesh *)context->m_pUserData;
	const float *vertex = mesh->vertices + (int64_t)vertexOf(context, face, vert) * mesh->stride;
	for (int k = 0; k < count; k++) out[k] = vertex[at + k];
}

static void getPosition(const SMikkTSpaceContext *context, float out[], const int face, const int vert) {
	readAt(context, out, face, vert, 0, 3);
}

static void getNormal(const SMikkTSpaceContext *context, float out[], const int face, const int vert) {
	readAt(context, out, face, vert, 3, 3);
}

static void getTexCoord(const SMikkTSpaceContext *context, float out[], const int face, const int vert) {
	readAt(context, out, face, vert, 6, 2);
}

static void setTSpaceBasic(const SMikkTSpaceContext *context, const float tangent[], const float sign,
	const int face, const int vert) {
	MikkMesh *mesh = (MikkMesh *)context->m_pUserData;
	float *out = mesh->corners + ((int64_t)face * 3 + vert) * 4;
	out[0] = tangent[0];
	out[1] = tangent[1];
	out[2] = tangent[2];
	out[3] = -sign;
}

static int32_t generateTangents(const float *vertices, int64_t vertexFloats, int32_t stride,
	const uint16_t *indices, const uint32_t *wideIndices, int64_t indexCount,
	float *corners, int64_t cornerFloats) {
	if (stride < 8 || vertexFloats < 0 || vertexFloats % stride != 0 ||
		cornerFloats < 0 || indexCount < 0) return 0;
	int64_t cornerCount = cornerFloats / 4;
	int64_t vertexCount = vertexFloats / stride;
	int64_t available = indexCount > 0 ? indexCount : vertexCount;
	if (cornerCount > INT32_MAX || vertexCount > INT32_MAX || cornerCount % 3 != 0 ||
		cornerCount * 4 != cornerFloats || cornerCount > available) return 0;
	if (cornerCount == 0) return 1;
	if (!vertices || !corners || (indexCount > 0 && !indices && !wideIndices)) return 0;
	for (int64_t i = 0; i < cornerCount && indexCount > 0; i++) {
		uint32_t index = wideIndices ? wideIndices[i] : indices[i];
		if ((int64_t)index >= vertexCount) return 0;
	}
	MikkMesh mesh = {
		vertices, stride, indexCount > 0 ? indices : 0,
		indexCount > 0 ? wideIndices : 0, cornerCount, corners,
	};
	SMikkTSpaceInterface callbacks = { 0 };
	callbacks.m_getNumFaces = numFaces;
	callbacks.m_getNumVerticesOfFace = numVerticesOfFace;
	callbacks.m_getPosition = getPosition;
	callbacks.m_getNormal = getNormal;
	callbacks.m_getTexCoord = getTexCoord;
	callbacks.m_setTSpaceBasic = setTSpaceBasic;
	SMikkTSpaceContext context = { &callbacks, &mesh };
	return genTangSpaceDefault(&context) ? 1 : 0;
}

int32_t void3dMikkTangents(const float *vertices, int64_t vertexFloats, int32_t stride,
	const uint16_t *indices, int64_t indexCount, float *corners, int64_t cornerFloats) {
	return generateTangents(vertices, vertexFloats, stride, indices, 0,
		indexCount, corners, cornerFloats);
}

int32_t void3dMikkTangents32(const float *vertices, int64_t vertexFloats, int32_t stride,
	const uint32_t *indices, int64_t indexCount, float *corners, int64_t cornerFloats) {
	return generateTangents(vertices, vertexFloats, stride, 0, indices,
		indexCount, corners, cornerFloats);
}
