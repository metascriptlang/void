// Void capture — see capture.h. Moved out of the gitignored out/tmp/capture/capture.c, which
// is the reason no gate of the last three sessions can be re-run by anyone (docs/TESTING.md).

#include "capture.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__EMSCRIPTEN__)
	#include <emscripten.h>
#endif

#if defined(VOID_GLES3) || defined(VOID_GLCORE)
	#define VOID_CAPTURE_GL 1
#elif defined(VOID_VULKAN)
	#define VOID_CAPTURE_VULKAN 1
#elif defined(VOID_D3D12) || defined(_WIN32)
	#define VOID_CAPTURE_D3D12 1
#elif defined(__APPLE__)
	#include <TargetConditionals.h>
	#define VOID_CAPTURE_METAL 1
	#if TARGET_OS_IPHONE
		#include <errno.h>
		#include <sys/stat.h>
	#endif
#endif

#if defined(VOID_CAPTURE_D3D12)
	#define COBJMACROS
	#include <d3d12.h>
	#include <dxgi1_4.h>
	void voidD3d12WaitIdle(void);
#endif

#if defined(VOID_CAPTURE_GL)
	#if defined(VOID_GLCORE)
		#if defined(_WIN32)
			#include <windows.h>
		#endif
		#include <GL/gl.h>
	#else
		#include <GLES3/gl3.h>
	#endif
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
#if defined(VOID_CAPTURE_GL) && defined(__EMSCRIPTEN__)
	return 3;
#elif defined(VOID_GLCORE)
	return 4;
#elif defined(VOID_CAPTURE_METAL)
	return 5;
#elif defined(VOID_CAPTURE_VULKAN)
	return 6;
#elif defined(VOID_CAPTURE_D3D12)
	return 7;
#elif defined(VOID_CAPTURE_GL)
	return 2;
#else
	return 0;
#endif
}

#if defined(VOID_CAPTURE_GL) || defined(VOID_CAPTURE_METAL) || defined(VOID_CAPTURE_VULKAN) || defined(VOID_CAPTURE_D3D12)
int32_t doorReadScreen(uint8_t *out, int64_t outLength);
int32_t voidSwapchainWidth(void);
int32_t voidSwapchainHeight(void);
#endif

extern void voidRequestedSize(int *w, int *h);
extern int voidFbWidth(void);
extern int voidFbHeight(void);
static void stopOnClampedWindow(void) {
	int reqW = 0, reqH = 0;
	voidRequestedSize(&reqW, &reqH);
	if (reqW <= 0 || reqH <= 0) return;
	if (reqW == voidFbWidth() && reqH == voidFbHeight()) return;
	fprintf(stderr, "capture: the window was asked for %dx%d but the framebuffer is %dx%d; "
		"a pixel test must read the size it asked for or use fbWidth/fbHeight\n",
		reqW, reqH, voidFbWidth(), voidFbHeight());
	exit(1);
}

const char *voidCaptureRenderer(void) {
#if defined(VOID_CAPTURE_GL)
	const char *renderer = (const char *)glGetString(GL_RENDERER);
	return renderer != NULL ? renderer : "GL_RENDERER unavailable";
#else
	return "";
#endif
}

int voidCaptureGrab(int slot) {
	if (slot < 0 || slot >= VOID_CAPTURE_SLOTS) {
		fprintf(stderr, "capture: slot %d is outside the %d capture slots\n", slot, VOID_CAPTURE_SLOTS);
		exit(1);
	}
	stopOnClampedWindow();
#if defined(VOID_CAPTURE_GL) || defined(VOID_CAPTURE_METAL) || defined(VOID_CAPTURE_VULKAN) || defined(VOID_CAPTURE_D3D12)
	int width = voidSwapchainWidth();
	int height = voidSwapchainHeight();
	if (width <= 0 || height <= 0) return 0;
	uint8_t *out = slotResize(slot, width, height);
	if (out == NULL) return 0;
	return doorReadScreen(out, (int64_t)width * (int64_t)height * 4);
#else
	(void)slot;
	return 0;
#endif
}

