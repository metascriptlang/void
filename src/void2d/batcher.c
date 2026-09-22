// Void 2D — thin sokol/fontstash primitives (see batcher.h). Batcher logic is in draw.ms.

#include "batcher.h"
#include "../sokol/bridge.h"
#include "../../deps/sokol/sokol_gfx.h"
#include "shader2d.glsl.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stddef.h>
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
// P2's flat sprite pipeline: one instance per quad, no SDF maths, its own program. Guardrail
// 8 is that a sprite-only scene must not pay for the UI pipeline, and a separate program is
// the only form of that promise a reviewer can check.
static sg_pipeline s_spritePips[VOID2D_BLEND_COUNT];
static sg_pipeline s_spritePipsRT[VOID2D_BLEND_COUNT];
// P2's unified UI pipeline: one program, one 108-byte stride, a per-instance mode. It is a
// third pipeline and needs no new machinery — a run carries its pipeline, so switching it
// closes the run and records break:pipeline exactly like a view or a blend change does.
static sg_pipeline s_uiPips[VOID2D_BLEND_COUNT];
static sg_pipeline s_uiPipsRT[VOID2D_BLEND_COUNT];
static int s_uiInstanceBase;          // where this frame's UI instances start in s_vbuf
static int s_uiInstanceCount;
static sg_buffer s_unitQuad;          // six corners (0,0)..(1,1), made once, stepped per vertex
static int s_spriteInstanceBase;      // where this frame's sprite instances start in s_vbuf
static int s_spriteInstanceCount;
// sokol's origin convention does not change after setup, and it was being queried twice per
// draw command - 40 000 times a frame on the UI bench whose `present` this phase reports as
// not met.
static bool s_originTopLeft;
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
static int s_atlasGen = 0;    // bumped on atlas resize -> invalidates cached glyph meshes
// Atlas images and views made and destroyed, so a leak is a number rather than an eventual
// `sg_make_image` failure 128 resizes later.
static int s_atlasMade;
static int s_atlasFreed;
// Buffers this module owns, counted where sokol is actually called. It used to be
// `return 3` - a literal, gated in tests/bench/baseline.json against the literal 3, so the
// assertion compared a constant to a constant and would have kept passing if every Label
// allocated a buffer again. It also miscounted: two of the three were buffers and the third
// was the font image.
static int s_buffersMade;
static int s_buffersFreed;

// A sokol FRAME, which is not a bracket. `begin2d`/`flushTargets` is a bracket and a frame may
// hold several - src/examples/renderer2d.ms runs two, the manual filter targets and then the
// scene - while sokol resets a buffer's append cursor only once per frame, at sg_commit
// (`sokol_gfx.h:27551`). Three things are therefore per frame and were being re-armed per
// bracket: the append budget, the one-sg_update_image-per-image rule, and the counters.
static int s_frameOpen;
// Brackets opened since the last void2dFrameEnd. A frame legitimately holds a few - the demo
// runs two - so this is not an error until it is absurd. void2dSetup registers void2dFrameEnd
// as the bridge's commit hook; any direct sg_commit call bypasses it and leaves s_frameOpen
// latched, so ensureAtlas stops uploading and retired resources stop being freed. Keep the
// counter loud because the visible failure appears several layers from the missing frame end.
static int s_bracketsThisFrame;
static int s_frameEndMissingReported;
#define VOID2D_BRACKETS_BEFORE_COMPLAINT 16
static int s_frameVertexBytes;   // bytes appended so far this FRAME, across every bracket

// A vertex buffer that grew mid-frame cannot be destroyed on the spot: an earlier bracket's
// draws are already encoded against it. Same frame-linear discipline as the retired atlases.
#define VOID2D_MAX_RETIRED_BUFFERS 4
static sg_buffer s_retiredBuf[VOID2D_MAX_RETIRED_BUFFERS];
static int s_retiredBufCount;
// A glyph that does not fit gets one report, not one per glyph per frame.
static bool s_atlasFullReported;
// The atlas image and view a resize retired. They cannot be destroyed on the spot: the
// commands already recorded this frame carry the OLD view id, and the replay has not run yet,
// so destroying immediately would have the replay bind a dead view. They are freed at the top
// of the next frame instead, by which time the frame that referenced them has been replayed -
// the same frame-linear discipline the filter targets use.
#define VOID2D_MAX_RETIRED_ATLASES 8
static sg_image s_retiredImg[VOID2D_MAX_RETIRED_ATLASES];
static sg_view s_retiredView[VOID2D_MAX_RETIRED_ATLASES];
static int s_retiredCount;
// 2048 is the smallest guaranteed maximum texture size across the backends this ships on,
// WebGL2 included, and the RGBA mirror of one is already 16 MB (batcher.c expands R8 to RGBA
// on the CPU - VOID2D.md lists that as P3's to remove).
#define VOID2D_MAX_ATLAS 2048

// Mirrors src/void2d/displayList.ms. void2dLayoutCheck is what keeps the two honest; it is
// called from MetaScript with that file's own constants, so a field added on one side and
// not the other fails at setup rather than drawing garbage.
#define CMD_FLOATS          32
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
#define CMD_PIPELINE        19
#define CMD_INSTANCE_OFFSET 20
#define CMD_INSTANCE_COUNT  21
#define CMD_CLIP_U_X        22

