#include "environmentBake.h"
#include "shaderBackends.h"
#include "../gpu/door.h"
#include "environment.glsl.h"

_Static_assert(sizeof(environmentParams_t) == ENVIRONMENT_PARAMS_FLOATS * sizeof(float),
	"environment.ms packs EnvironmentParams as ENVIRONMENT_PARAMS_FLOATS floats");
_Static_assert(UB_environmentParams == 0 && VIEW_panorama == 0 && VIEW_sourceCube == 0 &&
	SMP_environmentSampler == 0, "environment.ms binds every bake input at slot 0");
_Static_assert(ATTR_environmentPanorama_position == 0 && ATTR_environmentResample_position == 0 &&
	ATTR_environmentRadiance_position == 0 && ATTR_environmentIrradiance_position == 0,
	"the bake programs share one float2 layout");

static const door_shader_fn ENVIRONMENT_PROGRAMS[ENVIRONMENT_BAKE_PROGRAM_COUNT] = {
	environmentPanorama_shader_desc,
	environmentResample_shader_desc,
	environmentRadiance_shader_desc,
	environmentIrradiance_shader_desc,
};

static int32_t s_programBase = -1;
static int32_t s_layout = -1;

static void registerOnce(void) {
	if (s_programBase >= 0) { return; }
	sg_vertex_layout_state layout = {0};
	layout.attrs[0].format = SG_VERTEXFORMAT_FLOAT2;
	s_layout = doorRegisterLayouts(&layout, 1);
	int32_t layouts[ENVIRONMENT_BAKE_PROGRAM_COUNT];
	for (int32_t i = 0; i < ENVIRONMENT_BAKE_PROGRAM_COUNT; i++) { layouts[i] = s_layout; }
	s_programBase = doorRegisterPrograms(ENVIRONMENT_PROGRAMS, layouts, ENVIRONMENT_BAKE_PROGRAM_COUNT);
}

int32_t environmentBakeProgramBase(void) {
	registerOnce();
	return s_programBase;
}

int32_t environmentBakeLayout(void) {
	registerOnce();
	return s_layout;
}
