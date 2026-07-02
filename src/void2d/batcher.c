// Void 2D — thin sokol/fontstash primitives (see batcher.h). Batcher logic is in draw.ms.

#include "batcher.h"
#include "../sokol/bridge.h"
#include "../../deps/sokol/sokol_gfx.h"
#include "shader2d.glsl.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#define FONTSTASH_IMPLEMENTATION
#include "../../deps/fontstash/fontstash.h"

#define VOID2D_MAX_VERTS 32768

#define VOID2D_BLEND_COUNT 5

static sg_buffer s_vbuf;
static sg_pipeline s_pips[VOID2D_BLEND_COUNT];
static sg_view s_whiteView;
static sg_sampler s_smp[2];   // [0] = nearest (smooth off), [1] = linear (smooth on)

static FONScontext *s_fons;
static int s_fontId = FONS_INVALID;
static FONStextIter s_iter;
static sg_image s_fontImg;
static sg_view s_fontView;
static unsigned char *s_atlasRGBA;
static int s_atlasW, s_atlasH;
static bool s_atlasDirty;
static bool s_atlasUpdated;   // gate: sokol allows only one sg_update_image per image per frame

static int fons_create(void *up, int w, int h) {
	(void)up;
	s_atlasW = w;
	s_atlasH = h;
	s_atlasRGBA = (unsigned char *)malloc((size_t)(w * h * 4));
	memset(s_atlasRGBA, 0, (size_t)(w * h * 4));
	sg_image_desc d = {0};
	d.width = w;
	d.height = h;
	d.pixel_format = SG_PIXELFORMAT_RGBA8;
	d.usage.stream_update = true;
	s_fontImg = sg_make_image(&d);
	s_fontView = (sg_view){ .id = voidMakeView(s_fontImg.id) };
	return 1;
}
static int fons_resize(void *up, int w, int h) {
	if (s_atlasRGBA) free(s_atlasRGBA);
	return fons_create(up, w, h);
}
static void fons_delete(void *up) { (void)up; if (s_atlasRGBA) { free(s_atlasRGBA); s_atlasRGBA = NULL; } }

static unsigned char *readFile(const char *path, int *outSize) {
	FILE *f = fopen(path, "rb");
	if (!f) return NULL;
	fseek(f, 0, SEEK_END);
	long n = ftell(f);
	fseek(f, 0, SEEK_SET);
	unsigned char *buf = (unsigned char *)malloc((size_t)n);
	if (fread(buf, 1, (size_t)n, f) != (size_t)n) { fclose(f); free(buf); return NULL; }
	fclose(f);
	*outSize = (int)n;
	return buf;
}

