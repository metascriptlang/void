// Void sokol bridge — iOS embed driver. Host-driven: no run-loop, no UIKit window.
// The React-Native VoidView owns the CAMetalLayer + CADisplayLink and calls
// voidEmbedInit() once, then voidEmbedFrame() per tick. This is also the single
// sokol_gfx implementation unit on iOS (Metal backend, NO sokol_app). Everything
// below voidEmbedFrame is identical to bridge.c / bridgeEmbed.m.

#define SOKOL_IMPL
#define SOKOL_METAL

#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#include <unistd.h>

#include "bridge.h"
#include "voidRelay.h"
#include "sokol_gfx.h"
#include "sokol_log.h"
#include "shader.glsl.h"

// --- Host-provided GPU context (no sokol_app / sglue) ---
static id<MTLDevice>       g_device;
static CAMetalLayer*       g_layer;
static id<CAMetalDrawable> g_drawable;
static int g_w = 0, g_h = 0;

// --- Lifecycle closures (driven by the host's CADisplayLink) ---
static msClosure s_init;
static msClosure s_frame;
static msClosure s_pump;   // MetaScript message pump — drains host→void into onMessage handlers

static void call0(msClosure c) {
	if (!c.fn) return;
	if (c.env) ((void (*)(void *))c.fn)(c.env);
	else ((void (*)(void))c.fn)();
}

// --- Embed entry points (replace voidRun) ---

void voidEmbedRegister(msClosure init, msClosure frame) {
	s_init = init;
	s_frame = frame;
}

void voidEmbedSetMessagePump(msClosure pump) {
	s_pump = pump;
}

// Drive the message pump once (called per-frame by voidEmbedFrame; exposed so a host —
// or a headless test — can pump without rendering).
void voidEmbedPumpMessages(void) {
	call0(s_pump);
}

void voidEmbedInit(const void *layer, int w, int h) {
	g_layer = (__bridge CAMetalLayer *)layer;
	g_device = g_layer.device;
	if (!g_device) {
		g_device = MTLCreateSystemDefaultDevice();
		g_layer.device = g_device;
	}
	g_w = w;
	g_h = h;

	// Void's asset loaders use relative paths ("assets/test.png", "assets/font.ttf").
	// Point the CWD at the app bundle for the init window (where images + fonts load),
	// then restore — so the host app's CWD is untouched outside this call.
	char prev[4096];
	const char *got = getcwd(prev, sizeof prev);
	const char *res = [[[NSBundle mainBundle] resourcePath] fileSystemRepresentation];
	if (res) chdir(res);
	call0(s_init);
	if (got) chdir(prev);
}

void voidEmbedResize(int w, int h) {
	g_w = w;
	g_h = h;
}

void voidEmbedFrame(void) {
	if (!g_layer) return;

	// Drive the MetaScript message pump: it drains host→void via voidRelayNext() and
	// dispatches to the game's voidOnMessage handlers (which may voidEmit() back).
	voidEmbedPumpMessages();

	g_drawable = [g_layer nextDrawable];
	if (!g_drawable) return;
	call0(s_frame);
	g_drawable = nil;
}

void voidGfxSetup(void) {
	sg_desc d = {0};
	d.environment.metal.device = (__bridge const void *)g_device;
	d.environment.defaults.color_format = SG_PIXELFORMAT_BGRA8;
	d.environment.defaults.depth_format = SG_PIXELFORMAT_NONE;
	d.environment.defaults.sample_count = 1;
	d.logger.func = slog_func;
	sg_setup(&d);
}

int voidFbWidth(void) { return g_w; }
int voidFbHeight(void) { return g_h; }
int voidKeyDown(int keycode) { (void)keycode; return 0; }

// --- Resource creation (identical to bridge.c) ---

uint32_t voidMakeVertexBuffer(const void *data, int size) {
	sg_buffer_desc d = {0};
	d.usage.vertex_buffer = true;
	d.data.ptr = data;
	d.data.size = (size_t)size;
	return sg_make_buffer(&d).id;
}

