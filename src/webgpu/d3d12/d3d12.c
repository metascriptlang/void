#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d12.h>
#include <d3d12sdklayers.h>
#include <dxgi1_6.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include "d3d12.h"

#define DEVICE(d) ((ID3D12Device *)(uintptr_t)(d))
#define QUEUE(q) ((ID3D12CommandQueue *)(uintptr_t)(q))
#define FENCE(f) ((ID3D12Fence *)(uintptr_t)(f))
#define ALLOCATOR(a) ((ID3D12CommandAllocator *)(uintptr_t)(a))
#define LIST(l) ((ID3D12GraphicsCommandList *)(uintptr_t)(l))
#define HANDLE_OF(e) ((HANDLE)(uintptr_t)(e))
#define NATIVE(p) ((uint64_t)(uintptr_t)(p))

static char s_error[512];
static char s_adapter[256];

static int32_t fail(int32_t code, const char *format, ...) {
	va_list args;
	va_start(args, format);
	vsnprintf(s_error, sizeof s_error, format, args);
	va_end(args);
	return code;
}

static int32_t failCall(const char *call, HRESULT hr) {
	int32_t code = hr == E_OUTOFMEMORY ? DX12_OUT_OF_MEMORY
		: hr == DXGI_ERROR_DEVICE_REMOVED || hr == DXGI_ERROR_DEVICE_HUNG || hr == DXGI_ERROR_DEVICE_RESET
			|| hr == DXGI_ERROR_DRIVER_INTERNAL_ERROR ? DX12_DEVICE_REMOVED
		: DX12_ERROR_CALL;
	return fail(code, "%s returned HRESULT 0x%08lX", call, (unsigned long)hr);
}

const char *dx12Error(void) { return s_error; }

static int32_t debugFilter(ID3D12Device *device) {
	ID3D12InfoQueue *info = NULL;
	HRESULT hr = ID3D12Device_QueryInterface(device, &IID_ID3D12InfoQueue, (void **)&info);
	if (FAILED(hr)) return fail(DX12_ERROR_DEBUG_LAYER, "ID3D12Device::QueryInterface(ID3D12InfoQueue) returned HRESULT 0x%08lX", (unsigned long)hr);
	D3D12_MESSAGE_SEVERITY hidden[] = { D3D12_MESSAGE_SEVERITY_INFO, D3D12_MESSAGE_SEVERITY_MESSAGE };
	D3D12_INFO_QUEUE_FILTER filter = {0};
	filter.DenyList.NumSeverities = 2;
	filter.DenyList.pSeverityList = hidden;
	hr = ID3D12InfoQueue_PushStorageFilter(info, &filter);
	if (SUCCEEDED(hr)) ID3D12InfoQueue_ClearStoredMessages(info);
	ID3D12InfoQueue_Release(info);
	return FAILED(hr) ? failCall("ID3D12InfoQueue::PushStorageFilter", hr) : DX12_OK;
}

static int32_t hardwareDevice(IDXGIFactory4 *factory, IDXGIAdapter1 **adapter, ID3D12Device **device) {
	IDXGIAdapter1 *candidate = NULL;
	for (UINT i = 0; IDXGIFactory4_EnumAdapters1(factory, i, &candidate) != DXGI_ERROR_NOT_FOUND; i++) {
		DXGI_ADAPTER_DESC1 desc;
		if (SUCCEEDED(IDXGIAdapter1_GetDesc1(candidate, &desc)) && !(desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE)
			&& SUCCEEDED(D3D12CreateDevice((IUnknown *)candidate, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void **)device))) {
			*adapter = candidate;
			return DX12_OK;
		}
		IDXGIAdapter1_Release(candidate);
	}
	return fail(DX12_ERROR_ADAPTER, "no hardware adapter creates a D3D12 device at feature level 11_0");
}

static int32_t warpDevice(IDXGIFactory4 *factory, IDXGIAdapter1 **adapter, ID3D12Device **device) {
	HRESULT hr = IDXGIFactory4_EnumWarpAdapter(factory, &IID_IDXGIAdapter1, (void **)adapter);
	if (FAILED(hr)) return failCall("IDXGIFactory4::EnumWarpAdapter", hr);
	hr = D3D12CreateDevice((IUnknown *)*adapter, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void **)device);
	if (FAILED(hr)) {
		IDXGIAdapter1_Release(*adapter);
		*adapter = NULL;
		return failCall("D3D12CreateDevice on the WARP adapter", hr);
	}
	return DX12_OK;
}