void void2dSetup(void) {
	sg_buffer_desc bd = {0};
	bd.usage.vertex_buffer = true;
	bd.usage.stream_update = true;
	bd.size = (size_t)(VOID2D_MAX_VERTS * 8) * sizeof(float);
	s_vbuf = sg_make_buffer(&bd);

	sg_shader shd = sg_make_shader(void2d_shader_desc(sg_query_backend()));
	struct { bool on; sg_blend_factor srgb, drgb, sa, da; } modes[VOID2D_BLEND_COUNT] = {
		{ true,  SG_BLENDFACTOR_SRC_ALPHA, SG_BLENDFACTOR_ONE_MINUS_SRC_ALPHA, SG_BLENDFACTOR_ONE,       SG_BLENDFACTOR_ONE_MINUS_SRC_ALPHA }, // 0 Alpha
		{ true,  SG_BLENDFACTOR_SRC_ALPHA, SG_BLENDFACTOR_ONE,                 SG_BLENDFACTOR_ONE,       SG_BLENDFACTOR_ONE                 }, // 1 Add
		{ true,  SG_BLENDFACTOR_DST_COLOR, SG_BLENDFACTOR_ONE_MINUS_SRC_ALPHA, SG_BLENDFACTOR_DST_ALPHA, SG_BLENDFACTOR_ONE_MINUS_SRC_ALPHA }, // 2 Multiply
		{ true,  SG_BLENDFACTOR_ONE,       SG_BLENDFACTOR_ONE_MINUS_SRC_COLOR, SG_BLENDFACTOR_ONE,       SG_BLENDFACTOR_ONE_MINUS_SRC_ALPHA }, // 3 Screen
		{ false, SG_BLENDFACTOR_ONE,       SG_BLENDFACTOR_ZERO,                SG_BLENDFACTOR_ONE,       SG_BLENDFACTOR_ZERO                }, // 4 None
	};
	for (int i = 0; i < VOID2D_BLEND_COUNT; i++) {
		sg_pipeline_desc pd = {0};
		pd.shader = shd;
		pd.layout.attrs[ATTR_void2d_pos].format = SG_VERTEXFORMAT_FLOAT2;
		pd.layout.attrs[ATTR_void2d_uv0].format = SG_VERTEXFORMAT_FLOAT2;
		pd.layout.attrs[ATTR_void2d_color0].format = SG_VERTEXFORMAT_FLOAT4;
		pd.colors[0].blend.enabled = modes[i].on;
		pd.colors[0].blend.src_factor_rgb = modes[i].srgb;
		pd.colors[0].blend.dst_factor_rgb = modes[i].drgb;
		pd.colors[0].blend.src_factor_alpha = modes[i].sa;
		pd.colors[0].blend.dst_factor_alpha = modes[i].da;
		s_pips[i] = sg_make_pipeline(&pd);
	}

	s_whiteView = (sg_view){ .id = voidMakeView(voidMakeImage(NULL, 0, 0)) };
	sg_sampler_desc smpLin = {0};
	smpLin.min_filter = SG_FILTER_LINEAR;
	smpLin.mag_filter = SG_FILTER_LINEAR;
	smpLin.wrap_u = SG_WRAP_REPEAT;
	smpLin.wrap_v = SG_WRAP_REPEAT;
	s_smp[1] = sg_make_sampler(&smpLin);
	sg_sampler_desc smpNear = {0};
	smpNear.min_filter = SG_FILTER_NEAREST;
	smpNear.mag_filter = SG_FILTER_NEAREST;
	smpNear.wrap_u = SG_WRAP_REPEAT;
	smpNear.wrap_v = SG_WRAP_REPEAT;
	s_smp[0] = sg_make_sampler(&smpNear);

	FONSparams fp = {0};
	fp.width = 512;
	fp.height = 512;
	fp.flags = (unsigned char)FONS_ZERO_TOPLEFT;
	fp.renderCreate = fons_create;
	fp.renderResize = fons_resize;
	fp.renderDelete = fons_delete;
	s_fons = fonsCreateInternal(&fp);
	if (s_fons) {
		int sz = 0;
		unsigned char *ttf = readFile("assets/font.ttf", &sz);
		if (ttf) s_fontId = fonsAddFontMem(s_fons, "sans", ttf, sz, 1);
	}
}

uint32_t void2dWhiteView(void) { return s_whiteView.id; }
uint32_t void2dFontView(void) { return s_fontView.id; }

void void2dScissor(int x, int y, int w, int h) {
	sg_apply_scissor_rect(x, y, w, h, true);
}

// Per-frame reset — re-arms the single sg_update_image allowed for the font atlas.
void void2dFrameBegin(void) { s_atlasUpdated = false; }

// Upload the font atlas once per frame (whichever draw — dynamic or static text — needs it first).
static void ensureAtlas(void) {
	if (s_atlasDirty && !s_atlasUpdated) {
		sg_image_data id = {0};
		id.mip_levels[0].ptr = s_atlasRGBA;
		id.mip_levels[0].size = (size_t)(s_atlasW * s_atlasH * 4);
		sg_update_image(s_fontImg, &id);
		s_atlasDirty = false;
		s_atlasUpdated = true;
	}
}

