// Void capture — see capture.h. Moved out of the gitignored out/tmp/capture/capture.c, which
// is the reason no gate of the last three sessions can be re-run by anyone (docs/TESTING.md).
//
// The D3D11 path is that file's, unchanged in mechanism: reach the resolved swapchain buffer
// through sokol's native-handle getters, clone its desc as STAGING | CPU_ACCESS_READ,
// CopyResource, Map. It runs after sg_commit(), by which point sokol_gfx has resolved the
// swapchain pass into that buffer, so the bytes are the frame that was just drawn.
//
// The BGRA -> RGBA swizzle below is hand-written and nothing in the renderer checks it.
// What checks it is tests/golden/scenes.ms "harness/solid", whose expected pixels are
// arithmetic rather than a capture.

#include "capture.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(SOKOL_GLES3) || defined(SOKOL_GLCORE)
	#define VOID_CAPTURE_GL 1
#elif defined(_WIN32)
	#define VOID_CAPTURE_D3D11 1
#endif

#if defined(VOID_CAPTURE_D3D11)
	#define COBJMACROS
	#include <d3d11.h>
	#include <dxgi.h>
	const void *sg_d3d11_device(void);
	const void *sg_d3d11_device_context(void);
	const void *sapp_d3d11_get_swap_chain(void);
	static const GUID VOID_TEXTURE2D_IID =
		{0x6f15aaf2, 0xd208, 0x4e89, {0x9a, 0xb4, 0x48, 0x95, 0x35, 0xd3, 0x4f, 0x9c}};
#endif

#if defined(VOID_CAPTURE_GL)
	#include <GLES3/gl3.h>
	int sapp_width(void);
	int sapp_height(void);
#endif

#define STB_IMAGE_WRITE_IMPLEMENTATION
#define STBI_WRITE_NO_STDIO_WARNING
#include "../../deps/stb/stb_image_write.h"

typedef struct {
	uint8_t *rgba;
	int width;
	int height;
} voidCaptureSlot;

static voidCaptureSlot s_slots[VOID_CAPTURE_SLOTS];

// NULL on failure, and the slot is left empty rather than sized, so a caller that forgets
// to check cannot go on to report a size for a buffer that does not exist.
static uint8_t *slotResize(int slot, int width, int height) {
	voidCaptureSlot *s = &s_slots[slot];
	size_t bytes = (size_t)width * (size_t)height * 4u;
	if (s->width == width && s->height == height && s->rgba != NULL) return s->rgba;
	free(s->rgba);
	s->rgba = (uint8_t *)malloc(bytes);
	if (s->rgba == NULL) {
		s->width = 0;
		s->height = 0;
		return NULL;
	}
	s->width = width;
	s->height = height;
	return s->rgba;
}

int voidCaptureBackend(void) {
#if defined(VOID_CAPTURE_D3D11)
	return 1;
#elif defined(VOID_CAPTURE_GL)
	return 2;
#else
	return 0;
#endif
}

#if defined(VOID_CAPTURE_D3D11)
static int grabD3D11(int slot, IDXGISwapChain *swapChain, int buffer) {
	ID3D11Device *device = (ID3D11Device *)sg_d3d11_device();
	ID3D11DeviceContext *context = (ID3D11DeviceContext *)sg_d3d11_device_context();
	if (!swapChain || !device || !context) return 0;
	ID3D11Texture2D *back = NULL;
	if (FAILED(IDXGISwapChain_GetBuffer(swapChain, (UINT)buffer, &VOID_TEXTURE2D_IID, (void **)&back))) return 0;
	D3D11_TEXTURE2D_DESC desc;
	ID3D11Texture2D_GetDesc(back, &desc);
	desc.Usage = D3D11_USAGE_STAGING;
	desc.BindFlags = 0;
	desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
	desc.MiscFlags = 0;
	ID3D11Texture2D *staging = NULL;
	if (FAILED(ID3D11Device_CreateTexture2D(device, &desc, NULL, &staging))) {
		ID3D11Texture2D_Release(back);
		return 0;
	}
	ID3D11DeviceContext_CopyResource(context, (ID3D11Resource *)staging, (ID3D11Resource *)back);
	D3D11_MAPPED_SUBRESOURCE mapped;
	if (FAILED(ID3D11DeviceContext_Map(context, (ID3D11Resource *)staging, 0, D3D11_MAP_READ, 0, &mapped))) {
		ID3D11Texture2D_Release(staging);
		ID3D11Texture2D_Release(back);
		return 0;
	}
	uint8_t *out = slotResize(slot, (int)desc.Width, (int)desc.Height);
	if (out == NULL) {
		ID3D11DeviceContext_Unmap(context, (ID3D11Resource *)staging, 0);
		ID3D11Texture2D_Release(staging);
		ID3D11Texture2D_Release(back);
		return 0;
	}
	for (UINT y = 0; y < desc.Height; y++) {
		const uint8_t *row = (const uint8_t *)mapped.pData + (size_t)y * mapped.RowPitch;
		uint8_t *dst = out + (size_t)y * (size_t)desc.Width * 4u;
		for (UINT x = 0; x < desc.Width; x++) {
			dst[x * 4 + 0] = row[x * 4 + 2];
			dst[x * 4 + 1] = row[x * 4 + 1];
			dst[x * 4 + 2] = row[x * 4 + 0];
			dst[x * 4 + 3] = row[x * 4 + 3];
		}
	}
	ID3D11DeviceContext_Unmap(context, (ID3D11Resource *)staging, 0);
	ID3D11Texture2D_Release(staging);
	ID3D11Texture2D_Release(back);
	return 1;
}
#endif

