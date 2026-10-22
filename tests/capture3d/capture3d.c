// Scratch readback: copies the resolved swapchain buffer (D3D11, or the macOS Metal drawable) to a PPM
// before Present.
#include <stdio.h>
#include <stdlib.h>
#include "capture3d.h"

static FILE *openFrame(int32_t frame, char *path, size_t size, unsigned width, unsigned height) {
	const char *prefix = getenv("CAPTURE_PREFIX");
	snprintf(path, size, "%s_%d.ppm", prefix ? prefix : "out/tmp/capture/frame", frame);
	FILE *file = fopen(path, "wb");
	if (file) fprintf(file, "P6\n%u %u\n255\n", width, height);
	return file;
}

#if defined(__APPLE__)
int voidFbWidth(void);
int voidFbHeight(void);
int voidMetalReadDrawable(uint8_t *rgba, int width, int height);

void captureSwapchain(int32_t frame) {
	const int width = voidFbWidth(), height = voidFbHeight();
	uint8_t *rgba = (uint8_t *)malloc((size_t)width * (size_t)height * 4u);
	if (!rgba || !voidMetalReadDrawable(rgba, width, height)) { fprintf(stderr, "Metal drawable readback failed\n"); free(rgba); return; }
	char path[512];
	FILE *file = openFrame(frame, path, sizeof path, (unsigned)width, (unsigned)height);
	for (size_t i = 0; i < (size_t)width * (size_t)height; i++) fwrite(rgba + i * 4, 1, 3, file);
	fclose(file);
	free(rgba);
	fprintf(stderr, "captured %s (%dx%d, Metal BGRA8)\n", path, width, height);
}
#else
#define COBJMACROS
#include <d3d11.h>
#include <dxgi.h>

void *voidD3d11Device(void);
void *voidD3d11Context(void);
void *voidWindowSwapChain(void);

static const GUID TEXTURE2D_IID = {0x6f15aaf2, 0xd208, 0x4e89, {0x9a, 0xb4, 0x48, 0x95, 0x35, 0xd3, 0x4f, 0x9c}};

void captureSwapchain(int32_t frame) {
	IDXGISwapChain *swapChain = (IDXGISwapChain *)voidWindowSwapChain();
	ID3D11Device *device = (ID3D11Device *)voidD3d11Device();
	ID3D11DeviceContext *context = (ID3D11DeviceContext *)voidD3d11Context();
	ID3D11Texture2D *back = NULL;
	if (FAILED(IDXGISwapChain_GetBuffer(swapChain, 0, &TEXTURE2D_IID, (void **)&back))) { fprintf(stderr, "GetBuffer failed\n"); return; }
	D3D11_TEXTURE2D_DESC desc;
	ID3D11Texture2D_GetDesc(back, &desc);
	desc.Usage = D3D11_USAGE_STAGING;
	desc.BindFlags = 0;
	desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
	desc.MiscFlags = 0;
	ID3D11Texture2D *staging = NULL;
	ID3D11Device_CreateTexture2D(device, &desc, NULL, &staging);
	ID3D11DeviceContext_CopyResource(context, (ID3D11Resource *)staging, (ID3D11Resource *)back);
	D3D11_MAPPED_SUBRESOURCE mapped;
	ID3D11DeviceContext_Map(context, (ID3D11Resource *)staging, 0, D3D11_MAP_READ, 0, &mapped);
	char path[512];
	FILE *file = openFrame(frame, path, sizeof path, desc.Width, desc.Height);
	for (UINT y = 0; y < desc.Height; y++) {
		const uint8_t *row = (const uint8_t *)mapped.pData + y * mapped.RowPitch;
		for (UINT x = 0; x < desc.Width; x++) {
			uint8_t rgb[3] = {row[x * 4 + 2], row[x * 4 + 1], row[x * 4 + 0]};
			fwrite(rgb, 1, 3, file);
		}
	}
	fclose(file);
	ID3D11DeviceContext_Unmap(context, (ID3D11Resource *)staging, 0);
	ID3D11Texture2D_Release(staging);
	ID3D11Texture2D_Release(back);
	fprintf(stderr, "captured %s (%ux%u, format %d)\n", path, desc.Width, desc.Height, (int)desc.Format);
}
#endif

void captureQuit(void) { exit(0); }