void void2dUploadDraw(const float *verts, int vertCount, uint32_t view, int blend, float fbW, float fbH,
                      const float *colorMatrix, float addR, float addG, float addB, float addA,
                      float keyR, float keyG, float keyB, float keyA, int smooth) {
	if (vertCount <= 0) return;
	if (blend < 0 || blend >= VOID2D_BLEND_COUNT) blend = 0;
	ensureAtlas();
	sg_range data = { .ptr = verts, .size = (size_t)(vertCount * 8) * sizeof(float) };
	int offset = sg_append_buffer(s_vbuf, &data);
	sg_apply_pipeline(s_pips[blend]);
	sg_bindings b = {0};
	b.vertex_buffers[0] = s_vbuf;
	b.vertex_buffer_offsets[0] = offset;
	b.views[VIEW_tex] = (sg_view){ .id = view };
	b.samplers[SMP_smp] = s_smp[(smooth != 0) ? 1 : 0];
	sg_apply_bindings(&b);
	void2d_params_t vp = {0};
	vp.viewport[0] = fbW;
	vp.viewport[1] = fbH;
	vp.model0[0] = 1.0f; vp.model0[3] = 1.0f;   // identity 2D affine (a=d=1, b=c=tx=ty=0)
	vp.globalColor[0] = 1.0f; vp.globalColor[1] = 1.0f; vp.globalColor[2] = 1.0f; vp.globalColor[3] = 1.0f;
	sg_range u = { .ptr = &vp, .size = sizeof(vp) };
	sg_apply_uniforms(UB_void2d_params, &u);
	void2d_fx_t fx = {0};
	memcpy(fx.colorMatrix, colorMatrix, sizeof(fx.colorMatrix));
	fx.colorAdd[0] = addR; fx.colorAdd[1] = addG; fx.colorAdd[2] = addB; fx.colorAdd[3] = addA;
	fx.colorKey[0] = keyR; fx.colorKey[1] = keyG; fx.colorKey[2] = keyB; fx.colorKey[3] = keyA;
	sg_range uf = { .ptr = &fx, .size = sizeof(fx) };
	sg_apply_uniforms(UB_void2d_fx, &uf);
	sg_draw(0, vertCount, 1);
}

// Persistent (immutable) vertex buffer holding LOCAL-space geometry — drawn via void2dDrawStatic
// with the object matrix in the shader, reused across frames until the mesh changes.
uint32_t void2dMakeStaticBuffer(const float *verts, int vertCount) {
	if (vertCount <= 0) return 0;
	sg_buffer_desc bd = {0};
	bd.usage.vertex_buffer = true;
	bd.data = (sg_range){ .ptr = verts, .size = (size_t)(vertCount * 8) * sizeof(float) };
	return sg_make_buffer(&bd).id;
}

void void2dDestroyStaticBuffer(uint32_t bufId) {
	if (bufId) sg_destroy_buffer((sg_buffer){ .id = bufId });
}

