// Void 2D — thin GPU door primitives (see batcher.h). Batcher logic is in draw.ms.

#include "batcher.h"
#include "../sokol/bridge.h"
#include "../gpu/door.h"
#include "shader2dSlots.h"
#include "instanceLayout.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stddef.h>
#include <math.h>
#include "glyph.h"
#ifdef VOID_PROFILER
#include "frameClock.h"
#endif

#define VOID2D_BLEND_COUNT 12
#define VOID2D_PROGRAM_COUNT 4

// One growing vertex buffer for the whole frame, replacing both the fixed 65 536-vertex
// stream and the per-node static buffers (VOID2D.md "Known defects", closed here). Growth is
// max(2x, next power of two) with no shrink, a hard cap, and a dropped frame with an error
// past it (GPUI.md:63) — never a silent truncation, which is what the old
// sokol append overflow was.
#define VOID2D_INITIAL_BUFFER_BYTES (1 << 20)
#define VOID2D_MAX_BUFFER_BYTES     (192 << 20)

static uint32_t s_vbuf;
static int s_vbufBytes;
static int s_frameBaseOffset;   // where this frame's vertices start in s_vbuf
static int s_frameUploaded;     // 0 when the frame was dropped, and then nothing may draw
static uint32_t s_pipelines[VOID2D_PROGRAM_COUNT][2][VOID2D_BLEND_COUNT];
static int s_uiInstanceBase;          // where this frame's UI instances start in s_vbuf
static int s_uiInstanceCount;
static uint32_t s_unitQuad;          // six corners (0,0)..(1,1), made once, stepped per vertex
static int s_spriteInstanceBase;      // where this frame's sprite instances start in s_vbuf
static int s_spriteInstanceCount;
static uint32_t s_srcVertex;
static uint32_t s_srcSprite;
static uint32_t s_srcUi;
static int s_srcVertexBase;
static int s_srcSpriteBase;
static int s_srcUiBase;
static const float *s_scopes;
static int s_scopeCount;

void void2dSetScopes(const float *scopes, int count) {
	s_scopes = scopes;
	s_scopeCount = count;
}
// The door's origin convention does not change after setup, and it was being queried twice per
// draw command - 40 000 times a frame on the UI bench whose `present` this phase reports as
// not met.
static bool s_originTopLeft;
static float s_dpiScale = 1.0f;                    // framebuffer / logical pixel ratio (retina = 2.0)
static uint32_t s_fsQuad;                        // fullscreen quad (pos2+uv2) for filter passes
static uint32_t s_whiteView;
// Indexed by `smooth * 2 + tileWrap`, the packing displayList.ms `samplerIndex` writes into
// CMD_SAMPLER. Clamp is the default: a tile is a sub-rect of an atlas, so REPEAT on a tile
// that does not fill its page wraps in a neighbour's pixels at the seam.
#define SMP_COUNT 4
#define SAMPLER_NEAREST 0
#define SAMPLER_LINEAR 1
#define SAMPLER_CLAMP 0
#define SAMPLER_REPEAT 1
#define PIXEL_FORMAT_RGBA8 2
static uint32_t s_smp[SMP_COUNT];

static uint32_t s_pageImg[VOID2D_MAX_GLYPH_PAGES];
static uint32_t s_pageView[VOID2D_MAX_GLYPH_PAGES];
static unsigned int s_pageGen[VOID2D_MAX_GLYPH_PAGES];
static int s_atlasMade;
static int s_glyphUploads;
static float s_textGamma[4];
static float s_textContrast = 1.0f;
static int s_glyphUploadBytes;
// Buffers this module owns, counted where the door is actually called. It used to be
// `return 3` - a literal, gated in tests/bench/baseline.json against the literal 3, so the
// assertion compared a constant to a constant and would have kept passing if every Label
// allocated a buffer again. It also miscounted: two of the three were buffers and the third
// was the font image.
static int s_buffersMade;
static int s_buffersFreed;

// A GPU FRAME, which is not a bracket. `begin2d`/`flushTargets` is a bracket and a frame may
// hold several - src/examples/renderer2d.ms runs two, the manual filter targets and then the
// scene - while the door resets a buffer's append cursor only once per frame, at submit
// (sokol's rule, `sokol_gfx.h:27551`). Three things are therefore per frame and were being
// re-armed per bracket: the append budget, the one-texture-update-per-image rule, and the counters.
static int s_frameOpen;
// Brackets opened since the last void2dFrameEnd. A frame legitimately holds a few - the demo
// runs two - so this is not an error until it is absurd. void2dSetup registers void2dFrameEnd
// as the bridge's commit hook; any direct doorSubmitFrame call bypasses it and leaves s_frameOpen
// latched, so glyph pages stop uploading and retired resources stop being freed. Keep the
// counter loud because the visible failure appears several layers from the missing frame end.
static int s_bracketsThisFrame;
static int s_frameEndMissingReported;
static int s_frameSerial;
#define VOID2D_BRACKETS_BEFORE_COMPLAINT 16
static int s_frameVertexBytes;   // bytes appended so far this FRAME, across every bracket

// A vertex buffer that grew mid-frame cannot be destroyed on the spot: an earlier bracket's
// draws are already encoded against it. Same frame-linear discipline as the retired atlases.
#define VOID2D_MAX_RETIRED_BUFFERS 8
static uint32_t s_retiredBuf[VOID2D_MAX_RETIRED_BUFFERS];
static int s_retiredBufCount;
static uint32_t *s_closedBuf;
static int s_closedBufCount;
static int s_closedBufCap;

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
#define CMD_VIEW_HIGH       30
#define CMD_SCOPE           31
#define SCOPE_FLOATS        8

#define PIPELINE_VERTEX     0
#define PIPELINE_SPRITE     1
#define PIPELINE_UI         2
#define PIPELINE_BLUR       3

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
int void2dVertexBufferBytes(void) { return s_vbufBytes; }
int void2dDroppedFrames(void) { return s_droppedFrames; }

#ifdef VOID_PROFILER
static int s_frameUiInstances;
static int s_frameSpriteInstances;
int void2dProfilerCompiled(void) { return 1; }
#else
int void2dProfilerCompiled(void) { return 0; }
#endif
void void2dFailPendingTargets(void) {
	fprintf(stderr, "void2d: end2d with render-target commands pending; call flushTargets first\n");
	abort();
}

// Every buffer and image this layer holds: the one vertex buffer, the fullscreen quad
// the filter passes draw, and the font atlas image. Constant in the node count, which is the
// whole point of the change (VOID2D.md P1 exit).
// Made minus freed, at the sites that make and free. Two in a steady frame: the growing
// vertex buffer and the fullscreen quad the filter passes draw. It goes UP if anything starts
// allocating per node again, which is the whole reason the number is gated.
int void2dBuffersAlive(void) { return s_buffersMade - s_buffersFreed; }

