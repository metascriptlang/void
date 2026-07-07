// Void sokol bridge — thin C wrappers (impl lives in the @link'd sokol unit).

#include "bridge.h"
#include "sokol_gfx.h"
#include "sokol_app.h"
#include "sokol_glue.h"
#include "sokol_log.h"
#include "shader.glsl.h"

// --- Lifecycle ---

static msClosure s_init;
static msClosure s_frame;

static void call0(msClosure c) {
	if (!c.fn) return;
	if (c.env) ((void (*)(void *))c.fn)(c.env);
	else ((void (*)(void))c.fn)();
}

static void _init(void) { call0(s_init); }
static void _frame(void) { call0(s_frame); }

static bool s_keys[SAPP_MAX_KEYCODES];

static void _event(const sapp_event *e) {
	if (e->type == SAPP_EVENTTYPE_KEY_DOWN) {
		if (e->key_code == SAPP_KEYCODE_ESCAPE) sapp_request_quit();
		s_keys[e->key_code] = true;
	} else if (e->type == SAPP_EVENTTYPE_KEY_UP) {
		s_keys[e->key_code] = false;
	}
}

static void _cleanup(void) { sg_shutdown(); }

void voidRun(int w, int h, msClosure init, msClosure frame) {
	s_init = init;
	s_frame = frame;
	sapp_desc d = {0};
	d.init_cb = _init;
	d.frame_cb = _frame;
	d.event_cb = _event;
	d.cleanup_cb = _cleanup;
	d.width = w;
	d.height = h;
	d.sample_count = 4;
	d.high_dpi = true;
	d.window_title = "Void — sokol";
	d.logger.func = slog_func;
	sapp_run(&d);
}

void voidGfxSetup(void) {
	sg_desc d = {0};
	d.environment = sglue_environment();
	d.logger.func = slog_func;
	sg_setup(&d);
}

int voidFbWidth(void) { return sapp_width(); }
int voidFbHeight(void) { return sapp_height(); }
float voidDpiScale(void) { return sapp_dpi_scale(); }

int voidKeyDown(int keycode) {
	if (keycode < 0 || keycode >= SAPP_MAX_KEYCODES) return 0;
	return s_keys[keycode] ? 1 : 0;
}

// --- Resource creation (sokol handle .id ↔ uint32) ---

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

// --- Offscreen render targets ---

#define VOID_MAX_RT 16
typedef struct { sg_image img; sg_view attView; sg_view texView; int used; } VoidRT;
static VoidRT s_rts[VOID_MAX_RT];

uint32_t voidMakeRenderTarget(int w, int h) {
	if (w <= 0 || h <= 0) return 0;
	int slot = -1;
	for (int i = 0; i < VOID_MAX_RT; i++) { if (!s_rts[i].used) { slot = i; break; } }
	if (slot < 0) return 0;
	sg_image_desc id = {0};
	id.usage.color_attachment = true;
	id.width = w;
	id.height = h;
	id.pixel_format = SG_PIXELFORMAT_RGBA8;
	id.sample_count = 1;
	sg_image img = sg_make_image(&id);
	sg_view_desc avd = {0};
	avd.color_attachment.image = img;
	sg_view_desc tvd = {0};
	tvd.texture.image = img;
	s_rts[slot].img = img;
	s_rts[slot].attView = sg_make_view(&avd);
	s_rts[slot].texView = sg_make_view(&tvd);
	s_rts[slot].used = 1;
	return (uint32_t)(slot + 1);
}

uint32_t voidRenderTargetView(uint32_t rt) {
	if (rt == 0 || rt > VOID_MAX_RT || !s_rts[rt - 1].used) return 0;
	return s_rts[rt - 1].texView.id;
}

void voidBeginRenderTargetPass(uint32_t rt, float r, float g, float b, float a) {
	if (rt == 0 || rt > VOID_MAX_RT || !s_rts[rt - 1].used) return;
	sg_pass pass = {0};
	pass.action.colors[0].load_action = SG_LOADACTION_CLEAR;
	pass.action.colors[0].clear_value = (sg_color){r, g, b, a};
	pass.attachments.colors[0] = s_rts[rt - 1].attView;
	sg_begin_pass(&pass);
}

void voidDestroyRenderTarget(uint32_t rt) {
	if (rt == 0 || rt > VOID_MAX_RT || !s_rts[rt - 1].used) return;
	VoidRT *p = &s_rts[rt - 1];
	sg_destroy_view(p->texView);
	sg_destroy_view(p->attView);
	sg_destroy_image(p->img);
	p->used = 0;
}

int voidIsRenderTargetView(uint32_t view) {
	if (view == 0) return 0;
	for (int i = 0; i < VOID_MAX_RT; i++) {
		if (s_rts[i].used && s_rts[i].texView.id == view) return 1;
	}
	return 0;
}

// --- Frame sequence ---

void voidBeginPass(float r, float g, float b, float a) {
	sg_pass pass = {0};
	pass.action.colors[0].load_action = SG_LOADACTION_CLEAR;
	pass.action.colors[0].clear_value = (sg_color){r, g, b, a};
	pass.action.depth.load_action = SG_LOADACTION_CLEAR;
	pass.action.depth.clear_value = 1.0f;
	pass.swapchain = sglue_swapchain();
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
