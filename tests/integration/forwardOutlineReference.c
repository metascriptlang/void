#include "forwardOutlineReference.h"
#include "../../src/void3d/shaderBackends.h"
#include "../../src/gpu/door.h"
#include "forwardOutlineReference.glsl.h"

static int32_t referenceProgram = -1;
static int32_t referenceLayout = -1;
static sg_buffer referenceVertices;

int32_t outlineReferenceProgram(void) {
    if (referenceProgram >= 0) return referenceProgram;
    sg_vertex_layout_state layout = {0};
    layout.attrs[ATTR_outlineReference_position].format = SG_VERTEXFORMAT_FLOAT2;
    referenceLayout = doorRegisterLayouts(&layout, 1);
    door_shader_fn shader = outlineReference_shader_desc;
    referenceProgram = doorRegisterPrograms(&shader, &referenceLayout, 1);
    return referenceProgram;
}

int32_t outlineReferenceLayout(void) {
    outlineReferenceProgram();
    return referenceLayout;
}

void outlineReferenceDraw(uint32_t pipeline, uint32_t view, uint32_t sampler,
    float sizeX, float sizeY, float complement) {
    if (referenceVertices.id == 0) {
        static const float triangle[] = {-1.0f, -1.0f, 3.0f, -1.0f, -1.0f, 3.0f};
        referenceVertices = sg_make_buffer(&(sg_buffer_desc){
            .usage.vertex_buffer = true,
            .data = {.ptr = triangle, .size = sizeof(triangle)},
        });
    }
    sg_apply_pipeline((sg_pipeline){.id = pipeline});
    sg_apply_bindings(&(sg_bindings){
        .vertex_buffers[0] = referenceVertices,
        .views[0] = {.id = view},
        .samplers[0] = {.id = sampler},
    });
    const referenceParameters_t parameters = {
        .referenceSize = {sizeX, sizeY, complement, 0.0f},
    };
    sg_apply_uniforms(UB_referenceParameters,
        &(sg_range){.ptr = &parameters, .size = sizeof(parameters)});
    sg_draw(0, 3, 1);
}

void outlineReferenceClose(void) {
    if (referenceVertices.id != 0) sg_destroy_buffer(referenceVertices);
    referenceVertices.id = 0;
}