int void2dAtlasImagesAlive(void) { return s_atlasMade; }
int void2dGlyphUploadCount(void) { return s_glyphUploads; }
void void2dSetTextGamma(float r0, float r1, float r2, float r3, float contrast) {
	s_textGamma[0] = r0; s_textGamma[1] = r1; s_textGamma[2] = r2; s_textGamma[3] = r3;
	s_textContrast = contrast;
}
int void2dGlyphUploadBytes(void) { return s_glyphUploadBytes; }

// The UI record is 36 floats and the GPU instance is 108 bytes, so unlike the sprite stream
// this one cannot be uploaded as it was recorded — the three colours pack to UBYTE4N on the
// way in. That is one staging buffer, grown and never shrunk, rather than bit-twiddling in
// the emitter where a Vec<float32> would lose the low bits to the mantissa anyway.
static void2dUiInstance *s_uiStage;
static int s_uiStageCap;

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

void void2dCopyFloats(float *dst, const float *src, int count) {
	if (count > 0) { memcpy(dst, src, (size_t)count * sizeof(float)); }
}

uint32_t void2dCommandView(const float *cmd) {
	return (uint32_t)cmd[CMD_VIEW] | ((uint32_t)cmd[CMD_VIEW_HIGH] << 16);
}

int void2dLayoutCheck(int commandFloats, int effectFloats, int vertexFloats,
                      int kindField, int breakField, int vertexOffsetField, int vertexCountField,
                      int viewField, int viewHighField, int blendField, int samplerField,
                      int effectField,
                      int samplerCount, int clearRField,
                      int clipXField, int clipUField, int arg0Field, int rtModeField,
                      int kindDraw, int kindScissor, int kindBlur,
                      int kindTargetBegin, int kindTargetEnd,
                      int programVertex, int programSprite, int programUi, int programBlur,
                      int programCount, int blendCount) {
	return programVertex == PIPELINE_VERTEX
		&& programSprite == PIPELINE_SPRITE
		&& programUi == PIPELINE_UI
		&& programBlur == PIPELINE_BLUR
		&& programCount == VOID2D_PROGRAM_COUNT
		&& blendCount == VOID2D_BLEND_COUNT
		&& commandFloats == CMD_FLOATS
		&& effectFloats == EFFECT_FLOATS
		&& vertexFloats == VERTEX_FLOATS
		&& kindField == CMD_KIND
		&& breakField == CMD_BREAK
		&& vertexOffsetField == CMD_VERTEX_OFFSET
		&& vertexCountField == CMD_VERTEX_COUNT
		&& viewField == CMD_VIEW
		&& viewHighField == CMD_VIEW_HIGH
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
		&& clearRField == CMD_CLEAR_R;
}


// Free resources retained through the preceding commit; deferred backends may still read them
// until that frame has been submitted.
static void releaseRetiredBuffers(void) {
	for (int i = 0; i < s_retiredBufCount; i++) {
		doorDestroyBuffer(s_retiredBuf[i]);
		s_buffersFreed++;
	}
	s_retiredBufCount = 0;
	for (int i = 0; i < s_closedBufCount; i++) {
		doorDestroyBuffer(s_closedBuf[i]);
		s_buffersFreed++;
	}
	s_closedBufCount = 0;
}

static void retireClosedBuffer(uint32_t buf, int list) {
	if (s_closedBufCount == s_closedBufCap) {
		int want = s_closedBufCap > 0 ? s_closedBufCap * 2 : 8;
		uint32_t *grown = (uint32_t *)realloc(s_closedBuf, (size_t)want * sizeof(uint32_t));
		if (!grown) {
			fprintf(stderr, "void2d: no room to retire the buffers of closed list %d\n", list);
			abort();
		}
		s_closedBuf = grown;
		s_closedBufCap = want;
	}
	s_closedBuf[s_closedBufCount++] = buf;
}




// Allocate, or reallocate, the one vertex buffer. The door cannot resize a buffer, so growth is
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

// A buffer the door refused is a device that cannot draw this layer; it stops here, naming the
// buffer, rather than leaving every later draw to read id 0.
static uint32_t makeBuffer(int32_t usage, const void *data, size_t bytes, const char *what) {
	const uint32_t id = doorMakeBuffer(usage, (const uint8_t *)data, data ? (int64_t)bytes : 0, (int64_t)bytes);
	if (id == 0) {
		fprintf(stderr, "void2d: the door made no %zu-byte %s buffer\n", bytes, what);
		abort();
	}
	return id;
}

static int ensureVertexBuffer(int bytes) {
	int want = void2dGrowthTarget(s_vbufBytes, bytes);
	if (want <= s_vbufBytes) return 1;
	if (s_vbuf) {
		// Doubling from 1 MiB through the 192 MiB cap can retire at most eight buffers in
		// one frame. Keep every one alive until commit; destroying an encoded buffer here is
		// a use-after-free on deferred backends.
		if (s_retiredBufCount >= VOID2D_MAX_RETIRED_BUFFERS) {
			fprintf(stderr, "void2d: more than %d vertex-buffer growths in one frame — frame dropped\n",
				VOID2D_MAX_RETIRED_BUFFERS);
			return 0;
		}
		s_retiredBuf[s_retiredBufCount] = s_vbuf;
		s_retiredBufCount++;
	}
	s_vbuf = makeBuffer(DOOR_BUFFER_VERTEX | DOOR_BUFFER_STREAM, NULL, (size_t)want, "frame vertex");
	s_buffersMade++;
	s_vbufBytes = want;
	return 1;
}


void void2dSetPipeline(int32_t program, int32_t target, int32_t blend, uint32_t pipeline) {
	if (program < 0 || program >= VOID2D_PROGRAM_COUNT || target < 0 || target > 1
		|| blend < 0 || blend >= VOID2D_BLEND_COUNT) {
		fprintf(stderr, "void2d: no pipeline slot for program %d, target %d, blend %d\n",
			program, target, blend);
		abort();
	}
	s_pipelines[program][target][blend] = pipeline;
}

static int sourceOf(const float *cmd) {
	const int source = (int)cmd[CMD_SAMPLER];
	if (source < 0 || source >= 2 * SMP_COUNT) {
		fprintf(stderr, "void2d: a command's sampler field is %d, outside 0..%d\n", source, 2 * SMP_COUNT - 1);
		abort();
	}
	return source;
}

static int samplerOf(const float *cmd) {
	return sourceOf(cmd) % SMP_COUNT;
}

static bool premultipliedSource(const float *cmd) {
	return sourceOf(cmd) >= SMP_COUNT;
}

static bool sampledTarget(uint32_t view) {
	return doorViewIsColorAttachment(view) != 0;
}

