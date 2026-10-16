#include "swapChainVisual.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <dcomp.h>
#include <cstdio>

extern "C" void *swapChainVisualAttach(void *device, void *root, long long swapChain) {
	auto *dcomp = static_cast<IDCompositionDevice *>(device);
	auto *parent = static_cast<IDCompositionVisual *>(root);
	if (dcomp == nullptr || parent == nullptr || swapChain == 0) return nullptr;
	IDCompositionVisual *visual = nullptr;
	HRESULT hr = dcomp->CreateVisual(&visual);
	if (SUCCEEDED(hr)) hr = visual->SetContent(reinterpret_cast<IUnknown *>(swapChain));
	// With a NULL reference AddVisual inverts insertAbove: FALSE is in front of every sibling
	// (ion/docs/WINDOW-CONTENT.md "Traps", measured 2026-10-15).
	if (SUCCEEDED(hr)) hr = parent->AddVisual(visual, FALSE, nullptr);
	if (FAILED(hr)) {
		fprintf(stderr, "ionViews: attaching a swapchain failed, HRESULT 0x%08lx\n", (unsigned long)hr);
		if (visual != nullptr) visual->Release();
		return nullptr;
	}
	return visual;
}