uint32_t voidMakeIndexBuffer(const void *data, int size) {
	sg_buffer_desc d = {0};
	d.usage.index_buffer = true;
	d.data.ptr = data;
	d.data.size = (size_t)size;
	return sg_make_buffer(&d).id;
}

uint32_t voidMakeCubeShader(void) {
	return sg_make_shader(cube_shader_desc(sg_query_backend())).id;
}

uint32_t voidMakePipeline(uint32_t shader) {
	sg_pipeline_desc d = {0};
	d.shader = (sg_shader){.id = shader};
	d.layout.attrs[ATTR_cube_pos].format = SG_VERTEXFORMAT_FLOAT3;
	d.layout.attrs[ATTR_cube_uv0].format = SG_VERTEXFORMAT_FLOAT2;
	d.index_type = SG_INDEXTYPE_UINT16;
	d.cull_mode = SG_CULLMODE_BACK;
	d.face_winding = SG_FACEWINDING_CCW;
	d.depth.compare = SG_COMPAREFUNC_LESS_EQUAL;
	d.depth.write_enabled = true;
	return sg_make_pipeline(&d).id;
}

uint32_t voidMakeImage(const void *rgba, int w, int h) {
	static const uint8_t white[4] = {255, 255, 255, 255};
	if (rgba == NULL || w <= 0 || h <= 0) { rgba = white; w = 1; h = 1; }
	sg_image_desc d = {0};
	d.width = w;
	d.height = h;
	d.pixel_format = SG_PIXELFORMAT_RGBA8;
	d.data.mip_levels[0].ptr = rgba;
	d.data.mip_levels[0].size = (size_t)(w * h * 4);
	return sg_make_image(&d).id;
}

uint32_t voidMakeView(uint32_t image) {
	sg_view_desc d = {0};
	d.texture.image = (sg_image){.id = image};
	return sg_make_view(&d).id;
}

uint32_t voidMakeSampler(void) {
	sg_sampler_desc d = {0};
	d.min_filter = SG_FILTER_LINEAR;
	d.mag_filter = SG_FILTER_LINEAR;
	d.wrap_u = SG_WRAP_REPEAT;
	d.wrap_v = SG_WRAP_REPEAT;
	return sg_make_sampler(&d).id;
}

// --- Frame sequence ---

void voidBeginPass(float r, float g, float b, float a) {
	sg_pass pass = {0};
	pass.action.colors[0].load_action = SG_LOADACTION_CLEAR;
	pass.action.colors[0].clear_value = (sg_color){r, g, b, a};
	pass.swapchain.width = g_w;
	pass.swapchain.height = g_h;
	pass.swapchain.sample_count = 1;
	pass.swapchain.color_format = SG_PIXELFORMAT_BGRA8;
	pass.swapchain.depth_format = SG_PIXELFORMAT_NONE;
	pass.swapchain.metal.current_drawable = (__bridge const void *)g_drawable;
	sg_begin_pass(&pass);
}

void voidApplyPipeline(uint32_t pipeline) {
	sg_apply_pipeline((sg_pipeline){.id = pipeline});
}

void voidApplyBindings(uint32_t vbuf, uint32_t ibuf, uint32_t view, uint32_t sampler) {
	sg_bindings b = {0};
	b.vertex_buffers[0] = (sg_buffer){.id = vbuf};
	b.index_buffer = (sg_buffer){.id = ibuf};
	b.views[VIEW_tex] = (sg_view){.id = view};
	b.samplers[SMP_smp] = (sg_sampler){.id = sampler};
	sg_apply_bindings(&b);
}

void voidApplyMvp(const float *mvp) {
	sg_range u = {.ptr = mvp, .size = sizeof(vs_params_t)};
	sg_apply_uniforms(UB_vs_params, &u);
}

void voidDraw(int count) { sg_draw(0, count, 1); }
void voidEndPass(void) { sg_end_pass(); }
void voidCommit(void) { sg_commit(); }