static uint32_t pipelineAt(int program, int target, int blend) {
	const bool inRange = program >= 0 && program < VOID2D_PROGRAM_COUNT
		&& target >= 0 && target <= 1 && blend >= 0 && blend < VOID2D_BLEND_COUNT;
	const uint32_t id = inRange ? s_pipelines[program][target][blend] : 0;
	if (id == 0) {
		fprintf(stderr, "void2d: replay reached program %d, %s target, blend %d, "
			"which flushTargets did not prepare\n",
			program, target ? "offscreen" : "screen", blend);
		abort();
	}
	return id;
}

static int s_generation;

static void makeContextResources(void) {
	(void)ensureVertexBuffer(VOID2D_INITIAL_BUFFER_BYTES);

	s_originTopLeft = doorOriginTopLeft() != 0;

	// Six corners rather than four plus an index buffer. VOID2D.md records that the two have
	// not been compared on a Mali or an Adreno; until they have, this is one 48-byte static
	// buffer and no index path to get wrong.
	static const float unit[12] = {
		0.0f, 0.0f,  1.0f, 0.0f,  1.0f, 1.0f,
		0.0f, 0.0f,  1.0f, 1.0f,  0.0f, 1.0f,
	};
	s_unitQuad = makeBuffer(DOOR_BUFFER_VERTEX, unit, sizeof(unit), "unit quad");
	s_buffersMade++;

	static const float fsq[24] = {
		-1.0f, -1.0f, 0.0f, 0.0f,   1.0f, -1.0f, 1.0f, 0.0f,   1.0f, 1.0f, 1.0f, 1.0f,
		-1.0f, -1.0f, 0.0f, 0.0f,   1.0f,  1.0f, 1.0f, 1.0f,  -1.0f, 1.0f, 0.0f, 1.0f,
	};
	s_fsQuad = makeBuffer(DOOR_BUFFER_VERTEX, fsq, sizeof(fsq), "fullscreen quad");
	s_buffersMade++;

	s_whiteView = voidMakeView(voidMakeImage(NULL, 0, 0));
	// Four samplers, made once: smooth * 2 + tileWrap. They are four objects and not a
	// mutated one because samplers are immutable, and four is a constant cost that does not
	// grow with the scene.
	for (int i = 0; i < SMP_COUNT; i++) {
		int smooth = (i & 2) != 0;
		int wrap = (i & 1) != 0;
		s_smp[i] = doorMakeSampler(smooth ? SAMPLER_LINEAR : SAMPLER_NEAREST, wrap ? SAMPLER_REPEAT : SAMPLER_CLAMP);
	}
	s_generation = doorContextGeneration();
}

void void2dSetup(void) {
	voidSetCommitHook(void2dFrameEnd);
	makeContextResources();
}

static void adoptContext(void);


uint32_t void2dWhiteView(void) { return s_whiteView; }
static void dropReleasedPageImage(int page) {
	if (s_pageImg[page] == 0 || s_pageGen[page] == void2dGlyphPageGeneration(page)) { return; }
	doorDestroyView(s_pageView[page]);
	doorDestroyImage(s_pageImg[page]);
	s_pageImg[page] = 0;
	s_pageView[page] = 0;
}

uint32_t void2dGlyphPageView(int page) {
	if (page < 0 || page >= VOID2D_MAX_GLYPH_PAGES || !doorValid()) { return 0; }
	dropReleasedPageImage(page);
	if (s_pageImg[page] == 0) {
		unsigned int generation = void2dGlyphPageGeneration(page);
		if (generation == 0) { return 0; }
		int size = void2dGlyphPageSize(page);
		if (size <= 0) { return 0; }
		int kind = void2dGlyphPageKind(page);
		if (kind != VOID2D_PAGE_COVERAGE && kind != VOID2D_PAGE_SDF && kind != VOID2D_PAGE_RGBA &&
			kind != VOID2D_PAGE_MASK) {
			fprintf(stderr, "void2d: no image format for glyph page %d of kind %d\n", page, kind);
			return 0;
		}
		s_pageImg[page] = doorMakeTexture(size, size,
			kind == VOID2D_PAGE_RGBA ? PIXEL_FORMAT_RGBA8 : DOOR_PIXEL_FORMAT_R8, NULL, 0);
		s_pageView[page] = voidMakeView(s_pageImg[page]);
		s_pageGen[page] = generation;
		s_atlasMade++;
	}
	return s_pageView[page];
}

static int glyphPageViewKind(uint32_t view) {
	if (view == 0) { return -1; }
	for (int i = 0; i < VOID2D_MAX_GLYPH_PAGES; i++) {
		if (s_pageView[i] == view) {
			int kind = void2dGlyphPageKind(i);
			return kind < 0 ? -2 : kind;
		}
	}
	return -1;
}

static float glyphPageViewMode(uint32_t view) {
	int kind = glyphPageViewKind(view);
	switch (kind) {
	case -1: return 0.0f;
	case VOID2D_PAGE_COVERAGE: return 1.0f;
	case VOID2D_PAGE_SDF: return 2.0f;
	case VOID2D_PAGE_MASK: return 1.0f;

	case VOID2D_PAGE_RGBA: return 0.0f;
	default:
		fprintf(stderr, "void2d: glyph page view %u of kind %d has no shader mode\n", view, kind);
		abort();
	}
}

int void2dScissorMin(float edge, float scale) {
	return (int)floorf(edge * scale);
}

int void2dScissorMax(float edge, float scale) {
	return (int)ceilf(edge * scale);
}

// A clip is a command in the stream now, applied here during replay rather than by the tree
// walk. The whole viewport is w == 0, which is how displayList.ms records "no clip".
static const float *scopeOf(const float *cmd) {
	int scope = (int)cmd[CMD_SCOPE];
	if (scope < 0 || scope >= s_scopeCount || !s_scopes) { return NULL; }
	return s_scopes + (size_t)scope * SCOPE_FLOATS;
}

