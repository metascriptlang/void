// Void 2D — thin sokol/fontstash primitives (see batcher.h). Batcher logic is in draw.ms.

#include "batcher.h"
#include "../sokol/bridge.h"
#include "../../deps/sokol/sokol_gfx.h"
#include "shader2d.glsl.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>   // fontstash's _WIN32 fopen path uses MAX_PATH / MultiByteToWideChar
#endif
#define FONTSTASH_IMPLEMENTATION
#include "../../deps/fontstash/fontstash.h"

#define VOID2D_BLEND_COUNT 5

// One growing vertex buffer for the whole frame, replacing both the fixed 65 536-vertex
// stream and the per-node static buffers (VOID2D.md "Known defects", closed here). Growth is
// max(2x, next power of two) with no shrink, a hard cap, and a dropped frame with an error
// past it (GPUI.md:63) — never a silent truncation, which is what the old
// `sg_append_buffer` overflow was.
#define VOID2D_INITIAL_BUFFER_BYTES (1 << 20)
#define VOID2D_MAX_BUFFER_BYTES     (192 << 20)

static sg_buffer s_vbuf;
static int s_vbufBytes;
static int s_frameBaseOffset;   // where this frame's vertices start in s_vbuf
static int s_frameUploaded;     // 0 when the frame was dropped, and then nothing may draw
static sg_pipeline s_pips[VOID2D_BLEND_COUNT];
static sg_pipeline s_pipsRT[VOID2D_BLEND_COUNT];   // offscreen variant: single-sample RGBA8, no depth
static float s_dpiScale = 1.0f;                    // framebuffer / logical pixel ratio (retina = 2.0)
static sg_pipeline s_blurPip;                      // separable-blur fullscreen pass (offscreen format)
static sg_buffer s_fsQuad;                         // fullscreen quad (pos2+uv2) for filter passes
static sg_view s_whiteView;
// Indexed by `smooth * 2 + tileWrap`, the packing displayList.ms `samplerIndex` writes into
// CMD_SAMPLER. Clamp is the default: a tile is a sub-rect of an atlas, so REPEAT on a tile
// that does not fill its page wraps in a neighbour's pixels at the seam.
#define SMP_COUNT 4
static sg_sampler s_smp[SMP_COUNT];

static FONScontext *s_fons;
static int s_fontId = FONS_INVALID;
static int s_fontIds[16];
static int s_fontCount = 0;
static FONStextIter s_iter;
static sg_image s_fontImg;
static sg_view s_fontView;
static unsigned char *s_atlasRGBA;
static int s_atlasW, s_atlasH;
static bool s_atlasDirty;
static bool s_atlasUpdated;   // gate: sokol allows only one sg_update_image per image per frame
static int s_atlasGen = 0;    // bumped on atlas resize → invalidates cached glyph meshes

// Mirrors src/void2d/displayList.ms. void2dLayoutCheck is what keeps the two honest; it is
// called from MetaScript with that file's own constants, so a field added on one side and
// not the other fails at setup rather than drawing garbage.
#define CMD_FLOATS          24
#define CMD_KIND            0
#define CMD_BREAK           1
#define CMD_VERTEX_OFFSET   2
#define CMD_VERTEX_COUNT    3
#define CMD_VIEW            4
#define CMD_BLEND           5
#define CMD_SAMPLER         6
#define CMD_EFFECT          7
#define CMD_CLIP_X          8
#define CMD_CLIP_Y          9
#define CMD_CLIP_W          10
#define CMD_CLIP_H          11
#define CMD_ARG0            12
#define CMD_ARG1            13
#define CMD_RT_MODE         14
#define CMD_CLEAR_R         15

#define EFFECT_FLOATS       24
#define VERTEX_FLOATS       8

#define CMD_KIND_DRAW       0
#define CMD_KIND_SCISSOR    1
#define CMD_KIND_BLUR       2
#define CMD_KIND_TGT_BEGIN  3
#define CMD_KIND_TGT_END    4
#define VOID2D_MAX_TARGET_DEPTH 8

static const float s_identityMatrix[16] = {
	1.0f, 0.0f, 0.0f, 0.0f,
	0.0f, 1.0f, 0.0f, 0.0f,
	0.0f, 0.0f, 1.0f, 0.0f,
	0.0f, 0.0f, 0.0f, 1.0f,
};

static int s_drawCallCount;
static int s_uploadCount;
static int s_uploadBytes;
static int s_droppedFrames;