#define PIPELINE_VERTEX     0
#define PIPELINE_SPRITE     1
#define PIPELINE_UI         2

// The sprite record and its GPU struct are the same bytes in the same order, so the upload is
// a memcpy and not a pack. src/test/instanceLayoutCheck.ms asserts that.
#define SPRITE_REC_FLOATS   16

// The UI record is 36 floats where the GPU instance is 108 bytes: six float4 lanes copy
// straight through and the three trailing colours pack to UBYTE4N.
// src/test/instanceLayoutCheck.ms asserts both numbers against instance.ms.
#define UI_REC_FLOATS       36

#define EFFECT_FLOATS       44
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
// Made minus freed, at the sites that make and free. Two in a steady frame: the growing
// vertex buffer and the fullscreen quad the filter passes draw. It goes UP if anything starts
// allocating per node again, which is the whole reason the number is gated.
int void2dBuffersAlive(void) { return s_buffersMade - s_buffersFreed; }

// Glyph-atlas images made minus freed. One, unless a resize is waiting to be collected at the
// top of the next frame. A number, because the leak it replaced was invisible until sokol's
// image pool ran out 128 resizes later.
int void2dAtlasImagesAlive(void) { return s_atlasMade - s_atlasFreed; }

// P2's two instance layouts. These structs are what the vertex-buffer layout is built from,
// so sizeof is the stride and src/void2d/instance.ms's constants are checked against it.
typedef struct {
	float affine[4];
	float originSize[4];
	float uvRadii[4];
	float borders[4];
	float params0[4];
	float params1[4];
	uint32_t colorFill;
	uint32_t colorBorder;
	uint32_t colorExtra;
} void2dUiInstance;

// The UI record is 36 floats and the GPU instance is 108 bytes, so unlike the sprite stream
// this one cannot be uploaded as it was recorded — the three colours pack to UBYTE4N on the
// way in. That is one staging buffer, grown and never shrunk, rather than bit-twiddling in
// the emitter where a Vec<float32> would lose the low bits to the mantissa anyway.
static void2dUiInstance *s_uiStage;
static int s_uiStageCap;

typedef struct {
	float affine[4];
	float originSize[4];
	float uv[4];
	float color[4];
} void2dSpriteInstance;

// One colour channel as the GPU will store it. Rounding, not truncation: truncation loses a
// full level at every channel and turns 1.0 into 254. src/void2d/instance.ms holds the same
// arithmetic, and `void2dPackChannel` is exported so a test can compare the two rather than
// letting guardrail 9 rest on two copies that look alike.
int void2dPackChannel(float value) {
	float scaled = value * 255.0f + 0.5f;
	if (scaled <= 0.0f) { return 0; }
	if (scaled >= 255.0f) { return 255; }
	return (int)scaled;
}

static uint32_t packColor(const float *c) {
	return (uint32_t)void2dPackChannel(c[0])
		| ((uint32_t)void2dPackChannel(c[1]) << 8)
		| ((uint32_t)void2dPackChannel(c[2]) << 16)
		| ((uint32_t)void2dPackChannel(c[3]) << 24);
}

int void2dUiInstanceStride(void) { return (int)sizeof(void2dUiInstance); }
int void2dSpriteInstanceStride(void) { return (int)sizeof(void2dSpriteInstance); }

int void2dInstanceLayoutCheck(int uiStride, int uiAffine, int uiOriginSize, int uiUvRadii,
                              int uiBorders, int uiParams0, int uiParams1, int uiColorFill,
                              int uiColorBorder, int uiColorExtra,
                              int spriteStride, int spriteAffine, int spriteOriginSize,
                              int spriteUv, int spriteColor) {
	return uiStride == (int)sizeof(void2dUiInstance)
		&& uiAffine == (int)offsetof(void2dUiInstance, affine)
		&& uiOriginSize == (int)offsetof(void2dUiInstance, originSize)
		&& uiUvRadii == (int)offsetof(void2dUiInstance, uvRadii)
		&& uiBorders == (int)offsetof(void2dUiInstance, borders)
		&& uiParams0 == (int)offsetof(void2dUiInstance, params0)
		&& uiParams1 == (int)offsetof(void2dUiInstance, params1)
		&& uiColorFill == (int)offsetof(void2dUiInstance, colorFill)
		&& uiColorBorder == (int)offsetof(void2dUiInstance, colorBorder)
		&& uiColorExtra == (int)offsetof(void2dUiInstance, colorExtra)
		&& spriteStride == (int)sizeof(void2dSpriteInstance)
		&& spriteAffine == (int)offsetof(void2dSpriteInstance, affine)
		&& spriteOriginSize == (int)offsetof(void2dSpriteInstance, originSize)
		&& spriteUv == (int)offsetof(void2dSpriteInstance, uv)
		&& spriteColor == (int)offsetof(void2dSpriteInstance, color);
}