static void applyScissor(const float *cmd, float fbW, float fbH) {
	// Floor the near edge and ceil the far edge in device pixels. Truncating x/y/w/h
	// independently can discard a pixel the exact clip planes accept.
	float targetScale = cmd[CMD_RT_MODE];
	float scale = targetScale != 0.0f ? targetScale : s_dpiScale;
	int limitW = void2dScissorMax(fbW, scale);
	int limitH = void2dScissorMax(fbH, scale);
	float x = cmd[CMD_CLIP_X];
	float y = cmd[CMD_CLIP_Y];
	float w = cmd[CMD_CLIP_W];
	float h = cmd[CMD_CLIP_H];
	const float *scope = scopeOf(cmd);
	if (scope) {
		if (w > 0.0f && h > 0.0f) {
			float left = x + scope[0] > scope[2] ? x + scope[0] : scope[2];
			float top = y + scope[1] > scope[3] ? y + scope[1] : scope[3];
			float right = x + scope[0] + w < scope[2] + scope[4] ? x + scope[0] + w : scope[2] + scope[4];
			float bottom = y + scope[1] + h < scope[3] + scope[5] ? y + scope[1] + h : scope[3] + scope[5];
			x = left;
			y = top;
			w = right - left;
			h = bottom - top;
		} else {
			x = scope[2];
			y = scope[3];
			w = scope[4];
			h = scope[5];
		}
		if (w <= 0.0f || h <= 0.0f) {
			doorApplyScissor(0, 0, 0, 0);
			return;
		}
	}
	if (w <= 0.0f || h <= 0.0f) {
		doorApplyScissor(0, 0, limitW, limitH);
		return;
	}
	int x0 = void2dScissorMin(x, scale);
	int y0 = void2dScissorMin(y, scale);
	int x1 = void2dScissorMax(x + w, scale);
	int y1 = void2dScissorMax(y + h, scale);
	if (x0 < 0) x0 = 0;
	if (y0 < 0) y0 = 0;
	if (x0 > limitW) x0 = limitW;
	if (y0 > limitH) y0 = limitH;
	if (x1 < 0) x1 = 0;
	if (y1 < 0) y1 = 0;
	if (x1 > limitW) x1 = limitW;
	if (y1 > limitH) y1 = limitH;
	if (x1 < x0) x1 = x0;
	if (y1 < y0) y1 = y0;
	doorApplyScissor(x0, y0, x1 - x0, y1 - y0);
}

void void2dSetDpiScale(float scale) { if (scale > 0.0f) s_dpiScale = scale; }

// Per-frame reset — re-arms the single texture update allowed for the font atlas.
// Called at the top of every bracket. Only the FIRST bracket of a frame does the per-frame
// work; `void2dFrameEnd` at submit is what closes the frame and lets the next one through.
void void2dFrameBegin(void) {
	s_bracketsThisFrame++;
	if (s_bracketsThisFrame > VOID2D_BRACKETS_BEFORE_COMPLAINT && !s_frameEndMissingReported) {
		s_frameEndMissingReported = 1;
		fprintf(stderr,
			"void2d: %d brackets since the last void2dFrameEnd - is it being called after the submit? "
			"until it is, the glyph atlas will not upload and retired resources will not be freed\n",
			s_bracketsThisFrame);
	}
	if (s_frameOpen) { return; }
	s_frameOpen = 1;
#ifdef VOID_PROFILER
	voidProfileBegin();
	s_frameUiInstances = 0;
	s_frameSpriteInstances = 0;
#endif
	adoptContext();
	void2dGlyphPagesFrameBegin();
	releaseRetiredBuffers();
	s_drawCallCount = 0;
	s_uploadCount = 0;
	s_uploadBytes = 0;
	s_glyphUploads = 0;
	s_glyphUploadBytes = 0;
	s_frameVertexBytes = 0;
}

// Runs immediately after doorSubmitFrame, as the commit hook void2dSetup registers. Everything the
// door resets per frame - the append cursor above all - becomes safe to reset here and nowhere else.
void void2dFrameEnd(void) {
	s_frameOpen = 0;
	s_bracketsThisFrame = 0;
	s_frameSerial++;
#ifdef VOID_PROFILER
	int32_t counters[VOID_COUNTER_VOID2D_SLOTS];
	counters[VOID_COUNTER_DRAWS] = s_drawCallCount;
	counters[VOID_COUNTER_UI_INSTANCES] = s_frameUiInstances;
	counters[VOID_COUNTER_SPRITE_INSTANCES] = s_frameSpriteInstances;
	counters[VOID_COUNTER_UPLOAD_BYTES] = s_uploadBytes;
	counters[VOID_COUNTER_UPLOADS] = s_uploadCount;
	voidProfileCommit(s_frameSerial, counters);
#endif
}

int void2dFrameSerial(void) { return s_frameSerial; }

typedef struct {
	uint32_t srcVertex;
	uint32_t srcSprite;
	uint32_t srcUi;
	int srcVertexBase;
	int srcSpriteBase;
	int srcUiBase;
	int spriteInstanceCount;
	int uiInstanceCount;
	int frameUploaded;
	int frameSerial;
	int prepared;
	int live;
} void2dPreparedContext;

static void2dPreparedContext *s_contexts;
static size_t s_contextCap;

void void2dRememberContext(int id, int live) {
	if (id < 0) {
		fprintf(stderr, "void2d: cannot remember context %d — invalid id\n", id);
		abort();
	}
	if ((size_t)id >= s_contextCap) {
		size_t want = s_contextCap > 0 ? s_contextCap : 4;
		while (want <= (size_t)id) {
			if (want > SIZE_MAX / 2) {
				fprintf(stderr, "void2d: cannot remember context %d — metadata capacity overflow\n", id);
				abort();
			}
			want *= 2;
		}
		if (want > SIZE_MAX / sizeof(void2dPreparedContext)) {
			fprintf(stderr, "void2d: cannot remember context %d — metadata size overflow\n", id);
			abort();
		}
		void2dPreparedContext *grown = (void2dPreparedContext *)realloc(
			s_contexts, want * sizeof(void2dPreparedContext));
		if (!grown) {
			fprintf(stderr, "void2d: cannot remember context %d — no room for prepared bindings\n", id);
			abort();
		}
		memset(grown + s_contextCap, 0,
			(want - s_contextCap) * sizeof(void2dPreparedContext));
		s_contexts = grown;
		s_contextCap = want;
	}
	void2dPreparedContext *c = &s_contexts[id];
	c->srcVertex = s_srcVertex;
	c->srcSprite = s_srcSprite;
	c->srcUi = s_srcUi;
	c->srcVertexBase = s_srcVertexBase;
	c->srcSpriteBase = s_srcSpriteBase;
	c->srcUiBase = s_srcUiBase;
	c->spriteInstanceCount = s_spriteInstanceCount;
	c->uiInstanceCount = s_uiInstanceCount;
	c->frameUploaded = s_frameUploaded;
	c->frameSerial = s_frameSerial;
	c->prepared = 1;
	c->live = live != 0;
}