int void2dDrawCallCount(void) { return s_drawCallCount; }
int void2dUploadCount(void) { return s_uploadCount; }
int void2dUploadBytes(void) { return s_uploadBytes; }
int void2dInstanceBufferBytes(void) { return s_vbufBytes; }
int void2dDroppedFrames(void) { return s_droppedFrames; }

// Every sg_buffer and sg_image this layer holds: the one vertex buffer, the fullscreen quad
// the filter passes draw, and the font atlas image. Constant in the node count, which is the
// whole point of the change (VOID2D.md P1 exit).
int void2dBuffersAlive(void) { return 3; }

int void2dLayoutCheck(int commandFloats, int effectFloats, int vertexFloats,
                      int kindField, int breakField, int vertexOffsetField, int vertexCountField,
                      int viewField, int blendField, int samplerField, int effectField,
                      int samplerCount, int maxTargetDepth, int clearRField,
                      int clipXField, int arg0Field, int rtModeField,
                      int kindDraw, int kindScissor, int kindBlur,
                      int kindTargetBegin, int kindTargetEnd) {
	return commandFloats == CMD_FLOATS
		&& effectFloats == EFFECT_FLOATS
		&& vertexFloats == VERTEX_FLOATS
		&& kindField == CMD_KIND
		&& breakField == CMD_BREAK
		&& vertexOffsetField == CMD_VERTEX_OFFSET
		&& vertexCountField == CMD_VERTEX_COUNT
		&& viewField == CMD_VIEW
		&& blendField == CMD_BLEND
		&& samplerField == CMD_SAMPLER
		&& samplerCount == SMP_COUNT
		&& effectField == CMD_EFFECT
		&& clipXField == CMD_CLIP_X
		&& arg0Field == CMD_ARG0
		&& rtModeField == CMD_RT_MODE
		&& kindDraw == CMD_KIND_DRAW
		&& kindScissor == CMD_KIND_SCISSOR
		&& kindBlur == CMD_KIND_BLUR
		&& kindTargetBegin == CMD_KIND_TGT_BEGIN
		&& kindTargetEnd == CMD_KIND_TGT_END
		&& maxTargetDepth == VOID2D_MAX_TARGET_DEPTH
		&& clearRField == CMD_CLEAR_R;
}

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
	// Persists across frames, re-uploaded only when fontstash adds glyphs. dynamic_update is
	// deprecated upstream in favour of write_persistent (sokol CHANGELOG, 30-Aug-2026).
	d.usage.dynamic_update = true;
	s_fontImg = sg_make_image(&d);
	s_fontView = (sg_view){ .id = voidMakeView(s_fontImg.id) };
	return 1;
}
static int fons_resize(void *up, int w, int h) {
	s_atlasGen++;
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

// Allocate, or reallocate, the one vertex buffer. sokol cannot resize a buffer, so growth is
// a destroy and a make; it happens when a frame first needs more room and then never again,
// because the buffer does not shrink.
static void ensureVertexBuffer(int bytes) {
	if (bytes <= s_vbufBytes) return;
	int want = s_vbufBytes > 0 ? s_vbufBytes * 2 : VOID2D_INITIAL_BUFFER_BYTES;
	while (want < bytes) want *= 2;
	if (s_vbuf.id) sg_destroy_buffer(s_vbuf);
	sg_buffer_desc bd = {0};
	bd.usage.vertex_buffer = true;
	bd.usage.dynamic_update = true;
	bd.size = (size_t)want;
	s_vbuf = sg_make_buffer(&bd);
	s_vbufBytes = want;
}

void void2dSetup(void) {
	ensureVertexBuffer(VOID2D_INITIAL_BUFFER_BYTES);

	sg_shader shd = sg_make_shader(void2d_shader_desc(sg_query_backend()));
	struct { bool on; sg_blend_factor srgb, drgb, sa, da; } modes[VOID2D_BLEND_COUNT] = {
		{ true,  SG_BLENDFACTOR_ONE,       SG_BLENDFACTOR_ONE_MINUS_SRC_ALPHA, SG_BLENDFACTOR_ONE,       SG_BLENDFACTOR_ONE_MINUS_SRC_ALPHA }, // 0 Alpha (premult)
		{ true,  SG_BLENDFACTOR_ONE,       SG_BLENDFACTOR_ONE,                 SG_BLENDFACTOR_ONE,       SG_BLENDFACTOR_ONE                 }, // 1 Add (premult)
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
		pd.colors[0].pixel_format = SG_PIXELFORMAT_RGBA8;
		pd.sample_count = 1;
		pd.depth.pixel_format = SG_PIXELFORMAT_NONE;
		s_pipsRT[i] = sg_make_pipeline(&pd);
	}

	sg_pipeline_desc bpd = {0};
	bpd.shader = sg_make_shader(blur_shader_desc(sg_query_backend()));
	bpd.layout.attrs[ATTR_blur_pos].format = SG_VERTEXFORMAT_FLOAT2;
	bpd.layout.attrs[ATTR_blur_uv0].format = SG_VERTEXFORMAT_FLOAT2;
	bpd.colors[0].pixel_format = SG_PIXELFORMAT_RGBA8;
	bpd.sample_count = 1;
	bpd.depth.pixel_format = SG_PIXELFORMAT_NONE;
	s_blurPip = sg_make_pipeline(&bpd);

	static const float fsq[24] = {
		-1.0f, -1.0f, 0.0f, 0.0f,   1.0f, -1.0f, 1.0f, 0.0f,   1.0f, 1.0f, 1.0f, 1.0f,
		-1.0f, -1.0f, 0.0f, 0.0f,   1.0f,  1.0f, 1.0f, 1.0f,  -1.0f, 1.0f, 0.0f, 1.0f,
	};
	sg_buffer_desc fqd = {0};
	fqd.usage.vertex_buffer = true;
	fqd.data = (sg_range){ .ptr = fsq, .size = sizeof(fsq) };
	s_fsQuad = sg_make_buffer(&fqd);

	s_whiteView = (sg_view){ .id = voidMakeView(voidMakeImage(NULL, 0, 0)) };
	// Four samplers, made once: smooth * 2 + tileWrap. They are four objects and not a
	// mutated one because sokol samplers are immutable, and four of a 128-slot pool is a
	// constant cost that does not grow with the scene.
	for (int i = 0; i < SMP_COUNT; i++) {
		int smooth = (i & 2) != 0;
		int wrap = (i & 1) != 0;
		sg_sampler_desc d = {0};
		d.min_filter = smooth ? SG_FILTER_LINEAR : SG_FILTER_NEAREST;
		d.mag_filter = smooth ? SG_FILTER_LINEAR : SG_FILTER_NEAREST;
		d.wrap_u = wrap ? SG_WRAP_REPEAT : SG_WRAP_CLAMP_TO_EDGE;
		d.wrap_v = wrap ? SG_WRAP_REPEAT : SG_WRAP_CLAMP_TO_EDGE;
		s_smp[i] = sg_make_sampler(&d);
	}

	FONSparams fp = {0};
	fp.width = 512;
	fp.height = 512;
	fp.flags = (unsigned char)FONS_ZERO_TOPLEFT;
	fp.renderCreate = fons_create;
	fp.renderResize = fons_resize;
	fp.renderDelete = fons_delete;
	s_fons = fonsCreateInternal(&fp);
	if (s_fons) {
		void2dAddFont("assets/font.ttf");
	}
}

int void2dAddFont(const char *path) {
	if (!s_fons || s_fontCount >= 16) return -1;
	int sz = 0;
	unsigned char *ttf = readFile(path, &sz);
	if (!ttf) return -1;
	s_fontIds[s_fontCount] = fonsAddFontMem(s_fons, "font", ttf, sz, 1);
	if (s_fontCount == 0) s_fontId = s_fontIds[0];
	return s_fontCount++;
}

void void2dSelectFont(int id) {
	if (id >= 0 && id < s_fontCount) s_fontId = s_fontIds[id];
}

uint32_t void2dWhiteView(void) { return s_whiteView.id; }
uint32_t void2dFontView(void) { return s_fontView.id; }

// A clip is a command in the stream now, applied here during replay rather than by the tree
// walk. The whole viewport is w == 0, which is how displayList.ms records "no clip".
static void applyScissor(const float *cmd, float fbW, float fbH) {
	float w = cmd[CMD_CLIP_W];
	float h = cmd[CMD_CLIP_H];
	if (w <= 0.0f || h <= 0.0f) {
		sg_apply_scissor_rectf(0.0f, 0.0f, fbW * s_dpiScale, fbH * s_dpiScale, true);
		return;
	}
	sg_apply_scissor_rectf(cmd[CMD_CLIP_X] * s_dpiScale, cmd[CMD_CLIP_Y] * s_dpiScale,
		w * s_dpiScale, h * s_dpiScale, true);
}

void void2dSetDpiScale(float scale) { if (scale > 0.0f) s_dpiScale = scale; }

// Per-frame reset — re-arms the single sg_update_image allowed for the font atlas.
void void2dFrameBegin(void) {
	s_atlasUpdated = false;
	s_drawCallCount = 0;
	s_uploadCount = 0;
	s_uploadBytes = 0;
}

// One separable-blur tap pass into the active offscreen RT pass: sample srcView with the
// 9-tap kernel offset by (dirX,dirY) in UV space. Caller runs it twice (H then V) ping-ponging
// between two RTs. dir = (radius/texW,0) horizontal, (0,radius/texH) vertical.
void void2dBlur(uint32_t srcView, float dirX, float dirY) {
	sg_apply_pipeline(s_blurPip);
	sg_bindings b = {0};
	b.vertex_buffers[0] = s_fsQuad;
	b.views[VIEW_srcTex] = (sg_view){ .id = srcView };
	b.samplers[SMP_srcSmp] = s_smp[2];   // linear, clamp: a blur tap past the edge must not wrap
	sg_apply_bindings(&b);
	blur_params_t p = {0};
	p.dir[0] = dirX; p.dir[1] = dirY;
	sg_range u = { .ptr = &p, .size = sizeof(p) };
	sg_apply_uniforms(UB_blur_params, &u);
	sg_draw(0, 6, 1);
}

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

static void runCommands(const float *commands, int commandCount,
                        const float *effects, int effectCount,
                        float fbW, float fbH);

// Upload the frame's geometry once, then run every render-target pass to completion. Called
// with NO pass open: each TargetBegin opens one and its TargetEnd closes it, so target passes
// are siblings and never nest. That is what hoisting the target blocks out of the swapchain
// list buys - sokol asserts `!_sg.cur_pass.valid` on a nested begin, which is exactly how the
// old filter path died. Returns 0 when the frame was dropped; then nothing else may draw.
int void2dReplayTargets(const float *targetCommands, int targetCommandCount,
                        const float *effects, int effectCount,
                        const float *vertices, int vertexCount) {
	s_frameUploaded = 0;
	s_frameBaseOffset = 0;

	size_t vertexBytes = (size_t)vertexCount * VERTEX_FLOATS * sizeof(float);
	if (vertexBytes > (size_t)VOID2D_MAX_BUFFER_BYTES) {
		// A dropped frame with an error, never a silent truncation. The old path let
		// sg_append_buffer run past the end and the rest of the scene simply vanished.
		s_droppedFrames++;
		fprintf(stderr, "void2d: frame needs %zu bytes of geometry, cap is %d — frame dropped\n",
			vertexBytes, VOID2D_MAX_BUFFER_BYTES);
		return 0;
	}
	ensureVertexBuffer((int)vertexBytes);
	ensureAtlas();

	// One upload for the whole frame, before any draw: every Draw command is a range inside
	// it. This is the "one upload per bracket" of VOID2D.md P1, and it is one per FRAME here
	// because the target lists share the stream.
	if (vertexBytes > 0) {
		sg_range data = { .ptr = vertices, .size = vertexBytes };
		s_frameBaseOffset = sg_append_buffer(s_vbuf, &data);
		s_uploadCount++;
		s_uploadBytes += (int)vertexBytes;
	}
	s_frameUploaded = 1;
	if (targetCommandCount > 0) {
		runCommands(targetCommands, targetCommandCount, effects, effectCount, 0.0f, 0.0f);
	}
	return 1;
}

// Replay the swapchain list inside the pass the caller already opened.
void void2dReplay(const float *commands, int commandCount,
                  const float *effects, int effectCount,
                  float fbW, float fbH) {
	if (commandCount <= 0 || !s_frameUploaded) return;
	runCommands(commands, commandCount, effects, effectCount, fbW, fbH);
}

// The one executor both lists go through. `fbW`/`fbH` are the viewport the commands were
// recorded against; a TargetBegin replaces them for the length of its block, which is how a
// target of a different size gets the right projection with no second code path.
static void runCommands(const float *commands, int commandCount,
                        const float *effects, int effectCount,
                        float fbW, float fbH) {
	float sizeStack[VOID2D_MAX_TARGET_DEPTH][2];
	int sizeDepth = 0;

	// A uniform block that has not changed is not re-applied. On WebGPU and Metal every
	// sg_apply_uniforms costs at least 256 bytes of the per-frame uniform buffer whatever
	// the payload (sokol_gfx.h:2014-2023, VOID2D.md "Web and WebGPU"), and in a UI frame the
	// viewport and the colour pipeline are the same for almost every draw. The display list
	// is what makes this visible: before it, each draw applied both blocks unconditionally.
	void2d_params_t lastParams;
	void2d_fx_t lastFx;
	int paramsValid = 0;
	int fxValid = 0;
	uint32_t lastPipeline = 0;

	int scissorApplied = 0;
	for (int i = 0; i < commandCount; i++) {
		const float *cmd = commands + (size_t)i * CMD_FLOATS;
		int kind = (int)cmd[CMD_KIND];
		if (kind == CMD_KIND_SCISSOR) {
			applyScissor(cmd, fbW, fbH);
			scissorApplied = 1;
			continue;
		}
		if (kind == CMD_KIND_BLUR) {
			void2dBlur((uint32_t)cmd[CMD_VIEW], cmd[CMD_ARG0], cmd[CMD_ARG1]);
			continue;
		}
		if (kind == CMD_KIND_TGT_BEGIN) {
			if (sizeDepth < VOID2D_MAX_TARGET_DEPTH) {
				sizeStack[sizeDepth][0] = fbW;
				sizeStack[sizeDepth][1] = fbH;
				sizeDepth++;
			}
			fbW = cmd[CMD_ARG0];
			fbH = cmd[CMD_ARG1];
			voidBeginRenderTargetPass((uint32_t)cmd[CMD_VIEW],
				cmd[CMD_CLEAR_R], cmd[CMD_CLEAR_R + 1], cmd[CMD_CLEAR_R + 2], cmd[CMD_CLEAR_R + 3]);
			lastPipeline = 0; paramsValid = 0; fxValid = 0; scissorApplied = 0;
			continue;
		}
		if (kind == CMD_KIND_TGT_END) {
			voidEndPass();
			if (sizeDepth > 0) {
				sizeDepth--;
				fbW = sizeStack[sizeDepth][0];
				fbH = sizeStack[sizeDepth][1];
			}
			lastPipeline = 0; paramsValid = 0; fxValid = 0; scissorApplied = 0;
			continue;
		}
		if (kind != CMD_KIND_DRAW) continue;

		int count = (int)cmd[CMD_VERTEX_COUNT];
		if (count <= 0) continue;
		int blend = (int)cmd[CMD_BLEND];
		if (blend < 0 || blend >= VOID2D_BLEND_COUNT) blend = 0;
		uint32_t view = (uint32_t)cmd[CMD_VIEW];
		if (view == 0) view = s_whiteView.id;

		sg_pipeline pip = (cmd[CMD_RT_MODE] != 0.0f ? s_pipsRT : s_pips)[blend];
		if (pip.id != lastPipeline) {
			sg_apply_pipeline(pip);
			lastPipeline = pip.id;
			// sokol resets the scissor and the bindings when a pipeline is applied.
			scissorApplied = 0;
			paramsValid = 0;
			fxValid = 0;
		}
		sg_bindings b = {0};
		b.vertex_buffers[0] = s_vbuf;
		b.vertex_buffer_offsets[0] = s_frameBaseOffset + (int)cmd[CMD_VERTEX_OFFSET] * VERTEX_FLOATS * (int)sizeof(float);
		b.views[VIEW_tex] = (sg_view){ .id = view };
		int smpIndex = (int)cmd[CMD_SAMPLER];
		if (smpIndex < 0 || smpIndex >= SMP_COUNT) { smpIndex = 2; }
		b.samplers[SMP_smp] = s_smp[smpIndex];
		sg_apply_bindings(&b);

		// After a pipeline change the scissor is no longer in force, and the clip a command
		// carries is the one displayList.ms recorded for it.
		if (!scissorApplied) {
			applyScissor(cmd, fbW, fbH);
			scissorApplied = 1;
		}

		int effectIndex = (int)cmd[CMD_EFFECT];
		const float *fx = (effectIndex >= 0 && effectIndex < effectCount)
			? effects + (size_t)effectIndex * EFFECT_FLOATS
			: NULL;
		const float *matrix = fx ? fx : s_identityMatrix;
		float addR = fx ? fx[16] : 0.0f;
		float addG = fx ? fx[17] : 0.0f;
		float addB = fx ? fx[18] : 0.0f;
		float addA = fx ? fx[19] : 0.0f;

		void2d_params_t vp = {0};
		vp.viewport[0] = fbW;
		vp.viewport[1] = fbH;
		vp.viewport[2] = (voidIsRenderTargetView(view) && !sg_query_features().origin_top_left) ? 1.0f : 0.0f;
		vp.viewport[3] = (voidIsRenderTargetView(view)
			&& addR == 0.0f && addG == 0.0f && addB == 0.0f
			&& matrix[0] == 1.0f && matrix[5] == 1.0f && matrix[10] == 1.0f) ? 1.0f : 0.0f;
		vp.model0[0] = 1.0f; vp.model0[3] = 1.0f;   // the stream is already in world space
		vp.globalColor[0] = 1.0f; vp.globalColor[1] = 1.0f; vp.globalColor[2] = 1.0f; vp.globalColor[3] = 1.0f;
		if (!paramsValid || memcmp(&vp, &lastParams, sizeof(vp)) != 0) {
			sg_range u = { .ptr = &vp, .size = sizeof(vp) };
			sg_apply_uniforms(UB_void2d_params, &u);
			lastParams = vp;
			paramsValid = 1;
		}

		void2d_fx_t fxu = {0};
		memcpy(fxu.colorMatrix, matrix, sizeof(fxu.colorMatrix));
		fxu.colorAdd[0] = addR; fxu.colorAdd[1] = addG; fxu.colorAdd[2] = addB; fxu.colorAdd[3] = addA;
		if (fx) {
			fxu.colorKey[0] = fx[20]; fxu.colorKey[1] = fx[21];
			fxu.colorKey[2] = fx[22]; fxu.colorKey[3] = fx[23];
		}
		if (!fxValid || memcmp(&fxu, &lastFx, sizeof(fxu)) != 0) {
			sg_range uf = { .ptr = &fxu, .size = sizeof(fxu) };
			sg_apply_uniforms(UB_void2d_fx, &uf);
			lastFx = fxu;
			fxValid = 1;
		}

		sg_draw(0, count, 1);
		s_drawCallCount++;
	}
}

void void2dTextBegin(float x, float y, float size, const char *text) {
	if (!s_fons || s_fontId == FONS_INVALID) return;
	fonsSetFont(s_fons, s_fontId);
	fonsSetSize(s_fons, size * s_dpiScale);
	fonsSetAlign(s_fons, FONS_ALIGN_LEFT | FONS_ALIGN_TOP);
	fonsTextIterInit(s_fons, &s_iter, x * s_dpiScale, y * s_dpiScale, text, NULL);
}

static float s_quad[8];
float *void2dTextNext(void) {
	if (!s_fons) return NULL;
	FONSquad q;
	if (!fonsTextIterNext(s_fons, &s_iter, &q)) return NULL;
	s_quad[0] = q.x0 / s_dpiScale; s_quad[1] = q.y0 / s_dpiScale; s_quad[2] = q.s0; s_quad[3] = q.t0;
	s_quad[4] = q.x1 / s_dpiScale; s_quad[5] = q.y1 / s_dpiScale; s_quad[6] = q.s1; s_quad[7] = q.t1;
	return s_quad;
}

float void2dTextWidth(float size, const char *text) {
	if (!s_fons || s_fontId == FONS_INVALID) return 0.0f;
	fonsSetFont(s_fons, s_fontId);
	fonsSetSize(s_fons, size * s_dpiScale);
	fonsSetAlign(s_fons, FONS_ALIGN_LEFT | FONS_ALIGN_TOP);
	return fonsTextBounds(s_fons, 0.0f, 0.0f, text, NULL, NULL) / s_dpiScale;
}

float void2dLineHeight(float size) {
	if (!s_fons || s_fontId == FONS_INVALID) return size;
	fonsSetFont(s_fons, s_fontId);
	fonsSetSize(s_fons, size * s_dpiScale);
	float asc = 0.0f, desc = 0.0f, lineh = size;
	fonsVertMetrics(s_fons, &asc, &desc, &lineh);
	return lineh / s_dpiScale;
}

// persistent glyph-advance spacing; set per draw (0 = default) so it never leaks.
void void2dTextSpacing(float spacing) {
	if (s_fons) fonsSetSpacing(s_fons, spacing);
}

int void2dAtlasGen(void) { return s_atlasGen; }

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