int void2dLayoutCheck(int commandFloats, int effectFloats, int vertexFloats,
                      int kindField, int breakField, int vertexOffsetField, int vertexCountField,
                      int viewField, int blendField, int samplerField, int effectField,
                      int samplerCount, int maxTargetDepth, int clearRField,
                      int clipXField, int clipUField, int arg0Field, int rtModeField,
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
		&& clipUField == CMD_CLIP_U_X
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
	unsigned char *mirror = (unsigned char *)malloc((size_t)(w * h * 4));
	if (!mirror) {
		fprintf(stderr, "void2d: no memory for a %dx%d glyph atlas mirror\n", w, h);
		return 0;
	}
	s_atlasW = w;
	s_atlasH = h;
	s_atlasRGBA = mirror;
	memset(s_atlasRGBA, 0, (size_t)(w * h * 4));
	// The image is the only sokol object in the fontstash path, and T1 asserts glyph emission
	// in a process with no context at all: headless, the mirror and the white texel are real
	// and the image is not, and nothing below the layout ever looks at the ids.
	if (sg_isvalid()) {
		sg_image_desc d = {0};
		d.width = w;
		d.height = h;
		d.pixel_format = SG_PIXELFORMAT_RGBA8;
		// Persists across frames, re-uploaded only when fontstash adds glyphs. dynamic_update is
		// deprecated upstream in favour of write_persistent (sokol CHANGELOG, 30-Aug-2026).
		d.usage.dynamic_update = true;
		s_fontImg = sg_make_image(&d);
		s_fontView = (sg_view){ .id = voidMakeView(s_fontImg.id) };
		s_atlasMade++;
	} else {
		s_fontImg = (sg_image){0};
		s_fontView = (sg_view){0};
	}
	return 1;
}
static int fons_resize(void *up, int w, int h) {
	s_atlasGen++;
	if (s_atlasRGBA) free(s_atlasRGBA);
	// Retire the outgoing image and view before fons_create overwrites the handles. Without
	// this, every resize leaked one of each against sokol's 128-slot pools: measured on
	// regress/atlasFull before the fix, one capture of one scene left 3 atlas images alive
	// and 0 freed. Headless there is no image (sg_isvalid() was false at create), so there
	// is nothing to retire.
	if (s_fontImg.id == 0) {
		// no image to retire
	} else if (s_retiredCount < VOID2D_MAX_RETIRED_ATLASES) {
		s_retiredImg[s_retiredCount] = s_fontImg;
		s_retiredView[s_retiredCount] = s_fontView;
		s_retiredCount++;
	} else {
		// Eight resizes inside one frame is not a thing that happens - the atlas only ever
		// doubles, twice, between 512 and the 2048 cap. Say so rather than drop them.
		fprintf(stderr, "void2d: more than %d glyph-atlas resizes in one frame; the oldest images are leaked\n",
			VOID2D_MAX_RETIRED_ATLASES);
	}
	int ok = fons_create(up, w, h);
	return ok;
}

// Free what the previous frame retired. Called once per frame, after that frame's replay.
static void releaseRetiredBuffers(void) {
	for (int i = 0; i < s_retiredBufCount; i++) {
		sg_destroy_buffer(s_retiredBuf[i]);
		s_buffersFreed++;
	}
	s_retiredBufCount = 0;
}

static void releaseRetiredAtlases(void) {
	if (s_retiredCount == 0) { return; }
	for (int i = 0; i < s_retiredCount; i++) {
		sg_destroy_view(s_retiredView[i]);
		sg_destroy_image(s_retiredImg[i]);
		s_atlasFreed++;
	}
	fprintf(stderr, "void2d: released %d retired glyph atlas(es); images made %d freed %d alive %d\n",
		s_retiredCount, s_atlasMade, s_atlasFreed, s_atlasMade - s_atlasFreed);
	s_retiredCount = 0;
}