int void2dActivateContext(int id) {
	if (id < 0 || (size_t)id >= s_contextCap || !s_contexts[id].prepared) {
		fprintf(stderr, "void2d: cannot activate context %d — never prepared\n", id);
		abort();
	}
	const void2dPreparedContext *c = &s_contexts[id];
	if (c->frameSerial != s_frameSerial) {
		fprintf(stderr, "void2d: cannot activate context %d — prepared frame %d expired (current %d)\n",
			id, c->frameSerial, s_frameSerial);
		abort();
	}
	if (c->live && !c->frameUploaded) {
		fprintf(stderr, "void2d: cannot activate context %d — prepared draw has no uploaded sources\n", id);
		abort();
	}
	s_srcVertex = c->srcVertex;
	s_srcSprite = c->srcSprite;
	s_srcUi = c->srcUi;
	s_srcVertexBase = c->srcVertexBase;
	s_srcSpriteBase = c->srcSpriteBase;
	s_srcUiBase = c->srcUiBase;
	s_spriteInstanceCount = c->spriteInstanceCount;
	s_uiInstanceCount = c->uiInstanceCount;
	s_frameUploaded = c->live ? c->frameUploaded : 0;
	return c->live;
}

// One separable-blur tap pass into the active offscreen RT pass: sample srcView with the
// 9-tap kernel offset by (dirX,dirY) in UV space. Caller runs it twice (H then V) ping-ponging
// between two RTs. dir = (radius/texW,0) horizontal, (0,radius/texH) vertical.
// The door's 12 binding words: vertex buffers 0..1, index buffer 2, views from 3 and samplers
// from 9, each at the shader's slot as sg_bindings indexes them.
#define BIND_VIEWS 3
#define BIND_SAMPLERS 9
#define BIND_WORDS 12

static void applyBindings(uint32_t vertex0, uint32_t vertex1, int32_t offset0, int32_t offset1,
                          int viewSlot, uint32_t view, int samplerSlot, uint32_t sampler) {
	uint32_t words[BIND_WORDS] = {0};
	const int32_t offsets[2] = { offset0, offset1 };
	words[0] = vertex0;
	words[1] = vertex1;
	words[BIND_VIEWS + viewSlot] = view;
	words[BIND_SAMPLERS + samplerSlot] = sampler;
	doorApplyBindings(words, BIND_WORDS, offsets, 2);
}

static void void2dBlur(uint32_t srcView, float dirX, float dirY, int blend) {
	doorApplyPipeline(pipelineAt(PIPELINE_BLUR, 1, blend));
	// linear, clamp: a blur tap past the edge must not wrap
	applyBindings(s_fsQuad, 0, 0, 0, VIEW_srcTex, srcView, SMP_srcSmp, s_smp[2]);
	blur_params_t p = {0};
	p.dir[0] = dirX; p.dir[1] = dirY;
	doorApplyUniforms(UB_blur_params, (const uint8_t *)&p, (int64_t)sizeof(p));
	doorDraw(0, 6, 1);
}

static void uploadGlyphPages(void) {
	int count = void2dGlyphPageCount();
	for (int page = 0; page < count && page < VOID2D_MAX_GLYPH_PAGES; page++) {
		dropReleasedPageImage(page);
		if (s_pageImg[page] == 0 || !void2dGlyphPageTakeUpload(page)) { continue; }
		int bytes = void2dGlyphPageBytes(page);
		doorUpdateTexture(s_pageImg[page], void2dGlyphPageData(page), (int64_t)bytes);
		s_glyphUploads++;
		s_glyphUploadBytes += bytes;
	}
}

static void runCommands(const float *commands, int commandCount,
                        const float *effects, int effectCount,
                        float fbW, float fbH);

// The size check before it makes room for the frame, so a refused append is that check gone
// wrong: the frame drops with an error rather than drawing from stale bytes.
static int appendFrame(const void *data, size_t bytes, int *offset) {
	const int64_t at = doorAppendBuffer(s_vbuf, (const uint8_t *)data, (int64_t)bytes);
	if (at < 0) {
		s_droppedFrames++;
		fprintf(stderr, "void2d: %zu bytes did not fit the %d-byte vertex buffer after %d this frame — frame dropped\n",
			bytes, s_vbufBytes, s_frameVertexBytes);
		return 0;
	}
	*offset = (int)at;
	return 1;
}

// Upload the frame's geometry once, then run every render-target pass to completion. Called
// with NO pass open: each TargetBegin opens one and its TargetEnd closes it, so target passes
// are siblings and never nest. That is what hoisting the target blocks out of the swapchain
// list buys - the door stops on a nested begin (sokol asserts `!_sg.cur_pass.valid`), which is
// exactly how the old filter path died. Returns 0 when the frame was dropped; then nothing else may draw.
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
	// Against the FRAME's total, not this bracket's. doorAppendBuffer accumulates until
	// submit, so a buffer sized for one bracket overflows on the second. Same mechanism as the
	// "per-frame vertex cap" defect this phase closed one layer down.
	size_t frameBytes = (size_t)s_frameVertexBytes + vertexBytes + spriteBytes + uiBytes;
	if (frameBytes > (size_t)VOID2D_MAX_BUFFER_BYTES) {
		// A dropped frame with an error, never a silent truncation. The old path let the
		// append run past the end and the rest of the scene simply vanished.
		s_droppedFrames++;
		fprintf(stderr, "void2d: frame needs %zu bytes of geometry, cap is %d — frame dropped\n",
			frameBytes, VOID2D_MAX_BUFFER_BYTES);
		return 0;
	}
	if (!ensureVertexBuffer((int)frameBytes)) {
		s_droppedFrames++;
		return 0;
	}
	uploadGlyphPages();

	// One upload for the whole frame, before any draw: every Draw command is a range inside
	// it. This is the "one upload per bracket" of VOID2D.md P1, and it is one per FRAME here
	// because the target lists share the stream.
	if (vertexBytes > 0) {
		if (!appendFrame(vertices, vertexBytes, &s_frameBaseOffset)) { return 0; }
		s_uploadCount++;
		s_uploadBytes += (int)vertexBytes;
	}
	// The sprite record and void2dSpriteInstance are the same 64 bytes in the same order, so
	// the frame's instances append as they were recorded - no pack, no staging copy. A second
	// append rather than one concatenated upload, because concatenating would mean copying the
	// whole vertex stream through a staging buffer to save a call that costs nothing.
	if (spriteBytes > 0) {
		if (!appendFrame(spriteInstances, spriteBytes, &s_spriteInstanceBase)) { return 0; }
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
			void2dPackUiInstance(s_uiStage + i,
				uiInstances + (size_t)i * VOID2D_UI_REC_FLOATS, packColor);
		}
		if (!appendFrame(s_uiStage, uiBytes, &s_uiInstanceBase)) { return 0; }
		s_uploadCount++;
		s_uploadBytes += (int)uiBytes;
	}
	if (vertexBytes > 0 || spriteBytes > 0 || uiBytes > 0) { s_frameVertexBytes = (int)frameBytes; }
	s_srcVertex = s_vbuf;
	s_srcSprite = s_vbuf;
	s_srcUi = s_vbuf;
	s_srcVertexBase = s_frameBaseOffset;
	s_srcSpriteBase = s_spriteInstanceBase;
	s_srcUiBase = s_uiInstanceBase;
	s_frameUploaded = 1;
	if (targetCommandCount > 0) {
		runCommands(targetCommands, targetCommandCount, effects, effectCount, 0.0f, 0.0f);
	}
	return 1;
}

