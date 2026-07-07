// Void sokol bridge — Android embed driver (GLES3 via EGL). Host-driven: no sokol_app.
// The host (RN Fabric SurfaceView, or the headless M2 driver) owns the surface + render
// loop and calls voidEmbedInit*/voidEmbedFrame. Single sokol_gfx implementation unit on
// Android (GLES3 backend). Everything below voidGfxSetup mirrors bridgeIos.m (Metal),
// swapping the GPU-context internals: EGL context + GLES3 default framebuffer.

#define SOKOL_IMPL
#define SOKOL_GLES3

#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <unistd.h>

#include "bridge.h"
#include "sokol_gfx.h"
#include "sokol_log.h"
#include "shader.glsl.h"

static EGLDisplay g_dpy  = EGL_NO_DISPLAY;
static EGLContext g_ctx  = EGL_NO_CONTEXT;
static EGLSurface g_surf = EGL_NO_SURFACE;
static EGLConfig  g_cfg;
static int g_w = 0, g_h = 0;

static msClosure s_init;
static msClosure s_frame;
static msClosure s_pump;

static void call0(msClosure c) {
	if (!c.fn) return;
	if (c.env) ((void (*)(void *))c.fn)(c.env);
	else ((void (*)(void))c.fn)();
}

void voidEmbedRegister(msClosure init, msClosure frame) {
	s_init = init;
	s_frame = frame;
}

void voidEmbedSetMessagePump(msClosure pump) { s_pump = pump; }
void voidEmbedPumpMessages(void) { call0(s_pump); }

// EGL display + config + ES3 context (surface created by the caller: window or pbuffer).
static int egl_boot(int want_pbuffer) {
	g_dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
	if (g_dpy == EGL_NO_DISPLAY) return 0;
	if (!eglInitialize(g_dpy, NULL, NULL)) return 0;
	EGLint cfgAttr[] = {
		EGL_SURFACE_TYPE, want_pbuffer ? EGL_PBUFFER_BIT : EGL_WINDOW_BIT,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
		EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
		EGL_DEPTH_SIZE, 0, EGL_NONE
	};
	EGLint n = 0;
	if (!eglChooseConfig(g_dpy, cfgAttr, &g_cfg, 1, &n) || n < 1) return 0;
	eglBindAPI(EGL_OPENGL_ES_API);
	EGLint ctxAttr[] = { EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE };
	g_ctx = eglCreateContext(g_dpy, g_cfg, EGL_NO_CONTEXT, ctxAttr);
	return g_ctx != EGL_NO_CONTEXT;
}

// Headless offscreen render (M2 proof / tests) — no ANativeWindow needed.
void voidEmbedInitHeadless(int w, int h) {
	g_w = w; g_h = h;
	if (!egl_boot(1)) return;
	EGLint pb[] = { EGL_WIDTH, w, EGL_HEIGHT, h, EGL_NONE };
	g_surf = eglCreatePbufferSurface(g_dpy, g_cfg, pb);
	eglMakeCurrent(g_dpy, g_surf, g_surf, g_ctx);
	call0(s_init);
}

// Asset loaders use relative paths ("assets/test.png"); the host extracts APK assets to a
// real dir and tells us its root, so init2d's loads resolve (scoped chdir, like iOS bundles).
static char g_assetRoot[1024] = {0};

void voidEmbedSetAssetRoot(const char *p) {
	size_t n = 0;
	while (p[n] && n < sizeof(g_assetRoot) - 1) { g_assetRoot[n] = p[n]; n++; }
	g_assetRoot[n] = 0;
}

// Window-surface path (RN Fabric SurfaceView hands us an ANativeWindow*). Idempotent:
// Android fires surfaceCreated/Changed repeatedly (and on rotation) — the GL context +
// scene persist across calls; only the window surface is rebound.
static int g_scene_inited = 0;

void voidEmbedInit(const void *window, int w, int h) {
	g_w = w; g_h = h;
	if (g_ctx == EGL_NO_CONTEXT && !egl_boot(0)) return;
	if (g_surf != EGL_NO_SURFACE) {
		eglMakeCurrent(g_dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
		eglDestroySurface(g_dpy, g_surf);
		g_surf = EGL_NO_SURFACE;
	}
	g_surf = eglCreateWindowSurface(g_dpy, g_cfg, (EGLNativeWindowType)(uintptr_t)window, NULL);
	eglMakeCurrent(g_dpy, g_surf, g_surf, g_ctx);
	if (!g_scene_inited) {
		char prev[1024];
		const char *got = getcwd(prev, sizeof prev);
		if (g_assetRoot[0]) chdir(g_assetRoot);
		call0(s_init);
		if (got) chdir(prev);
		g_scene_inited = 1;
	}
}

void voidEmbedResize(int w, int h) { g_w = w; g_h = h; }

static void render_once(void) {
	voidEmbedPumpMessages();
	call0(s_frame);
}

void voidEmbedFrame(void) {
	if (g_ctx == EGL_NO_CONTEXT) return;
	render_once();
	eglSwapBuffers(g_dpy, g_surf);
}

// Headless render with no present — pbuffer content stays readable by voidAndroidReadPixels.
void voidEmbedRenderNoSwap(void) {
	if (g_ctx == EGL_NO_CONTEXT) return;
	render_once();
}

// Release the context from the calling thread (render thread teardown) so a future render
// thread can make it current again.
void voidEmbedDetach(void) {
	if (g_dpy != EGL_NO_DISPLAY) {
		eglMakeCurrent(g_dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
	}
}

void voidGfxSetup(void) {
	sg_desc d = {0};
	d.environment.defaults.color_format = SG_PIXELFORMAT_RGBA8;
	d.environment.defaults.depth_format = SG_PIXELFORMAT_NONE;
	d.environment.defaults.sample_count = 1;
	d.logger.func = slog_func;
	sg_setup(&d);
}

int voidFbWidth(void) { return g_w; }
int voidFbHeight(void) { return g_h; }
float voidDpiScale(void) { return 1.0f; }
int voidKeyDown(int keycode) { (void)keycode; return 0; }

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

void voidBeginPass(float r, float g, float b, float a) {
	sg_pass pass = {0};
	pass.action.colors[0].load_action = SG_LOADACTION_CLEAR;
	pass.action.colors[0].clear_value = (sg_color){r, g, b, a};
	pass.swapchain.width = g_w;
	pass.swapchain.height = g_h;
	pass.swapchain.sample_count = 1;
	pass.swapchain.color_format = SG_PIXELFORMAT_RGBA8;
	pass.swapchain.depth_format = SG_PIXELFORMAT_NONE;
	pass.swapchain.gl.framebuffer = 0;
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

// M2 readback — pull the rendered pbuffer (RGBA8, bottom-up GL order).
void voidAndroidReadPixels(unsigned char *out) {
	glReadPixels(0, 0, g_w, g_h, GL_RGBA, GL_UNSIGNED_BYTE, out);
}
