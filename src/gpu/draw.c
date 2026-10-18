#include "draw.h"
#include "../../deps/sokol/sokol_gfx.h"

#include <stdio.h>
#include <stdlib.h>

static size_t sizeOf(int64_t length, size_t element) {
	if (length <= 0 || length > INT32_MAX || (uint64_t)length > SIZE_MAX / element) return 0;
	return (size_t)length * element;
}

static uint32_t madeBuffer(const void *data, size_t size, int index, int dynamic) {
	if (size == 0) return SG_INVALID_ID;
	sg_buffer_desc desc = {0};
	desc.usage.vertex_buffer = !index;
	desc.usage.index_buffer = index;
	desc.usage.dynamic_update = dynamic;
	if (data == NULL) {
		desc.size = size;
	} else {
		desc.data.ptr = data;
		desc.data.size = size;
	}
	return sg_make_buffer(&desc).id;
}

uint32_t drawMakeVertexBuffer(const float *data, int64_t length) {
	if (data == NULL) return SG_INVALID_ID;
	return madeBuffer(data, sizeOf(length, sizeof(float)), 0, 0);
}

uint32_t drawMakeIndexBuffer(const uint16_t *data, int64_t length) {
	if (data == NULL) return SG_INVALID_ID;
	return madeBuffer(data, sizeOf(length, sizeof(uint16_t)), 1, 0);
}

uint32_t drawMakeIndexBuffer32(const uint32_t *data, int64_t length) {
	if (data == NULL) return SG_INVALID_ID;
	return madeBuffer(data, sizeOf(length, sizeof(uint32_t)), 1, 0);
}

uint32_t drawMakeStreamBuffer(int64_t length) {
	return madeBuffer(NULL, sizeOf(length, sizeof(float)), 0, 1);
}

int32_t drawUpdateBuffer(uint32_t buffer, const float *data, int64_t length) {
	sg_buffer handle = {.id = buffer};
	const size_t size = sizeOf(length, sizeof(float));
	if (data == NULL || size == 0) return 0;
	if (sg_query_buffer_state(handle) != SG_RESOURCESTATE_VALID) return 0;
	if (size > sg_query_buffer_size(handle)) return 0;
	sg_update_buffer(handle, &(sg_range){.ptr = data, .size = size});
	return 1;
}

void drawDestroyBuffer(uint32_t buffer) { sg_destroy_buffer((sg_buffer){.id = buffer}); }

void drawApplyPipeline(uint32_t pipeline) {
	sg_apply_pipeline((sg_pipeline){.id = pipeline});
}

void drawApplyBindings(const uint32_t *bindings, int64_t length) {
	if (length < DRAW_BINDING_LENGTH) {
		fprintf(stderr, "gpu draw: applyBindings descriptor holds %lld of %d words\n",
			(long long)length, DRAW_BINDING_LENGTH);
		abort();
	}
	sg_bindings desc = {0};
	for (int i = 0; i < DRAW_BINDING_VERTEX_BUFFERS; i++) {
		desc.vertex_buffers[i] = (sg_buffer){.id = bindings[DRAW_BINDING_VERTEX_BUFFER + i]};
	}
	desc.index_buffer = (sg_buffer){.id = bindings[DRAW_BINDING_INDEX_BUFFER]};
	for (int i = 0; i < DRAW_BINDING_VIEWS; i++) {
		desc.views[i] = (sg_view){.id = bindings[DRAW_BINDING_VIEW + i]};
	}
	for (int i = 0; i < DRAW_BINDING_SAMPLERS; i++) {
		desc.samplers[i] = (sg_sampler){.id = bindings[DRAW_BINDING_SAMPLER + i]};
	}
	sg_apply_bindings(&desc);
}

void drawApplyUniforms(int32_t slot, const float *data, int64_t length) {
	sg_apply_uniforms(slot, &(sg_range){.ptr = data, .size = (size_t)length * sizeof(float)});
}

void drawElements(int32_t base, int32_t count, int32_t instances) {
	sg_draw(base, count, instances);
}