#define LIST_VERTEX 0
#define LIST_SPRITE 1
#define LIST_UI 2

typedef struct {
	uint32_t buf[3];
	int cap[3];
	int updatedFrame;
	int stale;
	void2dUiInstance *stage;
	int stageCap;
} void2dList;

static void2dList *s_lists;
static int s_listCap;

static void2dList *listAt(int id) {
	if (id >= s_listCap) {
		int want = s_listCap > 0 ? s_listCap : 4;
		while (want <= id) { want *= 2; }
		void2dList *grown = (void2dList *)realloc(s_lists, (size_t)want * sizeof(void2dList));
		if (!grown) { return NULL; }
		memset(grown + s_listCap, 0, (size_t)(want - s_listCap) * sizeof(void2dList));
		for (int i = s_listCap; i < want; i++) { grown[i].updatedFrame = -1; }
		s_lists = grown;
		s_listCap = want;
	}
	return &s_lists[id];
}

void void2dReleaseList(int id) {
	if (id < 0) {
		fprintf(stderr, "void2d: cannot release list %d — invalid id\n", id);
		abort();
	}
	if ((size_t)id < s_contextCap) { memset(&s_contexts[id], 0, sizeof(s_contexts[id])); }
	if (id >= s_listCap) { return; }
	void2dList *l = &s_lists[id];
	for (int i = 0; i < 3; i++) {
		if (!l->buf[i]) { continue; }
		if (s_frameOpen) {
			retireClosedBuffer(l->buf[i], id);
		} else {
			doorDestroyBuffer(l->buf[i]);
			s_buffersFreed++;
		}
	}
	free(l->stage);
	memset(l, 0, sizeof(*l));
	l->updatedFrame = -1;
}

static void forgetContextResources(void) {
	s_vbuf = 0;
	s_vbufBytes = 0;
	memset(s_pipelines, 0, sizeof(s_pipelines));
	memset(s_pageImg, 0, sizeof(s_pageImg));
	memset(s_pageView, 0, sizeof(s_pageView));
	s_retiredBufCount = 0;
	s_closedBufCount = 0;
	for (int i = 0; i < s_listCap; i++) {
		for (int which = 0; which < 3; which++) {
			s_lists[i].buf[which] = 0;
			s_lists[i].cap[which] = 0;
		}
		s_lists[i].stale = 1;
	}
	for (size_t i = 0; i < s_contextCap; i++) {
		s_contexts[i].srcVertex = 0;
		s_contexts[i].srcSprite = 0;
		s_contexts[i].srcUi = 0;
		s_contexts[i].prepared = 0;
	}
	s_buffersMade = 0;
	s_buffersFreed = 0;
	s_atlasMade = 0;
	void2dGlyphPagesMarkDirty();
}

static void adoptContext(void) {
	if (s_generation == 0 || doorContextGeneration() == s_generation) { return; }
	forgetContextResources();
	makeContextResources();
}

static int ensureListBuffer(void2dList *l, int which, int bytes) {
	if (l->buf[which] && bytes <= l->cap[which]) { return 1; }
	int want = void2dGrowthTarget(l->cap[which], bytes);
	if (want == 0) { return 0; }
	if (l->buf[which]) {
		if (s_retiredBufCount >= VOID2D_MAX_RETIRED_BUFFERS) { return 0; }
		s_retiredBuf[s_retiredBufCount] = l->buf[which];
		s_retiredBufCount++;
	}
	l->buf[which] = makeBuffer(DOOR_BUFFER_VERTEX | DOOR_BUFFER_STREAM, NULL, (size_t)want, "display list");
	s_buffersMade++;
	l->cap[which] = want;
	return 1;
}

static int writeListBuffer(void2dList *l, int which, const void *data, size_t bytes) {
	if (bytes == 0) { return 1; }
	if (!ensureListBuffer(l, which, (int)bytes)) { return 0; }
	if (!doorUpdateBuffer(l->buf[which], (const uint8_t *)data, (int64_t)bytes)) { return 0; }
	s_uploadCount++;
	s_uploadBytes += (int)bytes;
	return 1;
}