#if defined(VOID_CAPTURE_D3D12)
// Buffer `ago` presents back of a flip-sequential swapchain (a host view's), copied on a queue of
// its own after the backend's queue went idle; the buffer stays in PRESENT before and after.
static int grabD3D12(int slot, IDXGISwapChain3 *chain, int ago) {
	if (chain == NULL || ago < 0) return 0;
	DXGI_SWAP_CHAIN_DESC1 sd;
	if (FAILED(IDXGISwapChain3_GetDesc1(chain, &sd)) || (UINT)ago >= sd.BufferCount) return 0;
	if (sd.Format != DXGI_FORMAT_B8G8R8A8_UNORM && sd.Format != DXGI_FORMAT_R8G8B8A8_UNORM) {
		fprintf(stderr, "capture: a D3D12 swapchain of DXGI format %d has no RGBA8 readback\n", (int)sd.Format);
		exit(1);
	}
	voidD3d12WaitIdle();
	UINT index = (IDXGISwapChain3_GetCurrentBackBufferIndex(chain) + sd.BufferCount - (UINT)ago) % sd.BufferCount;
	ID3D12Resource *back = NULL;
	ID3D12Device *device = NULL;
	ID3D12CommandQueue *queue = NULL;
	ID3D12CommandAllocator *allocator = NULL;
	ID3D12GraphicsCommandList *list = NULL;
	ID3D12Resource *readback = NULL;
	ID3D12Fence *fence = NULL;
	HANDLE event = NULL;
	uint8_t *mapped = NULL;
	int ok = 0;
	if (FAILED(IDXGISwapChain3_GetBuffer(chain, index, &IID_ID3D12Resource, (void **)&back))) goto done;
	if (FAILED(ID3D12Resource_GetDevice(back, &IID_ID3D12Device, (void **)&device))) goto done;
	D3D12_RESOURCE_DESC td = {0};
	td.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
	td.Width = sd.Width;
	td.Height = sd.Height;
	td.DepthOrArraySize = 1;
	td.MipLevels = 1;
	td.Format = sd.Format;
	td.SampleDesc.Count = 1;
	D3D12_PLACED_SUBRESOURCE_FOOTPRINT footprint;
	UINT rows = 0;
	UINT64 rowBytes = 0, total = 0;
	ID3D12Device_GetCopyableFootprints(device, &td, 0, 1, 0, &footprint, &rows, &rowBytes, &total);
	D3D12_HEAP_PROPERTIES heap = {0};
	heap.Type = D3D12_HEAP_TYPE_READBACK;
	D3D12_RESOURCE_DESC bd = {0};
	bd.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
	bd.Width = total;
	bd.Height = 1;
	bd.DepthOrArraySize = 1;
	bd.MipLevels = 1;
	bd.SampleDesc.Count = 1;
	bd.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
	if (FAILED(ID3D12Device_CreateCommittedResource(device, &heap, D3D12_HEAP_FLAG_NONE, &bd, D3D12_RESOURCE_STATE_COPY_DEST, NULL,
		&IID_ID3D12Resource, (void **)&readback))) goto done;
	D3D12_COMMAND_QUEUE_DESC qd = {0};
	qd.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
	if (FAILED(ID3D12Device_CreateCommandQueue(device, &qd, &IID_ID3D12CommandQueue, (void **)&queue))) goto done;
	if (FAILED(ID3D12Device_CreateCommandAllocator(device, D3D12_COMMAND_LIST_TYPE_DIRECT, &IID_ID3D12CommandAllocator, (void **)&allocator))) goto done;
	if (FAILED(ID3D12Device_CreateCommandList(device, 0, D3D12_COMMAND_LIST_TYPE_DIRECT, allocator, NULL,
		&IID_ID3D12GraphicsCommandList, (void **)&list))) goto done;
	D3D12_RESOURCE_BARRIER barrier = {0};
	barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
	barrier.Transition.pResource = back;
	barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
	barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_PRESENT;
	barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
	ID3D12GraphicsCommandList_ResourceBarrier(list, 1, &barrier);
	D3D12_TEXTURE_COPY_LOCATION from = {0};
	from.pResource = back;
	from.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
	D3D12_TEXTURE_COPY_LOCATION to = {0};
	to.pResource = readback;
	to.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
	to.PlacedFootprint = footprint;
	ID3D12GraphicsCommandList_CopyTextureRegion(list, &to, 0, 0, 0, &from, NULL);
	barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_COPY_SOURCE;
	barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_PRESENT;
	ID3D12GraphicsCommandList_ResourceBarrier(list, 1, &barrier);
	if (FAILED(ID3D12GraphicsCommandList_Close(list))) goto done;
	ID3D12CommandQueue_ExecuteCommandLists(queue, 1, (ID3D12CommandList **)&list);
	if (FAILED(ID3D12Device_CreateFence(device, 0, D3D12_FENCE_FLAG_NONE, &IID_ID3D12Fence, (void **)&fence))) goto done;
	event = CreateEventA(NULL, FALSE, FALSE, NULL);
	if (event == NULL || FAILED(ID3D12CommandQueue_Signal(queue, fence, 1))) goto done;
	if (FAILED(ID3D12Fence_SetEventOnCompletion(fence, 1, event))) goto done;
	WaitForSingleObject(event, INFINITE);
	D3D12_RANGE range = { 0, (SIZE_T)total };
	if (FAILED(ID3D12Resource_Map(readback, 0, &range, (void **)&mapped))) goto done;
	uint8_t *out = slotResize(slot, (int)sd.Width, (int)sd.Height);
	if (out != NULL) {
		int bgra = sd.Format == DXGI_FORMAT_B8G8R8A8_UNORM;
		for (UINT y = 0; y < sd.Height; y++) {
			const uint8_t *row = mapped + footprint.Offset + (size_t)y * footprint.Footprint.RowPitch;
			uint8_t *dst = out + (size_t)y * (size_t)sd.Width * 4u;
			for (UINT x = 0; x < sd.Width; x++) {
				dst[x * 4 + 0] = row[x * 4 + (bgra ? 2 : 0)];
				dst[x * 4 + 1] = row[x * 4 + 1];
				dst[x * 4 + 2] = row[x * 4 + (bgra ? 0 : 2)];
				dst[x * 4 + 3] = row[x * 4 + 3];
			}
		}
		ok = 1;
	}
	D3D12_RANGE none = { 0, 0 };
	ID3D12Resource_Unmap(readback, 0, &none);
done:
	if (event) CloseHandle(event);
	if (fence) ID3D12Fence_Release(fence);
	if (list) ID3D12GraphicsCommandList_Release(list);
	if (allocator) ID3D12CommandAllocator_Release(allocator);
	if (queue) ID3D12CommandQueue_Release(queue);
	if (readback) ID3D12Resource_Release(readback);
	if (device) ID3D12Device_Release(device);
	if (back) ID3D12Resource_Release(back);
	return ok;
}
#endif

