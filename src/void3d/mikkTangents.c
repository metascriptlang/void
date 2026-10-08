#include "mikkTangents.h"
#include "../../deps/mikktspace/mikktspace.c"

typedef struct {
	const float *vertices;
	int32_t stride;
	const uint16_t *indices;
	int64_t cornerCount;
	float *corners;
} MikkMesh;

static int vertexOf(const SMikkTSpaceContext *context, int face, int vert) {
	const MikkMesh *mesh = (const MikkMesh *)context->m_pUserData;
	int corner = face * 3 + vert;
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

int32_t void3dMikkTangents(const float *vertices, int64_t vertexFloats, int32_t stride,
	const uint16_t *indices, int64_t indexCount, float *corners, int64_t cornerFloats) {
	int64_t cornerCount = cornerFloats / 4;
	int64_t available = indexCount > 0 ? indexCount : vertexFloats / stride;
	if (cornerCount % 3 != 0 || cornerCount * 4 != cornerFloats || cornerCount > available) return 0;
	if (cornerCount == 0) return 1;
	MikkMesh mesh = { vertices, stride, indexCount > 0 ? indices : 0, cornerCount, corners };
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