int void2dReplayList(int list, const float *targetCommands, int targetCommandCount,
                     const float *effects, int effectCount,
                     const float *vertices, int vertexCount, int vertexDirty,
                     const float *spriteInstances, int spriteInstanceCount, int spriteDirty,
                     const float *uiInstances, int uiInstanceCount,
                     const int *uiRanges, int uiRangeCount) {
	void2dList *l = listAt(list);
	if (l && l->stale) {
		vertexDirty = 1;
		spriteDirty = 1;
		uiRangeCount = -1;
	}
	int dirty = vertexDirty || spriteDirty || uiRangeCount != 0;
	if (!l || (dirty && l->updatedFrame == s_frameSerial)) {
		if (l) { l->stale = 1; }
		return void2dReplayTargets(targetCommands, targetCommandCount, effects, effectCount,
			vertices, vertexCount, spriteInstances, spriteInstanceCount,
			uiInstances, uiInstanceCount);
	}
	s_frameUploaded = 0;
	s_spriteInstanceCount = spriteInstanceCount;
	s_uiInstanceCount = uiInstanceCount;
	uploadGlyphPages();
	size_t vertexBytes = (size_t)vertexCount * VERTEX_FLOATS * sizeof(float);
	size_t spriteBytes = (size_t)spriteInstanceCount * sizeof(void2dSpriteInstance);
	size_t uiBytes = (size_t)uiInstanceCount * sizeof(void2dUiInstance);
	if (vertexDirty && !writeListBuffer(l, LIST_VERTEX, vertices, vertexBytes)) {
		l->stale = 1;
		s_droppedFrames++;
		return 0;
	}
	if (spriteDirty && !writeListBuffer(l, LIST_SPRITE, spriteInstances, spriteBytes)) {
		l->stale = 1;
		s_droppedFrames++;
		return 0;
	}
	if (uiRangeCount != 0 && uiInstanceCount > 0) {
		if (uiInstanceCount > l->stageCap) {
			void2dUiInstance *grown = (void2dUiInstance *)realloc(
				l->stage, (size_t)uiInstanceCount * sizeof(void2dUiInstance));
			if (!grown) {
				l->stale = 1;
				s_droppedFrames++;
				fprintf(stderr, "void2d: no room to stage %d UI instances — frame dropped\n",
					uiInstanceCount);
				return 0;
			}
			l->stage = grown;
			l->stageCap = uiInstanceCount;
		}
		int ranges = uiRangeCount < 0 ? 1 : uiRangeCount;
		for (int r = 0; r < ranges; r++) {
			int from = uiRangeCount < 0 ? 0 : uiRanges[r * 2];
			int to = uiRangeCount < 0 ? uiInstanceCount : uiRanges[r * 2 + 1];
			for (int i = from; i < to && i < uiInstanceCount; i++) {
				void2dPackUiInstance(l->stage + i,
					uiInstances + (size_t)i * VOID2D_UI_REC_FLOATS, packColor);
			}
		}
		if (!writeListBuffer(l, LIST_UI, l->stage, uiBytes)) {
			l->stale = 1;
			s_droppedFrames++;
			return 0;
		}
	}
	if (dirty) { l->updatedFrame = s_frameSerial; }
	l->stale = 0;
	s_srcVertex = l->buf[LIST_VERTEX];
	s_srcSprite = l->buf[LIST_SPRITE];
	s_srcUi = l->buf[LIST_UI];
	s_srcVertexBase = 0;
	s_srcSpriteBase = 0;
	s_srcUiBase = 0;
	s_frameUploaded = 1;
	if (targetCommandCount > 0) {
		runCommands(targetCommands, targetCommandCount, effects, effectCount, 0.0f, 0.0f);
	}
	return 1;
}

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
// draw for the whole run. The sprite program carries no colour pipeline, so a node with a
// colorMatrix, colorAdd or colorKey never reaches here - the emitter keeps it on the vertex
// path and records the break, which is what makes that decision visible in a T1 snapshot
// rather than inferred from a pixel.
static void drawSpriteRun(const float *cmd, int blend, int rt, uint32_t view,
                          float fbW, float fbH, uint32_t *lastPipeline, int *scissorApplied,
                          int *paramsValid, int *fxValid) {
	int count = (int)cmd[CMD_INSTANCE_COUNT];
	if (count <= 0) { return; }

	uint32_t pip = pipelineAt(PIPELINE_SPRITE, rt, blend);
	if (pip != *lastPipeline) {
		doorApplyPipeline(pip);
		*lastPipeline = pip;
		*scissorApplied = 0;
		*paramsValid = 0;
		*fxValid = 0;
	}

	applyBindings(s_unitQuad, s_srcSprite, 0,
		s_srcSpriteBase + (int)cmd[CMD_INSTANCE_OFFSET] * (int)sizeof(void2dSpriteInstance),
		VIEW_spriteTex, view, SMP_spriteSmp, s_smp[samplerOf(cmd)]);

	if (!*scissorApplied) {
		applyScissor(cmd, fbW, fbH);
		*scissorApplied = 1;
	}

	sprite_params_t sp = {0};
	sp.viewport[0] = fbW;
	sp.viewport[1] = fbH;
	sp.viewport[2] = (sampledTarget(view) && !s_originTopLeft) ? 1.0f : 0.0f;
	sp.viewport[3] = premultipliedSource(cmd) ? 1.0f : 0.0f;
	const float *spriteScope = scopeOf(cmd);
	if (spriteScope) { sp.shift[0] = spriteScope[0]; sp.shift[1] = spriteScope[1]; }
	copyClipParams(sp.clipU, sp.clipV, cmd);
	doorApplyUniforms(UB_sprite_params, (const uint8_t *)&sp, (int64_t)sizeof(sp));

	doorDraw(0, 6, count);
	s_drawCallCount++;
#ifdef VOID_PROFILER
	s_frameSpriteInstances += count;
#endif
}

// One unified-UI run: the unit quad at slot 0, this run's instances at slot 1, one draw
// for the whole run. Every mode shares this program, which is the point — a card, its label
// and its image are one draw instead of three, and the mode lives in a per-instance lane
// rather than in a pipeline.
//
// The effect row rides with each instance, so a node with a colorMatrix, colorAdd or colorKey
// stays in this run.
static void drawUiRun(const float *cmd, int blend, int rt, uint32_t view,
                      float fbW, float fbH, uint32_t *lastPipeline, int *scissorApplied,
                      int *paramsValid, int *fxValid,
                      const float *effects, int effectCount) {
	int count = (int)cmd[CMD_INSTANCE_COUNT];
	if (count <= 0) { return; }

	uint32_t pip = pipelineAt(PIPELINE_UI, rt, blend);
	if (pip != *lastPipeline) {
		doorApplyPipeline(pip);
		*lastPipeline = pip;
		*scissorApplied = 0;
		*paramsValid = 0;
		*fxValid = 0;
	}

	applyBindings(s_unitQuad, s_srcUi, 0,
		s_srcUiBase + (int)cmd[CMD_INSTANCE_OFFSET] * (int)sizeof(void2dUiInstance),
		VIEW_uiTex, view, SMP_uiSmp, s_smp[samplerOf(cmd)]);

	if (!*scissorApplied) {
		applyScissor(cmd, fbW, fbH);
		*scissorApplied = 1;
	}

	ui_params_t up = {0};
	up.viewport[0] = fbW;
	up.viewport[1] = fbH;
	up.viewport[2] = (sampledTarget(view) && !s_originTopLeft) ? 1.0f : 0.0f;
	up.viewport[3] = cmd[CMD_RT_MODE] != 0.0f ? cmd[CMD_RT_MODE] : s_dpiScale;
	const float *uiScope = scopeOf(cmd);
	if (uiScope) { up.shift[0] = uiScope[0]; up.shift[1] = uiScope[1]; }
	copyClipParams(up.clipU, up.clipV, cmd);
	doorApplyUniforms(UB_ui_params, (const uint8_t *)&up, (int64_t)sizeof(up));
	ui_fx_t tu = {0};
	memcpy(tu.gammaRatios, s_textGamma, sizeof(tu.gammaRatios));
	tu.textParams[0] = s_textContrast;
	int effectIndex = (int)cmd[CMD_EFFECT];
	if (effectIndex >= 0 && effectIndex < effectCount) {
		const float *fx = effects + (size_t)effectIndex * EFFECT_FLOATS;
		memcpy(tu.colorMatrix, fx, sizeof(tu.colorMatrix));
		memcpy(tu.colorAdd, fx + 16, sizeof(tu.colorAdd));
		memcpy(tu.colorKey, fx + 20, sizeof(tu.colorKey));
		tu.effectParams[0] = 1.0f;
	}
	doorApplyUniforms(UB_ui_fx, (const uint8_t *)&tu, (int64_t)sizeof(tu));

	doorDraw(0, 6, count);
	s_drawCallCount++;
#ifdef VOID_PROFILER
	s_frameUiInstances += count;
#endif
}