int voidCaptureGrabSwapChain(int slot, long long swapChain, int buffer) {
	if (slot < 0 || slot >= VOID_CAPTURE_SLOTS) return 0;
#if defined(VOID_CAPTURE_D3D12)
	return grabD3D12(slot, (IDXGISwapChain3 *)(intptr_t)swapChain, buffer);
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
#if defined(__APPLE__) && TARGET_OS_IPHONE
	// The app bundle is read-only, so a relative path lands under the container's Documents,
	// which `devicectl device copy from --domain-type appDataContainer` reads back.
	char full[1024];
	const char *home = getenv("HOME");
	if (!home || path[0] == '/'
		|| snprintf(full, sizeof full, "%s/Documents/%s", home, path) >= (int)sizeof full) {
		free(rgb);
		return 0;
	}
	for (char *p = full + strlen(home) + 1; *p; p++) {
		if (*p != '/') continue;
		*p = 0;
		int made = mkdir(full, 0755) == 0 || errno == EEXIST;
		*p = '/';
		if (!made) { free(rgb); return 0; }
	}
	path = full;
#endif
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

void voidCaptureExit(int code) {
#if defined(__EMSCRIPTEN__)
	// A browser has no process to exit: the page's driver (scripts/webGolden.mjs) waits for
	// this flag, then reads the PNG out of the in-memory file system.
	EM_ASM({ window.voidDone = $0; }, code);
	emscripten_force_exit(code);
#else
	exit(code);
#endif
}