int32_t dx12DeviceCreate(int32_t warp, int32_t debug, uint64_t *device, uint64_t *adapter) {
	*device = 0;
	*adapter = 0;
	UINT factoryFlags = 0;
	if (debug) {
		ID3D12Debug *controller = NULL;
		HRESULT hr = D3D12GetDebugInterface(&IID_ID3D12Debug, (void **)&controller);
		if (FAILED(hr)) {
			return fail(DX12_ERROR_DEBUG_LAYER, "D3D12GetDebugInterface returned HRESULT 0x%08lX: the D3D12 debug layer (Graphics Tools) is not installed",
				(unsigned long)hr);
		}
		ID3D12Debug_EnableDebugLayer(controller);
		ID3D12Debug_Release(controller);
		factoryFlags |= DXGI_CREATE_FACTORY_DEBUG;
	}
	IDXGIFactory4 *factory = NULL;
	HRESULT hr = CreateDXGIFactory2(factoryFlags, &IID_IDXGIFactory4, (void **)&factory);
	if (FAILED(hr)) return failCall("CreateDXGIFactory2", hr);
	IDXGIAdapter1 *chosen = NULL;
	ID3D12Device *created = NULL;
	int32_t status = warp ? warpDevice(factory, &chosen, &created) : hardwareDevice(factory, &chosen, &created);
	IDXGIFactory4_Release(factory);
	if (status == DX12_OK && debug) status = debugFilter(created);
	if (status != DX12_OK) {
		if (created) ID3D12Device_Release(created);
		if (chosen) IDXGIAdapter1_Release(chosen);
		return status;
	}
	*device = NATIVE(created);
	*adapter = NATIVE(chosen);
	return DX12_OK;
}

int32_t dx12InfoDrain(uint64_t device, uint64_t *count) {
	*count = 0;
	ID3D12InfoQueue *info = NULL;
	HRESULT hr = ID3D12Device_QueryInterface(DEVICE(device), &IID_ID3D12InfoQueue, (void **)&info);
	if (FAILED(hr)) return fail(DX12_ERROR_DEBUG_LAYER, "the device has no ID3D12InfoQueue: it was created without the debug layer");
	UINT64 stored = ID3D12InfoQueue_GetNumStoredMessagesAllowedByRetrievalFilter(info);
	for (UINT64 i = 0; i < stored; i++) {
		SIZE_T length = 0;
		if (FAILED(ID3D12InfoQueue_GetMessage(info, i, NULL, &length))) continue;
		D3D12_MESSAGE *message = (D3D12_MESSAGE *)malloc(length);
		if (message == NULL) break;
		if (SUCCEEDED(ID3D12InfoQueue_GetMessage(info, i, message, &length))) fprintf(stderr, "d3d12 debug layer: %s\n", message->pDescription);
		free(message);
	}
	fflush(stderr);
	ID3D12InfoQueue_ClearStoredMessages(info);
	ID3D12InfoQueue_Release(info);
	*count = (uint64_t)stored;
	return DX12_OK;
}

int32_t dx12AdapterDescribe(uint64_t adapter, uint32_t *vendorId, uint32_t *deviceId) {
	DXGI_ADAPTER_DESC1 desc;
	HRESULT hr = IDXGIAdapter1_GetDesc1((IDXGIAdapter1 *)(uintptr_t)adapter, &desc);
	if (FAILED(hr)) return failCall("IDXGIAdapter1::GetDesc1", hr);
	WideCharToMultiByte(CP_UTF8, 0, desc.Description, -1, s_adapter, sizeof s_adapter, NULL, NULL);
	*vendorId = desc.VendorId;
	*deviceId = desc.DeviceId;
	return DX12_OK;
}

const char *dx12AdapterDescription(void) { return s_adapter; }

int32_t dx12QueueCreate(uint64_t device, uint64_t *queue) {
	D3D12_COMMAND_QUEUE_DESC desc = {0};
	desc.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
	desc.Priority = D3D12_COMMAND_QUEUE_PRIORITY_NORMAL;
	desc.Flags = D3D12_COMMAND_QUEUE_FLAG_NONE;
	ID3D12CommandQueue *created = NULL;
	HRESULT hr = ID3D12Device_CreateCommandQueue(DEVICE(device), &desc, &IID_ID3D12CommandQueue, (void **)&created);
	*queue = NATIVE(created);
	return FAILED(hr) ? failCall("ID3D12Device::CreateCommandQueue", hr) : DX12_OK;
}

int32_t dx12QueueSignal(uint64_t queue, uint64_t fence, uint64_t value) {
	HRESULT hr = ID3D12CommandQueue_Signal(QUEUE(queue), FENCE(fence), value);
	return FAILED(hr) ? failCall("ID3D12CommandQueue::Signal", hr) : DX12_OK;
}

