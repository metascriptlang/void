#include "gpuRegistrationFixture.h"
#include "../../src/sokol/backend.h"
#include "../../src/gpu/door.h"
#include "gpuCopy.glsl.h"
#include <stdlib.h>

static int32_t program = -1;
static int32_t layout = -1;
static sg_buffer vertices;

int32_t fixtureProgram(void) {
	if (program >= 0) return program;
	sg_vertex_layout_state layouts[4] = {0};
	for (int i = 0; i < 4; i++) {
		layouts[i].attrs[ATTR_gpuCopy_position].format = SG_VERTEXFORMAT_FLOAT2;
	}
	layout = doorRegisterLayouts(layouts, 4) + 3;
	door_shader_fn shaders[6];
	int32_t programLayouts[6];
	for (int i = 0; i < 6; i++) {
		shaders[i] = gpuCopy_shader_desc;
		programLayouts[i] = layout;
	}
	program = doorRegisterPrograms(shaders, programLayouts, 6) + 5;
	return program;
}

int32_t fixturePreload(void) {
	const char *order = getenv("VOID_GPU_REGISTRATION");
	return order && atoi(order) == 2 ? fixtureProgram() : -1;
}

int32_t fixtureLayout(void) {
	fixtureProgram();
	return layout;
}

void fixtureDraw(uint32_t pipeline, uint32_t texture, uint32_t sampler) {
	if (vertices.id == 0) {
		static const float triangle[] = {-1.0f, -1.0f, 3.0f, -1.0f, -1.0f, 3.0f};
		vertices = sg_make_buffer(&(sg_buffer_desc){
			.usage.vertex_buffer = true,
			.data = {.ptr = triangle, .size = sizeof(triangle)},
		});
	}
	sg_apply_pipeline((sg_pipeline){.id = pipeline});
	sg_apply_bindings(&(sg_bindings){
		.vertex_buffers[0] = vertices,
		.views[0] = {.id = texture},
		.samplers[0] = {.id = sampler},
	});
	sg_draw(0, 3, 1);
}

int32_t fixtureInvalidLayoutCount(int32_t count) {
	sg_vertex_layout_state value = {0};
	doorRegisterLayouts(&value, 1);
	return doorRegisterLayouts(&value, count);
}

int32_t fixtureInvalidProgramCount(int32_t count) {
	sg_vertex_layout_state value = {0};
	int32_t id = doorRegisterLayouts(&value, 1);
	door_shader_fn shader = gpuCopy_shader_desc;
	doorRegisterPrograms(&shader, &id, 1);
	return doorRegisterPrograms(&shader, &id, count);
}