// The one executor both lists go through. `fbW`/`fbH` are the viewport the commands were
// recorded against; a TargetBegin replaces them for the length of its block, which is how a
// target of a different size gets the right projection with no second code path.
static void runCommands(const float *commands, int commandCount,
                        const float *effects, int effectCount,
                        float fbW, float fbH) {
	float sizeStack[VOID2D_MAX_TARGET_DEPTH][2];
	int sizeDepth = 0;
	const int baseTarget = doorPassState() == DOOR_PASS_TARGET;

	// A uniform block that has not changed is not re-applied. Every doorApplyUniforms costs
	// 256 bytes of the per-frame uniform buffer whatever the payload, as sokol's WebGPU and
	// Metal uniforms do (sokol_gfx.h:2014-2023, VOID2D.md "Web and WebGPU"), and in a UI
	// frame the viewport and the colour pipeline are the same for almost every draw. The display list
	// is what makes this visible: before it, each draw applied both blocks unconditionally.
	void2d_params_t lastParams;
	void2d_fx_t lastFx;
	int paramsValid = 0;
	int fxValid = 0;
	uint32_t lastPipeline = 0;

	int scissorApplied = 0;
	int lastScope = -1;
	for (int i = 0; i < commandCount; i++) {
		const float *cmd = commands + (size_t)i * CMD_FLOATS;
		int kind = (int)cmd[CMD_KIND];
		int scope = (int)cmd[CMD_SCOPE];
		if (scope != lastScope) {
			lastScope = scope;
			scissorApplied = 0;
		}
		if (kind == CMD_KIND_SCISSOR) {
			applyScissor(cmd, fbW, fbH);
			scissorApplied = 1;
			continue;
		}
		if (kind == CMD_KIND_BLUR) {
			void2dBlur(void2dCommandView(cmd), cmd[CMD_ARG0], cmd[CMD_ARG1], (int)cmd[CMD_BLEND]);
			// It applied its own pipeline and bindings, so everything this loop remembers about
			// what is bound is now wrong. A Draw after a Blur in the same pass would otherwise
			// skip its own `doorApplyPipeline` and draw the quad with the blur pipeline.
			lastPipeline = 0; paramsValid = 0; fxValid = 0; scissorApplied = 0;
			continue;
		}
		if (kind == CMD_KIND_TGT_BEGIN) {
			if (sizeDepth >= VOID2D_MAX_TARGET_DEPTH) {
				fprintf(stderr, "void2d: a target list nested %d deep at replay, where its blocks are flat\n",
					sizeDepth + 1);
				abort();
			}
			sizeStack[sizeDepth][0] = fbW;
			sizeStack[sizeDepth][1] = fbH;
			sizeDepth++;
			fbW = cmd[CMD_ARG0];
			fbH = cmd[CMD_ARG1];
			doorBeginColorPass(void2dCommandView(cmd),
				cmd[CMD_CLEAR_R], cmd[CMD_CLEAR_R + 1], cmd[CMD_CLEAR_R + 2], cmd[CMD_CLEAR_R + 3]);
			lastPipeline = 0; paramsValid = 0; fxValid = 0; scissorApplied = 0;
			continue;
		}
		if (kind == CMD_KIND_TGT_END) {
			doorEndPass();
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
		uint32_t view = void2dCommandView(cmd);
		if (view == 0) view = s_whiteView;

		// The pipeline branch comes BEFORE the vertex-count guard: a sprite run carries an
		// instance range and a vertex count of zero, so testing the vertex count first would
		// skip every instanced draw and the frame would simply be missing its sprites.
		int rt = baseTarget || cmd[CMD_RT_MODE] != 0.0f;
		if ((int)cmd[CMD_PIPELINE] == PIPELINE_SPRITE) {
			drawSpriteRun(cmd, blend, rt, view, fbW, fbH, &lastPipeline, &scissorApplied,
				&paramsValid, &fxValid);
			continue;
		}
		if ((int)cmd[CMD_PIPELINE] == PIPELINE_UI) {
			drawUiRun(cmd, blend, rt, view, fbW, fbH, &lastPipeline, &scissorApplied,
				&paramsValid, &fxValid, effects, effectCount);
			continue;
		}

		int count = (int)cmd[CMD_VERTEX_COUNT];
		if (count <= 0) continue;
		uint32_t pip = pipelineAt(PIPELINE_VERTEX, rt, blend);
		if (pip != lastPipeline) {
			doorApplyPipeline(pip);
			lastPipeline = pip;
			// Applying a pipeline resets the scissor and the bindings, as sokol does.
			scissorApplied = 0;
			paramsValid = 0;
			fxValid = 0;
		}
		applyBindings(s_srcVertex, 0,
			s_srcVertexBase + (int)cmd[CMD_VERTEX_OFFSET] * VERTEX_FLOATS * (int)sizeof(float), 0,
			VIEW_tex, view, SMP_smp, s_smp[samplerOf(cmd)]);

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
		bool isRT = sampledTarget(view);
		bool noEffect = memcmp(matrix, s_identityMatrix, sizeof(s_identityMatrix)) == 0
			&& addR == 0.0f && addG == 0.0f && addB == 0.0f && addA == 0.0f
			&& (!fx || fx[23] <= 0.5f);
		bool premultiplied = premultipliedSource(cmd);
		vp.viewport[2] = (isRT && !s_originTopLeft) ? 1.0f : 0.0f;
		vp.viewport[3] = (premultiplied && noEffect) ? 1.0f : 0.0f;
		vp.model0[0] = 1.0f; vp.model0[3] = 1.0f;   // the stream is already in world space
		vp.model1[2] = glyphPageViewMode(view);
		vp.model1[3] = cmd[CMD_RT_MODE] != 0.0f ? cmd[CMD_RT_MODE] : s_dpiScale;
		vp.globalColor[0] = 1.0f; vp.globalColor[1] = 1.0f; vp.globalColor[2] = 1.0f; vp.globalColor[3] = 1.0f;
		const float *vertexScope = scopeOf(cmd);
		if (vertexScope) { vp.shift[0] = vertexScope[0]; vp.shift[1] = vertexScope[1]; }
		copyClipParams(vp.clipU, vp.clipV, cmd);
		if (!paramsValid || memcmp(&vp, &lastParams, sizeof(vp)) != 0) {
			doorApplyUniforms(UB_void2d_params, (const uint8_t *)&vp, (int64_t)sizeof(vp));
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
		memcpy(fxu.gammaRatios, s_textGamma, sizeof(fxu.gammaRatios));
		fxu.textParams[0] = s_textContrast;
		fxu.sourceParams[0] = (premultiplied && !noEffect) ? 1.0f : 0.0f;
		if (!fxValid || memcmp(&fxu, &lastFx, sizeof(fxu)) != 0) {
			doorApplyUniforms(UB_void2d_fx, (const uint8_t *)&fxu, (int64_t)sizeof(fxu));
			lastFx = fxu;
			fxValid = 1;
		}

		doorDraw(0, count, 1);
		s_drawCallCount++;
	}
}