int32_t dx12QueueExecute(uint64_t queue, uint64_t list) {
	ID3D12CommandList *lists[] = { (ID3D12CommandList *)LIST(list) };
	ID3D12CommandQueue_ExecuteCommandLists(QUEUE(queue), 1, lists);
	return DX12_OK;
}

int32_t dx12FenceCreate(uint64_t device, uint64_t *fence, uint64_t *event) {
	*fence = 0;
	*event = 0;
	ID3D12Fence *created = NULL;
	HRESULT hr = ID3D12Device_CreateFence(DEVICE(device), 0, D3D12_FENCE_FLAG_NONE, &IID_ID3D12Fence, (void **)&created);
	if (FAILED(hr)) return failCall("ID3D12Device::CreateFence", hr);
	HANDLE handle = CreateEventA(NULL, FALSE, FALSE, NULL);
	if (handle == NULL) {
		ID3D12Fence_Release(created);
		return fail(DX12_ERROR_CALL, "CreateEvent failed with error %lu", GetLastError());
	}
	*fence = NATIVE(created);
	*event = NATIVE(handle);
	return DX12_OK;
}

int32_t dx12FenceCompleted(uint64_t fence, uint64_t *value) {
	*value = ID3D12Fence_GetCompletedValue(FENCE(fence));
	return *value == UINT64_MAX ? fail(DX12_DEVICE_REMOVED, "ID3D12Fence::GetCompletedValue returned UINT64_MAX: the device was removed") : DX12_OK;
}

int32_t dx12FenceWait(uint64_t fence, uint64_t event, uint64_t value) {
	uint64_t completed = 0;
	int32_t status = dx12FenceCompleted(fence, &completed);
	if (status != DX12_OK || completed >= value) return status;
	HRESULT hr = ID3D12Fence_SetEventOnCompletion(FENCE(fence), value, HANDLE_OF(event));
	if (FAILED(hr)) return failCall("ID3D12Fence::SetEventOnCompletion", hr);
	if (WaitForSingleObject(HANDLE_OF(event), INFINITE) != WAIT_OBJECT_0) {
		return fail(DX12_ERROR_CALL, "WaitForSingleObject on the fence event failed with error %lu", GetLastError());
	}
	return dx12FenceCompleted(fence, &completed);
}

int32_t dx12EventClose(uint64_t event) {
	if (!CloseHandle(HANDLE_OF(event))) return fail(DX12_ERROR_CALL, "CloseHandle on the fence event failed with error %lu", GetLastError());
	return DX12_OK;
}

int32_t dx12AllocatorCreate(uint64_t device, uint64_t *allocator) {
	ID3D12CommandAllocator *created = NULL;
	HRESULT hr = ID3D12Device_CreateCommandAllocator(DEVICE(device), D3D12_COMMAND_LIST_TYPE_DIRECT, &IID_ID3D12CommandAllocator, (void **)&created);
	*allocator = NATIVE(created);
	return FAILED(hr) ? failCall("ID3D12Device::CreateCommandAllocator", hr) : DX12_OK;
}

int32_t dx12AllocatorReset(uint64_t allocator) {
	HRESULT hr = ID3D12CommandAllocator_Reset(ALLOCATOR(allocator));
	return FAILED(hr) ? failCall("ID3D12CommandAllocator::Reset", hr) : DX12_OK;
}

int32_t dx12ListCreate(uint64_t device, uint64_t allocator, uint64_t *list) {
	ID3D12GraphicsCommandList *created = NULL;
	HRESULT hr = ID3D12Device_CreateCommandList(DEVICE(device), 0, D3D12_COMMAND_LIST_TYPE_DIRECT, ALLOCATOR(allocator), NULL,
		&IID_ID3D12GraphicsCommandList, (void **)&created);
	*list = NATIVE(created);
	return FAILED(hr) ? failCall("ID3D12Device::CreateCommandList", hr) : DX12_OK;
}

int32_t dx12ListReset(uint64_t list, uint64_t allocator) {
	HRESULT hr = ID3D12GraphicsCommandList_Reset(LIST(list), ALLOCATOR(allocator), NULL);
	return FAILED(hr) ? failCall("ID3D12GraphicsCommandList::Reset", hr) : DX12_OK;
}

int32_t dx12ListClose(uint64_t list) {
	HRESULT hr = ID3D12GraphicsCommandList_Close(LIST(list));
	return FAILED(hr) ? failCall("ID3D12GraphicsCommandList::Close", hr) : DX12_OK;
}

int32_t dx12Release(uint64_t object) {
	if (object != 0) IUnknown_Release((IUnknown *)(uintptr_t)object);
	return DX12_OK;
}