// FONS_ATLAS_FULL: fontstash could not place a glyph. It asks once, retries once, and drops
// the glyph if the retry also fails - which is why, with no handler at all, *which* glyphs
// survived varied between runs of the same binary (three distinct outputs in ten runs,
// tests/PENDING.md at P0). Growing the atlas and letting it retry is the holding fix;
// P3 removes fontstash and the class with it.
static void fons_error(void *up, int error, int val) {
	(void)up;
	(void)val;
	if (error != FONS_ATLAS_FULL || !s_fons) { return; }
	int w = 0, h = 0;
	fonsGetAtlasSize(s_fons, &w, &h);
	int nw = w, nh = h;
	// Height first, then width: fontstash's packer fills row by row, so a taller atlas takes
	// the next glyph where a wider one only helps the row it is already on.
	if (h <= w && h * 2 <= VOID2D_MAX_ATLAS) { nh = h * 2; }
	else if (w * 2 <= VOID2D_MAX_ATLAS) { nw = w * 2; }
	else {
		if (!s_atlasFullReported) {
			s_atlasFullReported = true;
			fprintf(stderr, "void2d: glyph atlas is full at %dx%d, the cap - later glyphs will be dropped\n", w, h);
		}
		return;
	}
	if (!fonsExpandAtlas(s_fons, nw, nh) && !s_atlasFullReported) {
		s_atlasFullReported = true;
		fprintf(stderr, "void2d: could not expand the glyph atlas from %dx%d to %dx%d\n", w, h, nw, nh);
	}
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
// The growth policy, as arithmetic and nothing else: max(2x, next power of two), no shrink,
// and 0 for "past the cap, drop the frame". Pure, so T1 can assert its boundaries with no GPU
// - which is the only way the cap is ever exercised, since reaching it for real needs 192 MB
// of geometry. `have` is the current buffer size in bytes, `need` what the frame wants.
int void2dGrowthTarget(int have, int need) {
	if (need > VOID2D_MAX_BUFFER_BYTES) { return 0; }
	if (need <= have) { return have; }
	int want = have > 0 ? have * 2 : VOID2D_INITIAL_BUFFER_BYTES;
	while (want < need) { want *= 2; }
	if (want > VOID2D_MAX_BUFFER_BYTES) { want = VOID2D_MAX_BUFFER_BYTES; }
	return want;
}

static void ensureVertexBuffer(int bytes) {
	int want = void2dGrowthTarget(s_vbufBytes, bytes);
	if (want <= s_vbufBytes) return;
	if (s_vbuf.id) {
		// Retire, do not destroy: a second bracket that triggers growth would otherwise free a
		// buffer the first bracket's encoded draws still point at. Harmless on D3D11's
		// immediate context, a use-after-free on Metal and WebGPU - guardrail 9.
		if (s_retiredBufCount < VOID2D_MAX_RETIRED_BUFFERS) {
			s_retiredBuf[s_retiredBufCount] = s_vbuf;
			s_retiredBufCount++;
		} else {
			sg_destroy_buffer(s_vbuf);
			s_buffersFreed++;
		}
	}
	sg_buffer_desc bd = {0};
	bd.usage.vertex_buffer = true;
	bd.usage.dynamic_update = true;
	bd.size = (size_t)want;
	s_vbuf = sg_make_buffer(&bd);
	s_buffersMade++;
	s_vbufBytes = want;
}
static void ensureFons(void);


void void2dSetup(void) {
	voidSetCommitHook(void2dFrameEnd);
	ensureVertexBuffer(VOID2D_INITIAL_BUFFER_BYTES);

	s_originTopLeft = sg_query_features().origin_top_left;
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

	sg_shader spriteShd = sg_make_shader(sprite_shader_desc(sg_query_backend()));
	for (int i = 0; i < VOID2D_BLEND_COUNT; i++) {
		sg_pipeline_desc sd = {0};
		sd.shader = spriteShd;
		sd.layout.buffers[1].step_func = SG_VERTEXSTEP_PER_INSTANCE;
		sd.layout.attrs[ATTR_sprite_corner].format = SG_VERTEXFORMAT_FLOAT2;
		sd.layout.attrs[ATTR_sprite_corner].buffer_index = 0;
		sd.layout.attrs[ATTR_sprite_iAffine].format = SG_VERTEXFORMAT_FLOAT4;
		sd.layout.attrs[ATTR_sprite_iAffine].buffer_index = 1;
		sd.layout.attrs[ATTR_sprite_iOriginSize].format = SG_VERTEXFORMAT_FLOAT4;
		sd.layout.attrs[ATTR_sprite_iOriginSize].buffer_index = 1;
		sd.layout.attrs[ATTR_sprite_iUv].format = SG_VERTEXFORMAT_FLOAT4;
		sd.layout.attrs[ATTR_sprite_iUv].buffer_index = 1;
		sd.layout.attrs[ATTR_sprite_iColor].format = SG_VERTEXFORMAT_FLOAT4;
		sd.layout.attrs[ATTR_sprite_iColor].buffer_index = 1;
		sd.colors[0].blend.enabled = modes[i].on;
		sd.colors[0].blend.src_factor_rgb = modes[i].srgb;
		sd.colors[0].blend.dst_factor_rgb = modes[i].drgb;
		sd.colors[0].blend.src_factor_alpha = modes[i].sa;
		sd.colors[0].blend.dst_factor_alpha = modes[i].da;
		s_spritePips[i] = sg_make_pipeline(&sd);
		sd.colors[0].pixel_format = SG_PIXELFORMAT_RGBA8;
		sd.sample_count = 1;
		sd.depth.pixel_format = SG_PIXELFORMAT_NONE;
		s_spritePipsRT[i] = sg_make_pipeline(&sd);
	}

	sg_shader uiShd = sg_make_shader(ui_shader_desc(sg_query_backend()));
	for (int i = 0; i < VOID2D_BLEND_COUNT; i++) {
		sg_pipeline_desc ud = {0};
		ud.shader = uiShd;
		ud.layout.buffers[1].step_func = SG_VERTEXSTEP_PER_INSTANCE;
		ud.layout.attrs[ATTR_ui_corner].format = SG_VERTEXFORMAT_FLOAT2;
		ud.layout.attrs[ATTR_ui_corner].buffer_index = 0;
		ud.layout.attrs[ATTR_ui_iAffine].format = SG_VERTEXFORMAT_FLOAT4;
		ud.layout.attrs[ATTR_ui_iAffine].buffer_index = 1;
		ud.layout.attrs[ATTR_ui_iOriginSize].format = SG_VERTEXFORMAT_FLOAT4;
		ud.layout.attrs[ATTR_ui_iOriginSize].buffer_index = 1;
		ud.layout.attrs[ATTR_ui_iUvRadii].format = SG_VERTEXFORMAT_FLOAT4;
		ud.layout.attrs[ATTR_ui_iUvRadii].buffer_index = 1;
		ud.layout.attrs[ATTR_ui_iBorders].format = SG_VERTEXFORMAT_FLOAT4;
		ud.layout.attrs[ATTR_ui_iBorders].buffer_index = 1;
		ud.layout.attrs[ATTR_ui_iParams0].format = SG_VERTEXFORMAT_FLOAT4;
		ud.layout.attrs[ATTR_ui_iParams0].buffer_index = 1;
		ud.layout.attrs[ATTR_ui_iParams1].format = SG_VERTEXFORMAT_FLOAT4;
		ud.layout.attrs[ATTR_ui_iParams1].buffer_index = 1;
		// The three colours are UBYTE4N on the GPU and four floats in the record — the pack
		// happens on the way into the buffer (instance.ms, "the RECORD layout"), because a
		// Vec<float32> cannot hold a packed RGBA8 without losing the low bits to the mantissa.
		ud.layout.attrs[ATTR_ui_iColorFill].format = SG_VERTEXFORMAT_UBYTE4N;
		ud.layout.attrs[ATTR_ui_iColorFill].buffer_index = 1;
		ud.layout.attrs[ATTR_ui_iColorBorder].format = SG_VERTEXFORMAT_UBYTE4N;
		ud.layout.attrs[ATTR_ui_iColorBorder].buffer_index = 1;
		ud.layout.attrs[ATTR_ui_iColorExtra].format = SG_VERTEXFORMAT_UBYTE4N;
		ud.layout.attrs[ATTR_ui_iColorExtra].buffer_index = 1;
		ud.colors[0].blend.enabled = modes[i].on;
		ud.colors[0].blend.src_factor_rgb = modes[i].srgb;
		ud.colors[0].blend.dst_factor_rgb = modes[i].drgb;
		ud.colors[0].blend.src_factor_alpha = modes[i].sa;
		ud.colors[0].blend.dst_factor_alpha = modes[i].da;
		s_uiPips[i] = sg_make_pipeline(&ud);
		ud.colors[0].pixel_format = SG_PIXELFORMAT_RGBA8;
		ud.sample_count = 1;
		ud.depth.pixel_format = SG_PIXELFORMAT_NONE;
		s_uiPipsRT[i] = sg_make_pipeline(&ud);
	}

	// Six corners rather than four plus an index buffer. VOID2D.md records that the two have
	// not been compared on a Mali or an Adreno; until they have, this is one 48-byte static
	// buffer and no index path to get wrong.
	static const float unit[12] = {
		0.0f, 0.0f,  1.0f, 0.0f,  1.0f, 1.0f,
		0.0f, 0.0f,  1.0f, 1.0f,  0.0f, 1.0f,
	};
	sg_buffer_desc uqd = {0};
	uqd.usage.vertex_buffer = true;
	uqd.data = (sg_range){ .ptr = unit, .size = sizeof(unit) };
	s_unitQuad = sg_make_buffer(&uqd);
	s_buffersMade++;

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
	s_buffersMade++;

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

	ensureFons();
}

// fontstash is a CPU rasterizer; its lifetime was tied to void2dSetup only because that is
// where it was created. T1 asserts glyph emission in a process with no sokol context at all,
// so the fons state is created on demand — the first text entry point to need it — and the
// one sokol object in the path (the atlas image) guards itself on sg_isvalid().
static void ensureFons(void) {
	if (s_fons) return;
	FONSparams fp = {0};
	fp.width = 512;
	fp.height = 512;
	fp.flags = (unsigned char)FONS_ZERO_TOPLEFT;
	fp.renderCreate = fons_create;
	fp.renderResize = fons_resize;
	fp.renderDelete = fons_delete;
	s_fons = fonsCreateInternal(&fp);
	if (s_fons) {
		fonsSetErrorCallback(s_fons, fons_error, NULL);
		void2dAddFont("assets/font.ttf");
	}
}

int void2dAddFont(const char *path) {
	if (!s_fons) ensureFons();
	if (!s_fons || s_fontCount >= 16) return -1;
	int sz = 0;
	unsigned char *ttf = readFile(path, &sz);
	if (!ttf) return -1;
	s_fontIds[s_fontCount] = fonsAddFontMem(s_fons, "font", ttf, sz, 1);
	if (s_fontCount == 0) s_fontId = s_fontIds[0];
	return s_fontCount++;
}

void void2dSelectFont(int id) {
	if (!s_fons) ensureFons();
	if (id >= 0 && id < s_fontCount) s_fontId = s_fontIds[id];
}

uint32_t void2dWhiteView(void) { return s_whiteView.id; }
uint32_t void2dFontView(void) { return s_fontView.id; }

// A clip is a command in the stream now, applied here during replay rather than by the tree
// walk. The whole viewport is w == 0, which is how displayList.ms records "no clip".
static void applyScissor(const float *cmd, float fbW, float fbH) {
	// Inside a render-target pass the viewport IS the target's pixel size - `render.ms` sizes
	// a filter target from bounds in logical units and hands that straight to
	// `allocRenderTarget` - so one logical unit is one pixel there and scaling by the DPI
	// would scissor 1.5x the intended rect at DPI 1.5. Only the swapchain is in logical units.
	float scale = (cmd[CMD_RT_MODE] != 0.0f) ? 1.0f : s_dpiScale;
	float w = cmd[CMD_CLIP_W];
	float h = cmd[CMD_CLIP_H];
	if (w <= 0.0f || h <= 0.0f) {
		sg_apply_scissor_rectf(0.0f, 0.0f, fbW * scale, fbH * scale, true);
		return;
	}
	sg_apply_scissor_rectf(cmd[CMD_CLIP_X] * scale, cmd[CMD_CLIP_Y] * scale,
		w * scale, h * scale, true);
}

void void2dSetDpiScale(float scale) { if (scale > 0.0f) s_dpiScale = scale; }

// Per-frame reset — re-arms the single sg_update_image allowed for the font atlas.
// Called at the top of every bracket. Only the FIRST bracket of a frame does the per-frame
// work; `void2dFrameEnd` at sg_commit is what closes the frame and lets the next one through.
void void2dFrameBegin(void) {
	s_bracketsThisFrame++;
	if (s_bracketsThisFrame > VOID2D_BRACKETS_BEFORE_COMPLAINT && !s_frameEndMissingReported) {
		s_frameEndMissingReported = 1;
		fprintf(stderr,
			"void2d: %d brackets since the last void2dFrameEnd - is it being called after sg_commit? "
			"until it is, the glyph atlas will not upload and retired resources will not be freed\n",
			s_bracketsThisFrame);
	}
	if (s_frameOpen) { return; }
	s_frameOpen = 1;
	s_atlasUpdated = false;
	releaseRetiredAtlases();
	releaseRetiredBuffers();
	s_drawCallCount = 0;
	s_uploadCount = 0;
	s_uploadBytes = 0;
	s_frameVertexBytes = 0;
}

// Runs immediately after sg_commit, as the commit hook void2dSetup registers. Everything sokol
// resets per frame - the append cursor above all - becomes safe to reset here and nowhere else.
void void2dFrameEnd(void) {
	s_frameOpen = 0;
	s_bracketsThisFrame = 0;
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
                        const float *vertices, int vertexCount,
                        const float *spriteInstances, int spriteInstanceCount,
                        const float *uiInstances, int uiInstanceCount) {
	s_frameUploaded = 0;
	s_frameBaseOffset = 0;
	s_spriteInstanceBase = 0;
	s_spriteInstanceCount = spriteInstanceCount;
	s_uiInstanceBase = 0;
	s_uiInstanceCount = uiInstanceCount;

	size_t vertexBytes = (size_t)vertexCount * VERTEX_FLOATS * sizeof(float);
	size_t spriteBytes = (size_t)spriteInstanceCount * sizeof(void2dSpriteInstance);
	size_t uiBytes = (size_t)uiInstanceCount * sizeof(void2dUiInstance);
	// Against the FRAME's total, not this bracket's. sg_append_buffer accumulates until
	// sg_commit, so a buffer sized for one bracket overflows on the second - and sokol's
	// overflow copies nothing, returns a start position anyway, and leaves every draw in that
	// bracket reading whatever was there before. Silent in release. Same mechanism as the
	// "per-frame vertex cap" defect this phase closed one layer down.
	size_t frameBytes = (size_t)s_frameVertexBytes + vertexBytes + spriteBytes + uiBytes;
	if (frameBytes > (size_t)VOID2D_MAX_BUFFER_BYTES) {
		// A dropped frame with an error, never a silent truncation. The old path let
		// sg_append_buffer run past the end and the rest of the scene simply vanished.
		s_droppedFrames++;
		fprintf(stderr, "void2d: frame needs %zu bytes of geometry, cap is %d — frame dropped\n",
			frameBytes, VOID2D_MAX_BUFFER_BYTES);
		return 0;
	}
	ensureVertexBuffer((int)frameBytes);
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
	// The sprite record and void2dSpriteInstance are the same 64 bytes in the same order, so
	// the frame's instances append as they were recorded - no pack, no staging copy. A second
	// append rather than one concatenated upload, because concatenating would mean copying the
	// whole vertex stream through a staging buffer to save a call that costs nothing.
	if (spriteBytes > 0) {
		sg_range data = { .ptr = spriteInstances, .size = spriteBytes };
		s_spriteInstanceBase = sg_append_buffer(s_vbuf, &data);
		s_uploadCount++;
		s_uploadBytes += (int)spriteBytes;
	}
	if (uiBytes > 0) {
		if (uiInstanceCount > s_uiStageCap) {
			void2dUiInstance *grown = (void2dUiInstance *)realloc(
				s_uiStage, (size_t)uiInstanceCount * sizeof(void2dUiInstance));
			if (!grown) {
				s_droppedFrames++;
				fprintf(stderr, "void2d: no room to stage %d UI instances — frame dropped\n",
					uiInstanceCount);
				return 0;
			}
			s_uiStage = grown;
			s_uiStageCap = uiInstanceCount;
		}
		for (int i = 0; i < uiInstanceCount; i++) {
			const float *rec = uiInstances + (size_t)i * UI_REC_FLOATS;
			void2dUiInstance *dst = s_uiStage + i;
			memcpy(dst->affine, rec, 24 * sizeof(float));
			dst->colorFill = packColor(rec + 24);
			dst->colorBorder = packColor(rec + 28);
			dst->colorExtra = packColor(rec + 32);
		}
		sg_range data = { .ptr = s_uiStage, .size = uiBytes };
		s_uiInstanceBase = sg_append_buffer(s_vbuf, &data);
		s_uploadCount++;
		s_uploadBytes += (int)uiBytes;
	}
	if (vertexBytes > 0 || spriteBytes > 0 || uiBytes > 0) { s_frameVertexBytes = (int)frameBytes; }
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
static void copyClipParams(float *clipU, float *clipV, const float *cmd) {
	memcpy(clipU, cmd + CMD_CLIP_U_X, 4 * sizeof(float));
	memcpy(clipV, cmd + CMD_CLIP_U_X + 4, 4 * sizeof(float));
}

// One instanced sprite run: the unit quad at slot 0, this run's instances at slot 1, one
// sg_draw for the whole run. The sprite program carries no colour pipeline, so a node with a
// colorMatrix, colorAdd or colorKey never reaches here - the emitter keeps it on the vertex
// path and records the break, which is what makes that decision visible in a T1 snapshot
// rather than inferred from a pixel.
static void drawSpriteRun(const float *cmd, int blend, int rt, uint32_t view,
                          float fbW, float fbH, uint32_t *lastPipeline, int *scissorApplied,
                          int *paramsValid, int *fxValid) {
	int count = (int)cmd[CMD_INSTANCE_COUNT];
	if (count <= 0) { return; }

	sg_pipeline pip = (rt ? s_spritePipsRT : s_spritePips)[blend];
	if (pip.id != *lastPipeline) {
		sg_apply_pipeline(pip);
		*lastPipeline = pip.id;
		*scissorApplied = 0;
		*paramsValid = 0;
		*fxValid = 0;
	}

	sg_bindings b = {0};
	b.vertex_buffers[0] = s_unitQuad;
	b.vertex_buffers[1] = s_vbuf;
	b.vertex_buffer_offsets[1] = s_spriteInstanceBase
		+ (int)cmd[CMD_INSTANCE_OFFSET] * (int)sizeof(void2dSpriteInstance);
	b.views[VIEW_spriteTex] = (sg_view){ .id = view };
	int smpIndex = (int)cmd[CMD_SAMPLER];
	if (smpIndex < 0 || smpIndex >= SMP_COUNT) { smpIndex = 2; }
	b.samplers[SMP_spriteSmp] = s_smp[smpIndex];
	sg_apply_bindings(&b);

	if (!*scissorApplied) {
		applyScissor(cmd, fbW, fbH);
		*scissorApplied = 1;
	}

	sprite_params_t sp = {0};
	sp.viewport[0] = fbW;
	sp.viewport[1] = fbH;
	bool isRT = voidIsRenderTargetView(view);
	sp.viewport[2] = (isRT && !s_originTopLeft) ? 1.0f : 0.0f;
	sp.viewport[3] = isRT ? 1.0f : 0.0f;
	copyClipParams(sp.clipU, sp.clipV, cmd);
	sg_range u = { .ptr = &sp, .size = sizeof(sp) };
	sg_apply_uniforms(UB_sprite_params, &u);

	sg_draw(0, 6, count);
	s_drawCallCount++;
}

// One unified-UI run: the unit quad at slot 0, this run's instances at slot 1, one sg_draw
// for the whole run. Every mode shares this program, which is the point — a card, its label
// and its image are one draw instead of three, and the mode lives in a per-instance lane
// rather than in a pipeline.
//
// Like the sprite program it carries no colour pipeline, so a node with a colorMatrix,
// colorAdd or colorKey stays on the vertex path and records the break.
static void drawUiRun(const float *cmd, int blend, int rt, uint32_t view,
                      float fbW, float fbH, uint32_t *lastPipeline, int *scissorApplied,
                      int *paramsValid, int *fxValid) {
	int count = (int)cmd[CMD_INSTANCE_COUNT];
	if (count <= 0) { return; }

	sg_pipeline pip = (rt ? s_uiPipsRT : s_uiPips)[blend];
	if (pip.id != *lastPipeline) {
		sg_apply_pipeline(pip);
		*lastPipeline = pip.id;
		*scissorApplied = 0;
		*paramsValid = 0;
		*fxValid = 0;
	}

	sg_bindings b = {0};
	b.vertex_buffers[0] = s_unitQuad;
	b.vertex_buffers[1] = s_vbuf;
	b.vertex_buffer_offsets[1] = s_uiInstanceBase
		+ (int)cmd[CMD_INSTANCE_OFFSET] * (int)sizeof(void2dUiInstance);
	b.views[VIEW_uiTex] = (sg_view){ .id = view };
	int smpIndex = (int)cmd[CMD_SAMPLER];
	if (smpIndex < 0 || smpIndex >= SMP_COUNT) { smpIndex = 2; }
	b.samplers[SMP_uiSmp] = s_smp[smpIndex];
	sg_apply_bindings(&b);

	if (!*scissorApplied) {
		applyScissor(cmd, fbW, fbH);
		*scissorApplied = 1;
	}

	ui_params_t up = {0};
	up.viewport[0] = fbW;
	up.viewport[1] = fbH;
	up.viewport[2] = (voidIsRenderTargetView(view) && !s_originTopLeft) ? 1.0f : 0.0f;
	copyClipParams(up.clipU, up.clipV, cmd);
	sg_range u = { .ptr = &up, .size = sizeof(up) };
	sg_apply_uniforms(UB_ui_params, &u);

	sg_draw(0, 6, count);
	s_drawCallCount++;
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
			// It applied its own pipeline and bindings, so everything this loop remembers about
			// what is bound is now wrong. A Draw after a Blur in the same pass would otherwise
			// skip its own `sg_apply_pipeline` and draw the quad with the blur pipeline.
			lastPipeline = 0; paramsValid = 0; fxValid = 0; scissorApplied = 0;
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

		int blend = (int)cmd[CMD_BLEND];
		if (blend < 0 || blend >= VOID2D_BLEND_COUNT) blend = 0;
		uint32_t view = (uint32_t)cmd[CMD_VIEW];
		if (view == 0) view = s_whiteView.id;

		// The pipeline branch comes BEFORE the vertex-count guard: a sprite run carries an
		// instance range and a vertex count of zero, so testing the vertex count first would
		// skip every instanced draw and the frame would simply be missing its sprites.
		int rt = cmd[CMD_RT_MODE] != 0.0f;
		if ((int)cmd[CMD_PIPELINE] == PIPELINE_SPRITE) {
			drawSpriteRun(cmd, blend, rt, view, fbW, fbH, &lastPipeline, &scissorApplied,
				&paramsValid, &fxValid);
			continue;
		}
		if ((int)cmd[CMD_PIPELINE] == PIPELINE_UI) {
			drawUiRun(cmd, blend, rt, view, fbW, fbH, &lastPipeline, &scissorApplied,
				&paramsValid, &fxValid);
			continue;
		}

		int count = (int)cmd[CMD_VERTEX_COUNT];
		if (count <= 0) continue;
		sg_pipeline pip = (rt ? s_pipsRT : s_pips)[blend];
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
		// One lookup, not two: `voidIsRenderTargetView` is a linear scan of the 16-slot table.
		bool isRT = voidIsRenderTargetView(view);
		vp.viewport[2] = (isRT && !s_originTopLeft) ? 1.0f : 0.0f;
		vp.viewport[3] = (isRT
			&& addR == 0.0f && addG == 0.0f && addB == 0.0f
			&& matrix[0] == 1.0f && matrix[5] == 1.0f && matrix[10] == 1.0f) ? 1.0f : 0.0f;
		vp.model0[0] = 1.0f; vp.model0[3] = 1.0f;   // the stream is already in world space
		vp.globalColor[0] = 1.0f; vp.globalColor[1] = 1.0f; vp.globalColor[2] = 1.0f; vp.globalColor[3] = 1.0f;
		copyClipParams(vp.clipU, vp.clipV, cmd);
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
			memcpy(fxu.gradientMeta, fx + 24, sizeof(fxu.gradientMeta));
			memcpy(fxu.gradientParams, fx + 28, sizeof(fxu.gradientParams));
			memcpy(fxu.gradientColor0, fx + 32, sizeof(fxu.gradientColor0));
			memcpy(fxu.gradientColor1, fx + 36, sizeof(fxu.gradientColor1));
			memcpy(fxu.gradientColor2, fx + 40, sizeof(fxu.gradientColor2));
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
	if (!s_fons) ensureFons();
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

// fontstash reserves a 2x2 opaque block at the atlas origin on create and on reset, and
// fonsExpandAtlas preserves what is already placed, so it survives a grow. That block is what
// lets a solid card sample the GLYPH atlas instead of the 1x1 white image - and a card and a
// label that share a view no longer break each other's batch, which is half of what collapses
// P2's 20 000 draws.
//
// The UV is the centre of that block and therefore moves when the atlas grows; read it per
// frame, never cache it. void2dAtlasGen() already bumps on a resize for the same reason.
float void2dWhiteTexelU(void) { return s_atlasW > 0 ? 1.0f / (float)s_atlasW : 0.0f; }
float void2dWhiteTexelV(void) { return s_atlasH > 0 ? 1.0f / (float)s_atlasH : 0.0f; }

// Whether that block is ACTUALLY opaque, read out of fontstash rather than taken on trust
// from the comment beside its allocation. Returns 0 with no context, which is what T0 sees.
int void2dWhiteTexelOk(void) {
	if (!s_fons) { return 0; }
	int w = 0, h = 0;
	const unsigned char *tex = fonsGetTextureData(s_fons, &w, &h);
	if (!tex || w < 2 || h < 2) { return 0; }
	return tex[0] == 0xff && tex[1] == 0xff && tex[w] == 0xff && tex[w + 1] == 0xff;
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