// One draw call from a static buffer: object matrix + alpha in the shader (model/globalColor),
// colour pipeline (colorMatrix/add/key) as for the dynamic path. Caller flushes first to keep z-order.
void void2dDrawStatic(uint32_t bufId, int vertCount, uint32_t view, int blend, float fbW, float fbH,
                      float mA, float mB, float mC, float mD, float mTx, float mTy,
                      float gcR, float gcG, float gcB, float gcA,
                      const float *colorMatrix, float addR, float addG, float addB, float addA,
                      float keyR, float keyG, float keyB, float keyA, int smooth) {
	if (vertCount <= 0 || bufId == 0) return;
	if (blend < 0 || blend >= VOID2D_BLEND_COUNT) blend = 0;
	ensureAtlas();
	sg_apply_pipeline(s_pips[blend]);
	sg_bindings b = {0};
	b.vertex_buffers[0] = (sg_buffer){ .id = bufId };
	b.views[VIEW_tex] = (sg_view){ .id = (view == 0 ? s_whiteView.id : view) };
	b.samplers[SMP_smp] = s_smp[(smooth != 0) ? 1 : 0];
	sg_apply_bindings(&b);
	void2d_params_t vp = {0};
	vp.viewport[0] = fbW; vp.viewport[1] = fbH;
	vp.model0[0]=mA; vp.model0[1]=mB; vp.model0[2]=mC; vp.model0[3]=mD;
	vp.model1[0]=mTx; vp.model1[1]=mTy;
	vp.globalColor[0]=gcR; vp.globalColor[1]=gcG; vp.globalColor[2]=gcB; vp.globalColor[3]=gcA;
	sg_range u = { .ptr=&vp, .size=sizeof(vp) };
	sg_apply_uniforms(UB_void2d_params, &u);
	void2d_fx_t fx = {0};
	memcpy(fx.colorMatrix, colorMatrix, sizeof(fx.colorMatrix));
	fx.colorAdd[0]=addR; fx.colorAdd[1]=addG; fx.colorAdd[2]=addB; fx.colorAdd[3]=addA;
	fx.colorKey[0]=keyR; fx.colorKey[1]=keyG; fx.colorKey[2]=keyB; fx.colorKey[3]=keyA;
	sg_range uf = { .ptr=&fx, .size=sizeof(fx) };
	sg_apply_uniforms(UB_void2d_fx, &uf);
	sg_draw(0, vertCount, 1);
}

void void2dTextBegin(float x, float y, float size, const char *text) {
	if (!s_fons || s_fontId == FONS_INVALID) return;
	fonsSetFont(s_fons, s_fontId);
	fonsSetSize(s_fons, size);
	fonsSetAlign(s_fons, FONS_ALIGN_LEFT | FONS_ALIGN_TOP);
	fonsTextIterInit(s_fons, &s_iter, x, y, text, NULL);
}

static float s_quad[8];
float *void2dTextNext(void) {
	if (!s_fons) return NULL;
	FONSquad q;
	if (!fonsTextIterNext(s_fons, &s_iter, &q)) return NULL;
	s_quad[0] = q.x0; s_quad[1] = q.y0; s_quad[2] = q.s0; s_quad[3] = q.t0;
	s_quad[4] = q.x1; s_quad[5] = q.y1; s_quad[6] = q.s1; s_quad[7] = q.t1;
	return s_quad;
}

float void2dTextWidth(float size, const char *text) {
	if (!s_fons || s_fontId == FONS_INVALID) return 0.0f;
	fonsSetFont(s_fons, s_fontId);
	fonsSetSize(s_fons, size);
	fonsSetAlign(s_fons, FONS_ALIGN_LEFT | FONS_ALIGN_TOP);
	return fonsTextBounds(s_fons, 0.0f, 0.0f, text, NULL, NULL);
}

float void2dLineHeight(float size) {
	if (!s_fons || s_fontId == FONS_INVALID) return size;
	fonsSetFont(s_fons, s_fontId);
	fonsSetSize(s_fons, size);
	float asc = 0.0f, desc = 0.0f, lineh = size;
	fonsVertMetrics(s_fons, &asc, &desc, &lineh);
	return lineh;
}

// persistent glyph-advance spacing; set per draw (0 = default) so it never leaks.
void void2dTextSpacing(float spacing) {
	if (s_fons) fonsSetSpacing(s_fons, spacing);
}

void void2dTextSyncAtlas(void) {
	if (!s_fons) return;
	int dirty[4];
	if (fonsValidateTexture(s_fons, dirty)) {
		int w = 0, h = 0;
		const unsigned char *tex = fonsGetTextureData(s_fons, &w, &h);
		int n = w * h;
		for (int i = 0; i < n; i++) {
			s_atlasRGBA[i * 4 + 0] = 255;
			s_atlasRGBA[i * 4 + 1] = 255;
			s_atlasRGBA[i * 4 + 2] = 255;
			s_atlasRGBA[i * 4 + 3] = tex[i];
		}
		s_atlasDirty = true;
	}
}