int voidCaptureGrab(int slot) {
	if (slot < 0 || slot >= VOID_CAPTURE_SLOTS) return 0;
#if defined(VOID_CAPTURE_D3D11)
	return grabD3D11(slot, (IDXGISwapChain *)sapp_d3d11_get_swap_chain(), 0);
#elif defined(VOID_CAPTURE_GL)
	// Untested on this box: no GLES3 target has run the golden runner yet. It exists because
	// it is ~30 lines and is the same path the Android device and WebGL2 will use.
	int width = sapp_width();
	int height = sapp_height();
	if (width <= 0 || height <= 0) return 0;
	uint8_t *out = slotResize(slot, width, height);
	if (out == NULL) return 0;
	uint8_t *flip = (uint8_t *)malloc((size_t)width * (size_t)height * 4u);
	if (!flip) return 0;
	glPixelStorei(GL_PACK_ALIGNMENT, 1);
	glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, flip);
	// glReadPixels hands back the bottom row first; every other backend here is top row first.
	for (int y = 0; y < height; y++) {
		memcpy(out + (size_t)y * (size_t)width * 4u,
		       flip + (size_t)(height - 1 - y) * (size_t)width * 4u,
		       (size_t)width * 4u);
	}
	free(flip);
	return 1;
#else
	(void)slot;
	return 0;
#endif
}

int voidCaptureGrabSwapChain(int slot, long long swapChain, int buffer) {
	if (slot < 0 || slot >= VOID_CAPTURE_SLOTS) return 0;
#if defined(VOID_CAPTURE_D3D11)
	return grabD3D11(slot, (IDXGISwapChain *)(intptr_t)swapChain, buffer);
#else
	(void)swapChain;
	(void)buffer;
	return 0;
#endif
}

long long voidCapturePixel(int slot, int x, int y) {
	if (slot < 0 || slot >= VOID_CAPTURE_SLOTS) return -1;
	const voidCaptureSlot *s = &s_slots[slot];
	if (s->rgba == NULL || x < 0 || y < 0 || x >= s->width || y >= s->height) return -1;
	const uint8_t *p = s->rgba + ((size_t)y * (size_t)s->width + (size_t)x) * 4u;
	return ((long long)p[0] << 24) | ((long long)p[1] << 16) | ((long long)p[2] << 8) | (long long)p[3];
}

int voidCaptureWidth(int slot) {
	if (slot < 0 || slot >= VOID_CAPTURE_SLOTS) return 0;
	return s_slots[slot].width;
}

int voidCaptureHeight(int slot) {
	if (slot < 0 || slot >= VOID_CAPTURE_SLOTS) return 0;
	return s_slots[slot].height;
}

int voidCaptureSlotsDiffer(void) {
	const voidCaptureSlot *a = &s_slots[0];
	const voidCaptureSlot *b = &s_slots[1];
	if (!a->rgba || !b->rgba) return -1;
	if (a->width != b->width || a->height != b->height) return -1;
	int differ = 0;
	size_t count = (size_t)a->width * (size_t)a->height;
	for (size_t i = 0; i < count; i++) {
		if (memcmp(a->rgba + i * 4u, b->rgba + i * 4u, 3u) != 0) differ++;
	}
	return differ;
}

int voidCaptureUniform(int slot) {
	if (slot < 0 || slot >= VOID_CAPTURE_SLOTS) return 0;
	const voidCaptureSlot *s = &s_slots[slot];
	if (!s->rgba || s->width <= 0 || s->height <= 0) return 0;
	size_t count = (size_t)s->width * (size_t)s->height;
	for (size_t i = 1; i < count; i++) {
		if (memcmp(s->rgba, s->rgba + i * 4u, 3u) != 0) return 0;
	}
	return 1;
}

// RGB, not RGBA. The swapchain is opaque, so its alpha channel carries no information about
// what was drawn; storing it would cost about a quarter of the suite's bytes and would add a
// cross-backend failure that means nothing, since GL and WebGL readbacks do not all report
// the same alpha for an opaque surface. Alpha inside the frame is still tested — it is what
// blending turned into colour.
int voidCaptureWritePng(int slot, const char *path) {
	if (slot < 0 || slot >= VOID_CAPTURE_SLOTS) return 0;
	const voidCaptureSlot *s = &s_slots[slot];
	if (!s->rgba || s->width <= 0 || s->height <= 0) return 0;
	size_t count = (size_t)s->width * (size_t)s->height;
	uint8_t *rgb = (uint8_t *)malloc(count * 3u);
	if (!rgb) return 0;
	for (size_t i = 0; i < count; i++) {
		rgb[i * 3u + 0] = s->rgba[i * 4u + 0];
		rgb[i * 3u + 1] = s->rgba[i * 4u + 1];
		rgb[i * 3u + 2] = s->rgba[i * 4u + 2];
	}
	int ok = stbi_write_png(path, s->width, s->height, 3, rgb, s->width * 3) != 0 ? 1 : 0;
	free(rgb);
	return ok;
}

int voidCaptureEnvInt(const char *name, int fallback) {
	const char *value = getenv(name);
	if (!value || !*value) return fallback;
	char *end = NULL;
	long parsed = strtol(value, &end, 10);
	if (end == value) return fallback;
	return (int)parsed;
}

void voidCaptureExit(int code) { exit(code); }
