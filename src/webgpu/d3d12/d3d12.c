#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d12.h>
#include <d3d12sdklayers.h>
#include <d3dcompiler.h>
#include <dxgi1_6.h>
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "d3d12.h"

#define DEVICE(d) ((ID3D12Device *)(uintptr_t)(d))
#define QUEUE(q) ((ID3D12CommandQueue *)(uintptr_t)(q))
#define FENCE(f) ((ID3D12Fence *)(uintptr_t)(f))
#define ALLOCATOR(a) ((ID3D12CommandAllocator *)(uintptr_t)(a))
#define LIST(l) ((ID3D12GraphicsCommandList *)(uintptr_t)(l))
#define RESOURCE(r) ((ID3D12Resource *)(uintptr_t)(r))
#define HANDLE_OF(e) ((HANDLE)(uintptr_t)(e))
#define NATIVE(p) ((uint64_t)(uintptr_t)(p))

static char s_error[512];
static char s_adapter[256];
static D3D12_RESOURCE_BARRIER *s_barriers;
static uint32_t s_barrierCount;
static uint32_t s_barrierCapacity;

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
	D3D12_MESSAGE_ID silenced[] = {
		D3D12_MESSAGE_ID_CLEARRENDERTARGETVIEW_MISMATCHINGCLEARVALUE,
		D3D12_MESSAGE_ID_CLEARDEPTHSTENCILVIEW_MISMATCHINGCLEARVALUE,
		D3D12_MESSAGE_ID_DRAW_EMPTY_SCISSOR_RECTANGLE,
	};
	D3D12_INFO_QUEUE_FILTER filter = {0};
	filter.DenyList.NumSeverities = 2;
	filter.DenyList.pSeverityList = hidden;
	filter.DenyList.NumIDs = sizeof silenced / sizeof silenced[0];
	filter.DenyList.pIDList = silenced;
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

int32_t dx12BufferCreate(uint64_t device, uint64_t size, int32_t heap, uint32_t state, int32_t unordered, uint64_t *resource) {
	*resource = 0;
	D3D12_HEAP_PROPERTIES properties = {0};
	properties.Type = (D3D12_HEAP_TYPE)heap;
	D3D12_RESOURCE_DESC desc = {0};
	desc.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
	desc.Width = size;
	desc.Height = 1;
	desc.DepthOrArraySize = 1;
	desc.MipLevels = 1;
	desc.SampleDesc.Count = 1;
	desc.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
	desc.Flags = unordered ? D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS : D3D12_RESOURCE_FLAG_NONE;
	ID3D12Resource *created = NULL;
	HRESULT hr = ID3D12Device_CreateCommittedResource(DEVICE(device), &properties, D3D12_HEAP_FLAG_NONE, &desc, (D3D12_RESOURCE_STATES)state, NULL,
		&IID_ID3D12Resource, (void **)&created);
	if (FAILED(hr)) return failCall("ID3D12Device::CreateCommittedResource for a buffer", hr);
	*resource = NATIVE(created);
	return DX12_OK;
}

int32_t dx12ResourceAddress(uint64_t resource, uint64_t *address) {
	*address = ID3D12Resource_GetGPUVirtualAddress(RESOURCE(resource));
	return DX12_OK;
}

int32_t dx12ResourceMap(uint64_t resource, uint64_t readBegin, uint64_t readEnd, uint64_t *pointer) {
	*pointer = 0;
	D3D12_RANGE range = { (SIZE_T)readBegin, (SIZE_T)readEnd };
	void *data = NULL;
	HRESULT hr = ID3D12Resource_Map(RESOURCE(resource), 0, &range, &data);
	if (FAILED(hr)) return failCall("ID3D12Resource::Map", hr);
	*pointer = NATIVE(data);
	return DX12_OK;
}

int32_t dx12ResourceUnmap(uint64_t resource, uint64_t writtenBegin, uint64_t writtenEnd) {
	D3D12_RANGE range = { (SIZE_T)writtenBegin, (SIZE_T)writtenEnd };
	ID3D12Resource_Unmap(RESOURCE(resource), 0, &range);
	return DX12_OK;
}

int32_t dx12MemoryWrite(uint64_t pointer, void *data, uint64_t bytes) {
	memcpy((void *)(uintptr_t)pointer, data, (size_t)bytes);
	return DX12_OK;
}

int32_t dx12MemoryRead(uint64_t pointer, void *out, uint64_t bytes) {
	memcpy(out, (const void *)(uintptr_t)pointer, (size_t)bytes);
	return DX12_OK;
}

int32_t dx12MemoryWriteRows(uint64_t pointer, void *data, uint64_t dataOffset, uint64_t dataPitch, uint64_t rowBytes, uint64_t rowPitch, uint32_t rows) {
	uint8_t *target = (uint8_t *)(uintptr_t)pointer;
	const uint8_t *source = (const uint8_t *)data + dataOffset;
	for (uint32_t row = 0; row < rows; row++) memcpy(target + row * rowPitch, source + row * dataPitch, (size_t)rowBytes);
	return DX12_OK;
}

int32_t dx12TextureCreate(uint64_t device, int32_t volume, uint32_t width, uint32_t height, uint32_t depthOrArraySize, uint32_t mipLevels, int32_t format, uint32_t sampleCount, uint32_t flags, uint64_t *resource) {
	*resource = 0;
	D3D12_HEAP_PROPERTIES properties = {0};
	properties.Type = D3D12_HEAP_TYPE_DEFAULT;
	D3D12_RESOURCE_DESC desc = {0};
	desc.Dimension = volume ? D3D12_RESOURCE_DIMENSION_TEXTURE3D : D3D12_RESOURCE_DIMENSION_TEXTURE2D;
	desc.Width = width;
	desc.Height = height;
	desc.DepthOrArraySize = (UINT16)depthOrArraySize;
	desc.MipLevels = (UINT16)mipLevels;
	desc.Format = (DXGI_FORMAT)format;
	desc.SampleDesc.Count = sampleCount;
	desc.Layout = D3D12_TEXTURE_LAYOUT_UNKNOWN;
	desc.Flags = (D3D12_RESOURCE_FLAGS)flags;
	ID3D12Resource *created = NULL;
	HRESULT hr = ID3D12Device_CreateCommittedResource(DEVICE(device), &properties, D3D12_HEAP_FLAG_NONE, &desc, D3D12_RESOURCE_STATE_COMMON, NULL,
		&IID_ID3D12Resource, (void **)&created);
	if (FAILED(hr)) return failCall("ID3D12Device::CreateCommittedResource for a texture", hr);
	*resource = NATIVE(created);
	return DX12_OK;
}

int32_t dx12CopyableFootprint(uint64_t device, int32_t format, uint32_t width, uint32_t height, uint32_t *rowPitch, uint32_t *rows, uint64_t *rowBytes, uint64_t *totalBytes) {
	D3D12_RESOURCE_DESC desc = {0};
	desc.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
	desc.Width = width;
	desc.Height = height;
	desc.DepthOrArraySize = 1;
	desc.MipLevels = 1;
	desc.Format = (DXGI_FORMAT)format;
	desc.SampleDesc.Count = 1;
	desc.Layout = D3D12_TEXTURE_LAYOUT_UNKNOWN;
	D3D12_PLACED_SUBRESOURCE_FOOTPRINT footprint;
	UINT rowCount = 0;
	UINT64 rowSize = 0;
	UINT64 total = UINT64_MAX;
	ID3D12Device_GetCopyableFootprints(DEVICE(device), &desc, 0, 1, 0, &footprint, &rowCount, &rowSize, &total);
	if (total == UINT64_MAX) return fail(DX12_ERROR_CALL, "ID3D12Device::GetCopyableFootprints refused a %ux%u footprint of DXGI format %d", width, height, format);
	*rowPitch = footprint.Footprint.RowPitch;
	*rows = rowCount;
	*rowBytes = rowSize;
	*totalBytes = total;
	return DX12_OK;
}

int32_t dx12FormatSupport(uint64_t device, int32_t format, uint32_t *support1, uint32_t *support2) {
	*support1 = 0;
	*support2 = 0;
	D3D12_FEATURE_DATA_FORMAT_SUPPORT data = {0};
	data.Format = (DXGI_FORMAT)format;
	HRESULT hr = ID3D12Device_CheckFeatureSupport(DEVICE(device), D3D12_FEATURE_FORMAT_SUPPORT, &data, sizeof data);
	if (hr == E_FAIL || hr == E_INVALIDARG) return DX12_OK;
	if (FAILED(hr)) return failCall("ID3D12Device::CheckFeatureSupport(D3D12_FEATURE_FORMAT_SUPPORT)", hr);
	*support1 = (uint32_t)data.Support1;
	*support2 = (uint32_t)data.Support2;
	return DX12_OK;
}

int32_t dx12CopyBufferRegion(uint64_t list, uint64_t target, uint64_t targetOffset, uint64_t source, uint64_t sourceOffset, uint64_t bytes) {
	ID3D12GraphicsCommandList_CopyBufferRegion(LIST(list), RESOURCE(target), targetOffset, RESOURCE(source), sourceOffset, bytes);
	return DX12_OK;
}

static D3D12_TEXTURE_COPY_LOCATION subresourceLocation(uint64_t texture, uint32_t subresource) {
	D3D12_TEXTURE_COPY_LOCATION location = {0};
	location.pResource = RESOURCE(texture);
	location.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
	location.SubresourceIndex = subresource;
	return location;
}

int32_t dx12CopyBufferTexture(uint64_t list, int32_t toTexture, uint64_t texture, uint32_t subresource, uint32_t x, uint32_t y, uint32_t z, uint64_t buffer, uint64_t offset, int32_t format, uint32_t footprintWidth, uint32_t footprintHeight, uint32_t rowPitch, uint32_t bufferX, uint32_t bufferY, uint32_t width, uint32_t height) {
	D3D12_TEXTURE_COPY_LOCATION textureLocation = subresourceLocation(texture, subresource);
	D3D12_TEXTURE_COPY_LOCATION bufferLocation = {0};
	bufferLocation.pResource = RESOURCE(buffer);
	bufferLocation.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
	bufferLocation.PlacedFootprint.Offset = offset;
	bufferLocation.PlacedFootprint.Footprint.Format = (DXGI_FORMAT)format;
	bufferLocation.PlacedFootprint.Footprint.Width = footprintWidth;
	bufferLocation.PlacedFootprint.Footprint.Height = footprintHeight;
	bufferLocation.PlacedFootprint.Footprint.Depth = 1;
	bufferLocation.PlacedFootprint.Footprint.RowPitch = rowPitch;
	if (toTexture) {
		D3D12_BOX box = { bufferX, bufferY, 0, bufferX + width, bufferY + height, 1 };
		ID3D12GraphicsCommandList_CopyTextureRegion(LIST(list), &textureLocation, x, y, z, &bufferLocation, &box);
	} else {
		D3D12_BOX box = { x, y, z, x + width, y + height, z + 1 };
		ID3D12GraphicsCommandList_CopyTextureRegion(LIST(list), &bufferLocation, bufferX, bufferY, 0, &textureLocation, &box);
	}
	return DX12_OK;
}

int32_t dx12CopyTexture(uint64_t list, uint64_t target, uint32_t targetSubresource, uint32_t targetX, uint32_t targetY, uint32_t targetZ, uint64_t source, uint32_t sourceSubresource, uint32_t sourceX, uint32_t sourceY, uint32_t sourceZ, uint32_t width, uint32_t height, uint32_t depth) {
	D3D12_TEXTURE_COPY_LOCATION targetLocation = subresourceLocation(target, targetSubresource);
	D3D12_TEXTURE_COPY_LOCATION sourceLocation = subresourceLocation(source, sourceSubresource);
	D3D12_BOX box = { sourceX, sourceY, sourceZ, sourceX + width, sourceY + height, sourceZ + depth };
	ID3D12GraphicsCommandList_CopyTextureRegion(LIST(list), &targetLocation, targetX, targetY, targetZ, &sourceLocation, &box);
	return DX12_OK;
}

static int32_t barrierSlot(D3D12_RESOURCE_BARRIER **barrier) {
	if (s_barrierCount == s_barrierCapacity) {
		uint32_t capacity = s_barrierCapacity > 0 ? s_barrierCapacity * 2 : 16;
		D3D12_RESOURCE_BARRIER *grown = realloc(s_barriers, sizeof *grown * capacity);
		if (grown == NULL) {
			s_barrierCount = 0;
			return fail(DX12_OUT_OF_MEMORY, "out of memory growing the resource barrier list to %u", capacity);
		}
		s_barriers = grown;
		s_barrierCapacity = capacity;
	}
	*barrier = &s_barriers[s_barrierCount++];
	memset(*barrier, 0, sizeof **barrier);
	return DX12_OK;
}

int32_t dx12BarrierTransition(uint64_t resource, uint32_t subresource, uint32_t before, uint32_t after) {
	D3D12_RESOURCE_BARRIER *barrier = NULL;
	int32_t status = barrierSlot(&barrier);
	if (status != DX12_OK) return status;
	barrier->Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
	barrier->Transition.pResource = RESOURCE(resource);
	barrier->Transition.Subresource = subresource;
	barrier->Transition.StateBefore = (D3D12_RESOURCE_STATES)before;
	barrier->Transition.StateAfter = (D3D12_RESOURCE_STATES)after;
	return DX12_OK;
}

int32_t dx12BarrierFlush(uint64_t list, int32_t uav) {
	if (uav) {
		D3D12_RESOURCE_BARRIER *barrier = NULL;
		int32_t status = barrierSlot(&barrier);
		if (status != DX12_OK) return status;
		barrier->Type = D3D12_RESOURCE_BARRIER_TYPE_UAV;
	}
	if (s_barrierCount > 0) ID3D12GraphicsCommandList_ResourceBarrier(LIST(list), s_barrierCount, s_barriers);
	s_barrierCount = 0;
	return DX12_OK;
}

int32_t dx12DescriptorHeapCreate(uint64_t device, int32_t type, uint32_t count, int32_t shaderVisible, uint64_t *heap, uint64_t *cpuStart, uint64_t *gpuStart, uint32_t *increment) {
	*heap = 0;
	*cpuStart = 0;
	*gpuStart = 0;
	*increment = 0;
	D3D12_DESCRIPTOR_HEAP_DESC desc = {0};
	desc.Type = (D3D12_DESCRIPTOR_HEAP_TYPE)type;
	desc.NumDescriptors = count;
	desc.Flags = shaderVisible ? D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE : D3D12_DESCRIPTOR_HEAP_FLAG_NONE;
	ID3D12DescriptorHeap *created = NULL;
	HRESULT hr = ID3D12Device_CreateDescriptorHeap(DEVICE(device), &desc, &IID_ID3D12DescriptorHeap, (void **)&created);
	if (FAILED(hr)) return failCall("ID3D12Device::CreateDescriptorHeap", hr);
	D3D12_CPU_DESCRIPTOR_HANDLE cpu;
	created->lpVtbl->GetCPUDescriptorHandleForHeapStart(created, &cpu);
	if (shaderVisible) {
		D3D12_GPU_DESCRIPTOR_HANDLE gpu;
		created->lpVtbl->GetGPUDescriptorHandleForHeapStart(created, &gpu);
		*gpuStart = gpu.ptr;
	}
	*heap = NATIVE(created);
	*cpuStart = (uint64_t)cpu.ptr;
	*increment = ID3D12Device_GetDescriptorHandleIncrementSize(DEVICE(device), desc.Type);
	return DX12_OK;
}

static D3D12_CPU_DESCRIPTOR_HANDLE cpuHandle(uint64_t handle) {
	D3D12_CPU_DESCRIPTOR_HANDLE cpu = { (SIZE_T)handle };
	return cpu;
}

int32_t dx12DescriptorsCopy(uint64_t device, uint32_t count, uint64_t target, uint64_t source, int32_t type) {
	ID3D12Device_CopyDescriptorsSimple(DEVICE(device), count, cpuHandle(target), cpuHandle(source), (D3D12_DESCRIPTOR_HEAP_TYPE)type);
	return DX12_OK;
}

#define DX12_VIEW_2D 0
#define DX12_VIEW_2D_ARRAY 1
#define DX12_VIEW_CUBE 2
#define DX12_VIEW_CUBE_ARRAY 3
#define DX12_VIEW_3D 4

int32_t dx12TextureSrv(uint64_t device, uint64_t resource, int32_t format, int32_t dimension, int32_t multisampled, uint32_t baseMip, uint32_t mipCount, uint32_t baseLayer, uint32_t layerCount, uint64_t handle) {
	D3D12_SHADER_RESOURCE_VIEW_DESC desc = {0};
	desc.Format = (DXGI_FORMAT)format;
	desc.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
	if (multisampled && dimension == DX12_VIEW_2D) {
		desc.ViewDimension = D3D12_SRV_DIMENSION_TEXTURE2DMS;
	} else if (multisampled && dimension == DX12_VIEW_2D_ARRAY) {
		desc.ViewDimension = D3D12_SRV_DIMENSION_TEXTURE2DMSARRAY;
		desc.Texture2DMSArray.FirstArraySlice = baseLayer;
		desc.Texture2DMSArray.ArraySize = layerCount;
	} else if (multisampled) {
		return fail(DX12_ERROR_CALL, "a multisampled shader resource view has view dimension %d, which is neither 2d nor 2d-array", dimension);
	} else if (dimension == DX12_VIEW_2D) {
		desc.ViewDimension = D3D12_SRV_DIMENSION_TEXTURE2D;
		desc.Texture2D.MostDetailedMip = baseMip;
		desc.Texture2D.MipLevels = mipCount;
	} else if (dimension == DX12_VIEW_2D_ARRAY) {
		desc.ViewDimension = D3D12_SRV_DIMENSION_TEXTURE2DARRAY;
		desc.Texture2DArray.MostDetailedMip = baseMip;
		desc.Texture2DArray.MipLevels = mipCount;
		desc.Texture2DArray.FirstArraySlice = baseLayer;
		desc.Texture2DArray.ArraySize = layerCount;
	} else if (dimension == DX12_VIEW_CUBE) {
		desc.ViewDimension = D3D12_SRV_DIMENSION_TEXTURECUBE;
		desc.TextureCube.MostDetailedMip = baseMip;
		desc.TextureCube.MipLevels = mipCount;
	} else if (dimension == DX12_VIEW_CUBE_ARRAY) {
		desc.ViewDimension = D3D12_SRV_DIMENSION_TEXTURECUBEARRAY;
		desc.TextureCubeArray.MostDetailedMip = baseMip;
		desc.TextureCubeArray.MipLevels = mipCount;
		desc.TextureCubeArray.First2DArrayFace = baseLayer;
		desc.TextureCubeArray.NumCubes = layerCount / 6;
	} else if (dimension == DX12_VIEW_3D) {
		desc.ViewDimension = D3D12_SRV_DIMENSION_TEXTURE3D;
		desc.Texture3D.MostDetailedMip = baseMip;
		desc.Texture3D.MipLevels = mipCount;
	} else {
		return fail(DX12_ERROR_CALL, "a shader resource view has the unknown view dimension %d", dimension);
	}
	ID3D12Device_CreateShaderResourceView(DEVICE(device), RESOURCE(resource), &desc, cpuHandle(handle));
	return DX12_OK;
}

int32_t dx12TextureUav(uint64_t device, uint64_t resource, int32_t format, int32_t dimension, uint32_t mip, uint32_t baseLayer, uint32_t layerCount, uint64_t handle) {
	D3D12_UNORDERED_ACCESS_VIEW_DESC desc = {0};
	desc.Format = (DXGI_FORMAT)format;
	if (dimension == DX12_VIEW_3D) {
		desc.ViewDimension = D3D12_UAV_DIMENSION_TEXTURE3D;
		desc.Texture3D.MipSlice = mip;
		desc.Texture3D.WSize = (UINT)-1;
	} else if (dimension == DX12_VIEW_2D_ARRAY) {
		desc.ViewDimension = D3D12_UAV_DIMENSION_TEXTURE2DARRAY;
		desc.Texture2DArray.MipSlice = mip;
		desc.Texture2DArray.FirstArraySlice = baseLayer;
		desc.Texture2DArray.ArraySize = layerCount;
	} else if (dimension == DX12_VIEW_2D) {
		desc.ViewDimension = D3D12_UAV_DIMENSION_TEXTURE2D;
		desc.Texture2D.MipSlice = mip;
	} else {
		return fail(DX12_ERROR_CALL, "an unordered access view has view dimension %d, which is not 2d, 2d-array or 3d", dimension);
	}
	ID3D12Device_CreateUnorderedAccessView(DEVICE(device), RESOURCE(resource), NULL, &desc, cpuHandle(handle));
	return DX12_OK;
}

int32_t dx12BufferSrv(uint64_t device, uint64_t resource, uint64_t offset, uint64_t bytes, uint64_t handle) {
	D3D12_SHADER_RESOURCE_VIEW_DESC desc = {0};
	desc.Format = DXGI_FORMAT_R32_TYPELESS;
	desc.ViewDimension = D3D12_SRV_DIMENSION_BUFFER;
	desc.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
	desc.Buffer.FirstElement = offset / 4;
	desc.Buffer.NumElements = (UINT)(bytes / 4);
	desc.Buffer.Flags = D3D12_BUFFER_SRV_FLAG_RAW;
	ID3D12Device_CreateShaderResourceView(DEVICE(device), RESOURCE(resource), &desc, cpuHandle(handle));
	return DX12_OK;
}

int32_t dx12BufferUav(uint64_t device, uint64_t resource, uint64_t offset, uint64_t bytes, uint64_t handle) {
	D3D12_UNORDERED_ACCESS_VIEW_DESC desc = {0};
	desc.Format = DXGI_FORMAT_R32_TYPELESS;
	desc.ViewDimension = D3D12_UAV_DIMENSION_BUFFER;
	desc.Buffer.FirstElement = offset / 4;
	desc.Buffer.NumElements = (UINT)(bytes / 4);
	desc.Buffer.Flags = D3D12_BUFFER_UAV_FLAG_RAW;
	ID3D12Device_CreateUnorderedAccessView(DEVICE(device), RESOURCE(resource), NULL, &desc, cpuHandle(handle));
	return DX12_OK;
}

int32_t dx12SamplerCreate(uint64_t device, int32_t filter, int32_t addressU, int32_t addressV, int32_t addressW, uint32_t maxAnisotropy, int32_t comparison, double minLod, double maxLod, uint64_t handle) {
	D3D12_SAMPLER_DESC desc = {0};
	desc.Filter = (D3D12_FILTER)filter;
	desc.AddressU = (D3D12_TEXTURE_ADDRESS_MODE)addressU;
	desc.AddressV = (D3D12_TEXTURE_ADDRESS_MODE)addressV;
	desc.AddressW = (D3D12_TEXTURE_ADDRESS_MODE)addressW;
	desc.MaxAnisotropy = maxAnisotropy;
	desc.ComparisonFunc = (D3D12_COMPARISON_FUNC)comparison;
	desc.BorderColor[3] = 1.0f;
	desc.MinLOD = (FLOAT)minLod;
	desc.MaxLOD = (FLOAT)maxLod;
	ID3D12Device_CreateSampler(DEVICE(device), &desc, cpuHandle(handle));
	return DX12_OK;
}

#define DX12_ROOT_PARAMETER_WORDS 5
#define DX12_ROOT_RANGE_WORDS 3
#define DX12_MAX_ROOT_PARAMETERS 64
#define DX12_MAX_ROOT_RANGES 256

int32_t dx12RootSignatureSerialize(const uint32_t *parameters, uint32_t parameterCount, const uint32_t *ranges, uint32_t rangeCount, uint32_t flags, uint64_t *blob, uint64_t *bytes) {
	*blob = 0;
	*bytes = 0;
	if (parameterCount > DX12_MAX_ROOT_PARAMETERS || rangeCount > DX12_MAX_ROOT_RANGES) {
		return fail(DX12_ERROR_CALL, "a root signature of %u parameters and %u ranges is over %d and %d", parameterCount, rangeCount, DX12_MAX_ROOT_PARAMETERS, DX12_MAX_ROOT_RANGES);
	}
	D3D12_ROOT_PARAMETER rootParameters[DX12_MAX_ROOT_PARAMETERS];
	D3D12_DESCRIPTOR_RANGE descriptorRanges[DX12_MAX_ROOT_RANGES];
	memset(rootParameters, 0, sizeof rootParameters);
	for (uint32_t r = 0; r < rangeCount; r++) {
		const uint32_t *words = ranges + r * DX12_ROOT_RANGE_WORDS;
		descriptorRanges[r].RangeType = (D3D12_DESCRIPTOR_RANGE_TYPE)words[0];
		descriptorRanges[r].NumDescriptors = 1;
		descriptorRanges[r].BaseShaderRegister = words[1];
		descriptorRanges[r].RegisterSpace = 0;
		descriptorRanges[r].OffsetInDescriptorsFromTableStart = words[2];
	}
	for (uint32_t p = 0; p < parameterCount; p++) {
		const uint32_t *words = parameters + p * DX12_ROOT_PARAMETER_WORDS;
		D3D12_ROOT_PARAMETER *parameter = &rootParameters[p];
		parameter->ParameterType = (D3D12_ROOT_PARAMETER_TYPE)words[0];
		parameter->ShaderVisibility = (D3D12_SHADER_VISIBILITY)words[1];
		if (parameter->ParameterType == D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE) {
			if (words[3] + words[4] > rangeCount) return fail(DX12_ERROR_CALL, "root parameter %u names ranges %u..%u of %u", p, words[3], words[3] + words[4], rangeCount);
			parameter->DescriptorTable.NumDescriptorRanges = words[4];
			parameter->DescriptorTable.pDescriptorRanges = descriptorRanges + words[3];
		} else if (parameter->ParameterType == D3D12_ROOT_PARAMETER_TYPE_CBV) {
			parameter->Descriptor.ShaderRegister = words[2];
			parameter->Descriptor.RegisterSpace = 0;
		} else {
			return fail(DX12_ERROR_CALL, "root parameter %u has type %u, which is neither a descriptor table nor a CBV", p, words[0]);
		}
	}
	D3D12_ROOT_SIGNATURE_DESC desc = {0};
	desc.NumParameters = parameterCount;
	desc.pParameters = rootParameters;
	desc.Flags = (D3D12_ROOT_SIGNATURE_FLAGS)flags;
	ID3DBlob *serialized = NULL;
	ID3DBlob *error = NULL;
	HRESULT hr = D3D12SerializeRootSignature(&desc, D3D_ROOT_SIGNATURE_VERSION_1_0, &serialized, &error);
	if (FAILED(hr)) {
		int32_t status = error
			? fail(DX12_ERROR_CALL, "D3D12SerializeRootSignature returned HRESULT 0x%08lX: %s", (unsigned long)hr, (const char *)ID3D10Blob_GetBufferPointer(error))
			: failCall("D3D12SerializeRootSignature", hr);
		if (error) ID3D10Blob_Release(error);
		return status;
	}
	if (error) ID3D10Blob_Release(error);
	*blob = NATIVE(serialized);
	*bytes = (uint64_t)ID3D10Blob_GetBufferSize(serialized);
	return DX12_OK;
}

int32_t dx12RootSignatureCreate(uint64_t device, uint64_t blob, uint64_t *signature) {
	*signature = 0;
	ID3DBlob *serialized = (ID3DBlob *)(uintptr_t)blob;
	ID3D12RootSignature *created = NULL;
	HRESULT hr = ID3D12Device_CreateRootSignature(DEVICE(device), 0, ID3D10Blob_GetBufferPointer(serialized), ID3D10Blob_GetBufferSize(serialized),
		&IID_ID3D12RootSignature, (void **)&created);
	if (FAILED(hr)) return failCall("ID3D12Device::CreateRootSignature", hr);
	*signature = NATIVE(created);
	return DX12_OK;
}

int32_t dx12SetDescriptorHeaps(uint64_t list, uint64_t views, uint64_t samplers) {
	ID3D12DescriptorHeap *heaps[] = { (ID3D12DescriptorHeap *)(uintptr_t)views, (ID3D12DescriptorHeap *)(uintptr_t)samplers };
	ID3D12GraphicsCommandList_SetDescriptorHeaps(LIST(list), 2, heaps);
	return DX12_OK;
}

int32_t dx12SetRootSignature(uint64_t list, int32_t compute, uint64_t signature) {
	ID3D12RootSignature *root = (ID3D12RootSignature *)(uintptr_t)signature;
	if (compute) ID3D12GraphicsCommandList_SetComputeRootSignature(LIST(list), root);
	else ID3D12GraphicsCommandList_SetGraphicsRootSignature(LIST(list), root);
	return DX12_OK;
}

int32_t dx12SetRootConstantBufferView(uint64_t list, int32_t compute, uint32_t parameter, uint64_t address) {
	if (compute) ID3D12GraphicsCommandList_SetComputeRootConstantBufferView(LIST(list), parameter, address);
	else ID3D12GraphicsCommandList_SetGraphicsRootConstantBufferView(LIST(list), parameter, address);
	return DX12_OK;
}

int32_t dx12SetRootDescriptorTable(uint64_t list, int32_t compute, uint32_t parameter, uint64_t handle) {
	D3D12_GPU_DESCRIPTOR_HANDLE gpu = { handle };
	if (compute) ID3D12GraphicsCommandList_SetComputeRootDescriptorTable(LIST(list), parameter, gpu);
	else ID3D12GraphicsCommandList_SetGraphicsRootDescriptorTable(LIST(list), parameter, gpu);
	return DX12_OK;
}

#define DX12_INPUT_ELEMENT_WORDS 5
#define DX12_TARGET_WORDS 10

enum {
	PIPELINE_TOPOLOGY_TYPE,
	PIPELINE_SAMPLE_COUNT,
	PIPELINE_CULL,
	PIPELINE_FRONT_CCW,
	PIPELINE_DEPTH_BIAS,
	PIPELINE_DSV_FORMAT,
	PIPELINE_DEPTH_ENABLE,
	PIPELINE_DEPTH_WRITE,
	PIPELINE_DEPTH_FUNC,
	PIPELINE_STENCIL_ENABLE,
	PIPELINE_STENCIL_READ_MASK,
	PIPELINE_STENCIL_WRITE_MASK,
	PIPELINE_FRONT_FAIL,
	PIPELINE_FRONT_DEPTH_FAIL,
	PIPELINE_FRONT_PASS,
	PIPELINE_FRONT_FUNC,
	PIPELINE_BACK_FAIL,
	PIPELINE_BACK_DEPTH_FAIL,
	PIPELINE_BACK_PASS,
	PIPELINE_BACK_FUNC,
	PIPELINE_STRIP_CUT,
	PIPELINE_WORDS,
};

int32_t dx12RenderPipelineCreate(uint64_t device, uint64_t signature, const uint8_t *vertex, uint64_t vertexBytes, const uint8_t *pixel, uint64_t pixelBytes,
	const int32_t *elements, uint32_t elementCount, const int32_t *targets, uint32_t targetCount, const int32_t *words, uint32_t wordCount,
	double depthBiasSlopeScale, double depthBiasClamp, uint64_t *pipeline) {
	*pipeline = 0;
	if (wordCount != PIPELINE_WORDS) return fail(DX12_ERROR_CALL, "a pipeline description has %u words, not %d", wordCount, PIPELINE_WORDS);
	if (elementCount > D3D12_IA_VERTEX_INPUT_STRUCTURE_ELEMENT_COUNT) return fail(DX12_ERROR_CALL, "a pipeline has %u vertex attributes, over %d", elementCount, D3D12_IA_VERTEX_INPUT_STRUCTURE_ELEMENT_COUNT);
	D3D12_INPUT_ELEMENT_DESC inputs[D3D12_IA_VERTEX_INPUT_STRUCTURE_ELEMENT_COUNT];
	for (uint32_t i = 0; i < elementCount; i++) {
		const int32_t *e = &elements[i * DX12_INPUT_ELEMENT_WORDS];
		inputs[i].SemanticName = "TEXCOORD";
		inputs[i].SemanticIndex = (UINT)e[0];
		inputs[i].Format = (DXGI_FORMAT)e[1];
		inputs[i].InputSlot = (UINT)e[2];
		inputs[i].AlignedByteOffset = (UINT)e[3];
		inputs[i].InputSlotClass = e[4] ? D3D12_INPUT_CLASSIFICATION_PER_INSTANCE_DATA : D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA;
		inputs[i].InstanceDataStepRate = e[4] ? 1 : 0;
	}
	D3D12_GRAPHICS_PIPELINE_STATE_DESC desc;
	memset(&desc, 0, sizeof desc);
	desc.pRootSignature = (ID3D12RootSignature *)(uintptr_t)signature;
	desc.VS.pShaderBytecode = vertex;
	desc.VS.BytecodeLength = (SIZE_T)vertexBytes;
	desc.PS.pShaderBytecode = pixel;
	desc.PS.BytecodeLength = (SIZE_T)pixelBytes;
	desc.BlendState.IndependentBlendEnable = TRUE;
	for (int i = 0; i < D3D12_SIMULTANEOUS_RENDER_TARGET_COUNT; i++) {
		D3D12_RENDER_TARGET_BLEND_DESC *target = &desc.BlendState.RenderTarget[i];
		target->SrcBlend = target->SrcBlendAlpha = D3D12_BLEND_ONE;
		target->DestBlend = target->DestBlendAlpha = D3D12_BLEND_ZERO;
		target->BlendOp = target->BlendOpAlpha = D3D12_BLEND_OP_ADD;
		target->LogicOp = D3D12_LOGIC_OP_NOOP;
		target->RenderTargetWriteMask = D3D12_COLOR_WRITE_ENABLE_ALL;
	}
	for (uint32_t i = 0; i < targetCount; i++) {
		const int32_t *t = &targets[i * DX12_TARGET_WORDS];
		if (t[0] < 0 || t[0] >= D3D12_SIMULTANEOUS_RENDER_TARGET_COUNT) return fail(DX12_ERROR_CALL, "colour target index %d is outside 0..7", t[0]);
		D3D12_RENDER_TARGET_BLEND_DESC *target = &desc.BlendState.RenderTarget[t[0]];
		target->BlendEnable = t[1] ? TRUE : FALSE;
		target->SrcBlend = (D3D12_BLEND)t[2];
		target->DestBlend = (D3D12_BLEND)t[3];
		target->BlendOp = (D3D12_BLEND_OP)t[4];
		target->SrcBlendAlpha = (D3D12_BLEND)t[5];
		target->DestBlendAlpha = (D3D12_BLEND)t[6];
		target->BlendOpAlpha = (D3D12_BLEND_OP)t[7];
		target->RenderTargetWriteMask = (UINT8)t[8];
		desc.RTVFormats[t[0]] = (DXGI_FORMAT)t[9];
		if ((UINT)t[0] + 1 > desc.NumRenderTargets) desc.NumRenderTargets = (UINT)t[0] + 1;
	}
	desc.SampleMask = UINT_MAX;
	desc.RasterizerState.FillMode = D3D12_FILL_MODE_SOLID;
	desc.RasterizerState.CullMode = (D3D12_CULL_MODE)words[PIPELINE_CULL];
	desc.RasterizerState.FrontCounterClockwise = words[PIPELINE_FRONT_CCW] ? TRUE : FALSE;
	desc.RasterizerState.DepthBias = (INT)words[PIPELINE_DEPTH_BIAS];
	desc.RasterizerState.DepthBiasClamp = (FLOAT)depthBiasClamp;
	desc.RasterizerState.SlopeScaledDepthBias = (FLOAT)depthBiasSlopeScale;
	desc.RasterizerState.DepthClipEnable = TRUE;
	desc.RasterizerState.MultisampleEnable = words[PIPELINE_SAMPLE_COUNT] > 1 ? TRUE : FALSE;
	desc.DepthStencilState.DepthEnable = words[PIPELINE_DEPTH_ENABLE] ? TRUE : FALSE;
	desc.DepthStencilState.DepthWriteMask = words[PIPELINE_DEPTH_WRITE] ? D3D12_DEPTH_WRITE_MASK_ALL : D3D12_DEPTH_WRITE_MASK_ZERO;
	desc.DepthStencilState.DepthFunc = (D3D12_COMPARISON_FUNC)words[PIPELINE_DEPTH_FUNC];
	desc.DepthStencilState.StencilEnable = words[PIPELINE_STENCIL_ENABLE] ? TRUE : FALSE;
	desc.DepthStencilState.StencilReadMask = (UINT8)words[PIPELINE_STENCIL_READ_MASK];
	desc.DepthStencilState.StencilWriteMask = (UINT8)words[PIPELINE_STENCIL_WRITE_MASK];
	desc.DepthStencilState.FrontFace.StencilFailOp = (D3D12_STENCIL_OP)words[PIPELINE_FRONT_FAIL];
	desc.DepthStencilState.FrontFace.StencilDepthFailOp = (D3D12_STENCIL_OP)words[PIPELINE_FRONT_DEPTH_FAIL];
	desc.DepthStencilState.FrontFace.StencilPassOp = (D3D12_STENCIL_OP)words[PIPELINE_FRONT_PASS];
	desc.DepthStencilState.FrontFace.StencilFunc = (D3D12_COMPARISON_FUNC)words[PIPELINE_FRONT_FUNC];
	desc.DepthStencilState.BackFace.StencilFailOp = (D3D12_STENCIL_OP)words[PIPELINE_BACK_FAIL];
	desc.DepthStencilState.BackFace.StencilDepthFailOp = (D3D12_STENCIL_OP)words[PIPELINE_BACK_DEPTH_FAIL];
	desc.DepthStencilState.BackFace.StencilPassOp = (D3D12_STENCIL_OP)words[PIPELINE_BACK_PASS];
	desc.DepthStencilState.BackFace.StencilFunc = (D3D12_COMPARISON_FUNC)words[PIPELINE_BACK_FUNC];
	desc.InputLayout.pInputElementDescs = elementCount > 0 ? inputs : NULL;
	desc.InputLayout.NumElements = elementCount;
	desc.IBStripCutValue = (D3D12_INDEX_BUFFER_STRIP_CUT_VALUE)words[PIPELINE_STRIP_CUT];
	desc.PrimitiveTopologyType = (D3D12_PRIMITIVE_TOPOLOGY_TYPE)words[PIPELINE_TOPOLOGY_TYPE];
	desc.DSVFormat = (DXGI_FORMAT)words[PIPELINE_DSV_FORMAT];
	desc.SampleDesc.Count = (UINT)words[PIPELINE_SAMPLE_COUNT];
	ID3D12PipelineState *created = NULL;
	HRESULT hr = ID3D12Device_CreateGraphicsPipelineState(DEVICE(device), &desc, &IID_ID3D12PipelineState, (void **)&created);
	if (FAILED(hr)) return failCall("ID3D12Device::CreateGraphicsPipelineState", hr);
	*pipeline = NATIVE(created);
	return DX12_OK;
}

int32_t dx12ComputePipelineCreate(uint64_t device, uint64_t signature, const uint8_t *compute, uint64_t computeBytes, uint64_t *pipeline) {
	*pipeline = 0;
	D3D12_COMPUTE_PIPELINE_STATE_DESC desc;
	memset(&desc, 0, sizeof desc);
	desc.pRootSignature = (ID3D12RootSignature *)(uintptr_t)signature;
	desc.CS.pShaderBytecode = compute;
	desc.CS.BytecodeLength = (SIZE_T)computeBytes;
	ID3D12PipelineState *created = NULL;
	HRESULT hr = ID3D12Device_CreateComputePipelineState(DEVICE(device), &desc, &IID_ID3D12PipelineState, (void **)&created);
	if (FAILED(hr)) return failCall("ID3D12Device::CreateComputePipelineState", hr);
	*pipeline = NATIVE(created);
	return DX12_OK;
}

int32_t dx12RenderTargetView(uint64_t device, uint64_t resource, int32_t format, int32_t dimension, int32_t multisampled, uint32_t mip, uint32_t layer, uint64_t handle) {
	D3D12_RENDER_TARGET_VIEW_DESC desc;
	memset(&desc, 0, sizeof desc);
	desc.Format = (DXGI_FORMAT)format;
	if (multisampled && dimension == DX12_VIEW_2D) {
		desc.ViewDimension = D3D12_RTV_DIMENSION_TEXTURE2DMS;
	} else if (multisampled && dimension == DX12_VIEW_2D_ARRAY) {
		desc.ViewDimension = D3D12_RTV_DIMENSION_TEXTURE2DMSARRAY;
		desc.Texture2DMSArray.FirstArraySlice = layer;
		desc.Texture2DMSArray.ArraySize = 1;
	} else if (multisampled) {
		return fail(DX12_ERROR_CALL, "a multisampled render target view has view dimension %d, which is neither 2d nor 2d-array", dimension);
	} else if (dimension == DX12_VIEW_2D) {
		desc.ViewDimension = D3D12_RTV_DIMENSION_TEXTURE2D;
		desc.Texture2D.MipSlice = mip;
	} else if (dimension == DX12_VIEW_2D_ARRAY) {
		desc.ViewDimension = D3D12_RTV_DIMENSION_TEXTURE2DARRAY;
		desc.Texture2DArray.MipSlice = mip;
		desc.Texture2DArray.FirstArraySlice = layer;
		desc.Texture2DArray.ArraySize = 1;
	} else if (dimension == DX12_VIEW_3D) {
		desc.ViewDimension = D3D12_RTV_DIMENSION_TEXTURE3D;
		desc.Texture3D.MipSlice = mip;
		desc.Texture3D.FirstWSlice = layer;
		desc.Texture3D.WSize = 1;
	} else {
		return fail(DX12_ERROR_CALL, "a render target view has view dimension %d, which is not 2d, 2d-array or 3d", dimension);
	}
	ID3D12Device_CreateRenderTargetView(DEVICE(device), RESOURCE(resource), &desc, cpuHandle(handle));
	return DX12_OK;
}

int32_t dx12DepthStencilView(uint64_t device, uint64_t resource, int32_t format, int32_t dimension, int32_t multisampled, uint32_t mip, uint32_t layer, uint64_t handle) {
	D3D12_DEPTH_STENCIL_VIEW_DESC desc;
	memset(&desc, 0, sizeof desc);
	desc.Format = (DXGI_FORMAT)format;
	if (multisampled && dimension == DX12_VIEW_2D) {
		desc.ViewDimension = D3D12_DSV_DIMENSION_TEXTURE2DMS;
	} else if (multisampled && dimension == DX12_VIEW_2D_ARRAY) {
		desc.ViewDimension = D3D12_DSV_DIMENSION_TEXTURE2DMSARRAY;
		desc.Texture2DMSArray.FirstArraySlice = layer;
		desc.Texture2DMSArray.ArraySize = 1;
	} else if (dimension == DX12_VIEW_2D && !multisampled) {
		desc.ViewDimension = D3D12_DSV_DIMENSION_TEXTURE2D;
		desc.Texture2D.MipSlice = mip;
	} else if (dimension == DX12_VIEW_2D_ARRAY && !multisampled) {
		desc.ViewDimension = D3D12_DSV_DIMENSION_TEXTURE2DARRAY;
		desc.Texture2DArray.MipSlice = mip;
		desc.Texture2DArray.FirstArraySlice = layer;
		desc.Texture2DArray.ArraySize = 1;
	} else {
		return fail(DX12_ERROR_CALL, "a depth stencil view has view dimension %d, which is neither 2d nor 2d-array", dimension);
	}
	ID3D12Device_CreateDepthStencilView(DEVICE(device), RESOURCE(resource), &desc, cpuHandle(handle));
	return DX12_OK;
}

int32_t dx12SetRenderTargets(uint64_t list, const uint64_t *targets, uint32_t count, uint64_t depth) {
	D3D12_CPU_DESCRIPTOR_HANDLE colors[D3D12_SIMULTANEOUS_RENDER_TARGET_COUNT];
	if (count > D3D12_SIMULTANEOUS_RENDER_TARGET_COUNT) return fail(DX12_ERROR_CALL, "%u render targets are over %d", count, D3D12_SIMULTANEOUS_RENDER_TARGET_COUNT);
	for (uint32_t i = 0; i < count; i++) colors[i] = cpuHandle(targets[i]);
	D3D12_CPU_DESCRIPTOR_HANDLE depthStencil = cpuHandle(depth);
	ID3D12GraphicsCommandList_OMSetRenderTargets(LIST(list), count, count > 0 ? colors : NULL, FALSE, depth != 0 ? &depthStencil : NULL);
	return DX12_OK;
}

int32_t dx12ClearRenderTarget(uint64_t list, uint64_t handle, double r, double g, double b, double a) {
	const FLOAT color[4] = { (FLOAT)r, (FLOAT)g, (FLOAT)b, (FLOAT)a };
	ID3D12GraphicsCommandList_ClearRenderTargetView(LIST(list), cpuHandle(handle), color, 0, NULL);
	return DX12_OK;
}

int32_t dx12ClearDepthStencil(uint64_t list, uint64_t handle, int32_t flags, double depth, uint32_t stencil) {
	ID3D12GraphicsCommandList_ClearDepthStencilView(LIST(list), cpuHandle(handle), (D3D12_CLEAR_FLAGS)flags, (FLOAT)depth, (UINT8)stencil, 0, NULL);
	return DX12_OK;
}

int32_t dx12SetViewport(uint64_t list, double x, double y, double width, double height, double minDepth, double maxDepth) {
	D3D12_VIEWPORT viewport = { (FLOAT)x, (FLOAT)y, (FLOAT)width, (FLOAT)height, (FLOAT)minDepth, (FLOAT)maxDepth };
	ID3D12GraphicsCommandList_RSSetViewports(LIST(list), 1, &viewport);
	return DX12_OK;
}

int32_t dx12SetScissorRect(uint64_t list, int32_t left, int32_t top, int32_t right, int32_t bottom) {
	D3D12_RECT rect = { left, top, right, bottom };
	ID3D12GraphicsCommandList_RSSetScissorRects(LIST(list), 1, &rect);
	return DX12_OK;
}

int32_t dx12SetBlendFactor(uint64_t list, double r, double g, double b, double a) {
	const FLOAT factor[4] = { (FLOAT)r, (FLOAT)g, (FLOAT)b, (FLOAT)a };
	ID3D12GraphicsCommandList_OMSetBlendFactor(LIST(list), factor);
	return DX12_OK;
}

int32_t dx12SetStencilReference(uint64_t list, uint32_t reference) {
	ID3D12GraphicsCommandList_OMSetStencilRef(LIST(list), reference);
	return DX12_OK;
}

int32_t dx12SetPipelineState(uint64_t list, uint64_t pipeline, int32_t topology) {
	ID3D12GraphicsCommandList_SetPipelineState(LIST(list), (ID3D12PipelineState *)(uintptr_t)pipeline);
	if (topology != D3D_PRIMITIVE_TOPOLOGY_UNDEFINED) ID3D12GraphicsCommandList_IASetPrimitiveTopology(LIST(list), (D3D12_PRIMITIVE_TOPOLOGY)topology);
	return DX12_OK;
}

int32_t dx12SetVertexBuffer(uint64_t list, uint32_t slot, uint64_t address, uint32_t bytes, uint32_t stride) {
	D3D12_VERTEX_BUFFER_VIEW view = { address, bytes, stride };
	ID3D12GraphicsCommandList_IASetVertexBuffers(LIST(list), slot, 1, &view);
	return DX12_OK;
}

int32_t dx12SetIndexBuffer(uint64_t list, uint64_t address, uint32_t bytes, int32_t format) {
	D3D12_INDEX_BUFFER_VIEW view = { address, bytes, (DXGI_FORMAT)format };
	ID3D12GraphicsCommandList_IASetIndexBuffer(LIST(list), &view);
	return DX12_OK;
}

int32_t dx12Draw(uint64_t list, uint32_t vertexCount, uint32_t instanceCount, uint32_t firstVertex, uint32_t firstInstance) {
	ID3D12GraphicsCommandList_DrawInstanced(LIST(list), vertexCount, instanceCount, firstVertex, firstInstance);
	return DX12_OK;
}

int32_t dx12DrawIndexed(uint64_t list, uint32_t indexCount, uint32_t instanceCount, uint32_t firstIndex, int32_t baseVertex, uint32_t firstInstance) {
	ID3D12GraphicsCommandList_DrawIndexedInstanced(LIST(list), indexCount, instanceCount, firstIndex, baseVertex, firstInstance);
	return DX12_OK;
}

int32_t dx12Dispatch(uint64_t list, uint32_t x, uint32_t y, uint32_t z) {
	ID3D12GraphicsCommandList_Dispatch(LIST(list), x, y, z);
	return DX12_OK;
}

int32_t dx12CommandSignatureCreate(uint64_t device, int32_t argumentType, uint32_t stride, uint64_t *signature) {
	*signature = 0;
	D3D12_INDIRECT_ARGUMENT_DESC argument = {0};
	argument.Type = (D3D12_INDIRECT_ARGUMENT_TYPE)argumentType;
	D3D12_COMMAND_SIGNATURE_DESC desc = {0};
	desc.ByteStride = stride;
	desc.NumArgumentDescs = 1;
	desc.pArgumentDescs = &argument;
	ID3D12CommandSignature *created = NULL;
	HRESULT hr = ID3D12Device_CreateCommandSignature(DEVICE(device), &desc, NULL, &IID_ID3D12CommandSignature, (void **)&created);
	if (FAILED(hr)) return failCall("ID3D12Device::CreateCommandSignature", hr);
	*signature = NATIVE(created);
	return DX12_OK;
}

int32_t dx12ExecuteIndirect(uint64_t list, uint64_t signature, uint32_t count, uint64_t buffer, uint64_t offset) {
	ID3D12GraphicsCommandList_ExecuteIndirect(LIST(list), (ID3D12CommandSignature *)(uintptr_t)signature, count, RESOURCE(buffer), offset, NULL, 0);
	return DX12_OK;
}

#define QUERY_HEAP(h) ((ID3D12QueryHeap *)(uintptr_t)(h))

int32_t dx12QueryHeapCreate(uint64_t device, int32_t type, uint32_t count, uint64_t *heap) {
	*heap = 0;
	D3D12_QUERY_HEAP_DESC desc = {0};
	desc.Type = (D3D12_QUERY_HEAP_TYPE)type;
	desc.Count = count;
	ID3D12QueryHeap *created = NULL;
	HRESULT hr = ID3D12Device_CreateQueryHeap(DEVICE(device), &desc, &IID_ID3D12QueryHeap, (void **)&created);
	if (FAILED(hr)) return failCall("ID3D12Device::CreateQueryHeap", hr);
	*heap = NATIVE(created);
	return DX12_OK;
}

int32_t dx12QueryBegin(uint64_t list, uint64_t heap, int32_t type, uint32_t index) {
	ID3D12GraphicsCommandList_BeginQuery(LIST(list), QUERY_HEAP(heap), (D3D12_QUERY_TYPE)type, index);
	return DX12_OK;
}

int32_t dx12QueryEnd(uint64_t list, uint64_t heap, int32_t type, uint32_t index) {
	ID3D12GraphicsCommandList_EndQuery(LIST(list), QUERY_HEAP(heap), (D3D12_QUERY_TYPE)type, index);
	return DX12_OK;
}

int32_t dx12QueryResolve(uint64_t list, uint64_t heap, int32_t type, uint32_t first, uint32_t count, uint64_t buffer, uint64_t offset) {
	ID3D12GraphicsCommandList_ResolveQueryData(LIST(list), QUERY_HEAP(heap), (D3D12_QUERY_TYPE)type, first, count, RESOURCE(buffer), offset);
	return DX12_OK;
}

int32_t dx12TimestampFrequency(uint64_t queue, uint64_t *frequency) {
	*frequency = 0;
	UINT64 ticks = 0;
	HRESULT hr = ID3D12CommandQueue_GetTimestampFrequency(QUEUE(queue), &ticks);
	if (FAILED(hr)) return failCall("ID3D12CommandQueue::GetTimestampFrequency", hr);
	*frequency = ticks;
	return DX12_OK;
}

int32_t dx12ResolveSubresource(uint64_t list, uint64_t target, uint32_t targetSubresource, uint64_t source, uint32_t sourceSubresource, int32_t format) {
	ID3D12GraphicsCommandList_ResolveSubresource(LIST(list), RESOURCE(target), targetSubresource, RESOURCE(source), sourceSubresource, (DXGI_FORMAT)format);
	return DX12_OK;
}

#define DX12_LABEL_UNITS 256

int32_t dx12Event(uint64_t list, int32_t kind, const char *label) {
	if (kind == DX12_EVENT_END) {
		ID3D12GraphicsCommandList_EndEvent(LIST(list));
		return DX12_OK;
	}
	wchar_t wide[DX12_LABEL_UNITS];
	int units = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, label, -1, wide, DX12_LABEL_UNITS);
	if (units == 0) return fail(DX12_ERROR_CALL, "debug label '%s' is not UTF-8 or is over %d characters in UTF-16", label, DX12_LABEL_UNITS - 1);
	UINT bytes = (UINT)(units * sizeof(wchar_t));
	if (kind == DX12_EVENT_BEGIN) ID3D12GraphicsCommandList_BeginEvent(LIST(list), 0, wide, bytes);
	else if (kind == DX12_EVENT_MARKER) ID3D12GraphicsCommandList_SetMarker(LIST(list), 0, wide, bytes);
	else return fail(DX12_ERROR_CALL, "debug event kind %d is not begin, end or marker", kind);
	return DX12_OK;
}

int32_t dx12SetName(uint64_t object, const char *name) {
	int units = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, name, -1, NULL, 0);
	if (units == 0) return fail(DX12_ERROR_CALL, "label '%s' is not UTF-8", name);
	wchar_t *wide = (wchar_t *)malloc((size_t)units * sizeof(wchar_t));
	if (wide == NULL) return fail(DX12_OUT_OF_MEMORY, "out of memory widening label '%s'", name);
	MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, name, -1, wide, units);
	HRESULT hr = ID3D12Object_SetName((ID3D12Object *)(uintptr_t)object, wide);
	free(wide);
	return FAILED(hr) ? failCall("ID3D12Object::SetName", hr) : DX12_OK;
}

// mingw's d3dcommon.h lacks WKPDID_D3DDebugObjectNameW; the value is the Windows SDK's (um/d3dcommon.h).
static const GUID debugObjectNameW = { 0x4cca5fd8, 0x921f, 0x42c8, { 0x85, 0x66, 0x70, 0xca, 0xf2, 0xa9, 0xb7, 0x41 } };

int32_t dx12ObjectName(uint64_t object, uint8_t *out, int32_t size) {
	wchar_t wide[DX12_LABEL_UNITS];
	UINT bytes = sizeof wide;
	HRESULT hr = ID3D12Object_GetPrivateData((ID3D12Object *)(uintptr_t)object, &debugObjectNameW, &bytes, wide);
	if (FAILED(hr)) return failCall("ID3D12Object::GetPrivateData(WKPDID_D3DDebugObjectNameW)", hr);
	int units = (int)(bytes / sizeof(wchar_t));
	if (units > 0 && wide[units - 1] == 0) units--;
	return WideCharToMultiByte(CP_UTF8, 0, wide, units, (char *)out, size, NULL, NULL);
}

static HMODULE s_compilerDll;
static pD3DCompile s_compile;
static char s_compileLog[4096];

int32_t dx12ShaderCompile(const char *source, const char *entryPoint, const char *target, uint64_t *blob, uint64_t *bytes, uint64_t *size) {
	*blob = 0;
	*bytes = 0;
	*size = 0;
	s_compileLog[0] = 0;
	if (!s_compile) {
		if (!s_compilerDll) s_compilerDll = LoadLibraryA("d3dcompiler_47.dll");
		if (!s_compilerDll) {
			strcpy(s_compileLog, "d3dcompiler_47.dll did not load");
			return DX12_ERROR_CALL;
		}
		s_compile = (pD3DCompile)(void *)GetProcAddress(s_compilerDll, "D3DCompile");
		if (!s_compile) {
			strcpy(s_compileLog, "d3dcompiler_47.dll has no D3DCompile");
			return DX12_ERROR_CALL;
		}
	}
	ID3DBlob *output = NULL;
	ID3DBlob *messages = NULL;
	HRESULT hr = s_compile(source, strlen(source), NULL, NULL, D3D_COMPILE_STANDARD_FILE_INCLUDE, entryPoint, target,
		D3DCOMPILE_PACK_MATRIX_COLUMN_MAJOR | D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, &output, &messages);
	if (messages) {
		strncpy(s_compileLog, (const char *)ID3D10Blob_GetBufferPointer(messages), sizeof s_compileLog - 1);
		s_compileLog[sizeof s_compileLog - 1] = 0;
		ID3D10Blob_Release(messages);
	}
	if (FAILED(hr)) {
		if (output) ID3D10Blob_Release(output);
		return DX12_ERROR_CALL;
	}
	*blob = NATIVE(output);
	*bytes = NATIVE(ID3D10Blob_GetBufferPointer(output));
	*size = (uint64_t)ID3D10Blob_GetBufferSize(output);
	return DX12_OK;
}

const char *dx12CompileLog(void) { return s_compileLog; }

#define SWAPCHAIN(s) ((IDXGISwapChain3 *)(uintptr_t)(s))

static int32_t adapterFactory(uint64_t adapter, IDXGIFactory2 **factory) {
	HRESULT hr = IDXGIAdapter1_GetParent((IDXGIAdapter1 *)(uintptr_t)adapter, &IID_IDXGIFactory2, (void **)factory);
	return FAILED(hr) ? failCall("IDXGIAdapter1::GetParent(IDXGIFactory2)", hr) : DX12_OK;
}

int32_t dx12TearingSupported(uint64_t adapter, int32_t *supported) {
	*supported = 0;
	IDXGIFactory2 *factory = NULL;
	int32_t status = adapterFactory(adapter, &factory);
	if (status != DX12_OK) return status;
	IDXGIFactory5 *factory5 = NULL;
	if (SUCCEEDED(IDXGIFactory2_QueryInterface(factory, &IID_IDXGIFactory5, (void **)&factory5))) {
		BOOL allowed = FALSE;
		HRESULT hr = IDXGIFactory5_CheckFeatureSupport(factory5, DXGI_FEATURE_PRESENT_ALLOW_TEARING, &allowed, sizeof allowed);
		*supported = SUCCEEDED(hr) && allowed;
		IDXGIFactory5_Release(factory5);
	}
	IDXGIFactory2_Release(factory);
	return DX12_OK;
}

static int32_t watchLatency(IDXGISwapChain3 *chain, uint32_t latency, uint64_t *waitable) {
	HRESULT hr = IDXGISwapChain3_SetMaximumFrameLatency(chain, latency);
	if (FAILED(hr)) return failCall("IDXGISwapChain2::SetMaximumFrameLatency", hr);
	HANDLE handle = IDXGISwapChain3_GetFrameLatencyWaitableObject(chain);
	if (handle == NULL) return fail(DX12_ERROR_CALL, "IDXGISwapChain2::GetFrameLatencyWaitableObject gave no handle");
	*waitable = NATIVE(handle);
	return DX12_OK;
}

int32_t dx12SwapchainCreate(uint64_t adapter, uint64_t queue, uint64_t window, int32_t composition, uint32_t width, uint32_t height, int32_t format,
	uint32_t bufferCount, uint32_t flags, uint32_t latency, uint64_t *swapchain, uint64_t *waitable) {
	*swapchain = 0;
	*waitable = 0;
	IDXGIFactory2 *factory = NULL;
	int32_t status = adapterFactory(adapter, &factory);
	if (status != DX12_OK) return status;
	DXGI_SWAP_CHAIN_DESC1 desc = {0};
	desc.Width = width;
	desc.Height = height;
	desc.Format = (DXGI_FORMAT)format;
	desc.SampleDesc.Count = 1;
	desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
	desc.BufferCount = bufferCount;
	desc.Scaling = DXGI_SCALING_STRETCH;
	desc.SwapEffect = composition ? DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL : DXGI_SWAP_EFFECT_FLIP_DISCARD;
	desc.AlphaMode = composition ? DXGI_ALPHA_MODE_PREMULTIPLIED : DXGI_ALPHA_MODE_UNSPECIFIED;
	desc.Flags = flags;
	IDXGISwapChain1 *created = NULL;
	HRESULT hr = composition
		? IDXGIFactory2_CreateSwapChainForComposition(factory, (IUnknown *)QUEUE(queue), &desc, NULL, &created)
		: IDXGIFactory2_CreateSwapChainForHwnd(factory, (IUnknown *)QUEUE(queue), (HWND)(uintptr_t)window, &desc, NULL, NULL, &created);
	if (FAILED(hr)) {
		IDXGIFactory2_Release(factory);
		return failCall(composition ? "IDXGIFactory2::CreateSwapChainForComposition" : "IDXGIFactory2::CreateSwapChainForHwnd", hr);
	}
	if (!composition) IDXGIFactory2_MakeWindowAssociation(factory, (HWND)(uintptr_t)window, DXGI_MWA_NO_ALT_ENTER | DXGI_MWA_NO_PRINT_SCREEN);
	IDXGIFactory2_Release(factory);
	IDXGISwapChain3 *chain = NULL;
	hr = IDXGISwapChain1_QueryInterface(created, &IID_IDXGISwapChain3, (void **)&chain);
	IDXGISwapChain1_Release(created);
	if (FAILED(hr)) return failCall("IDXGISwapChain1::QueryInterface(IDXGISwapChain3)", hr);
	status = watchLatency(chain, latency, waitable);
	if (status != DX12_OK) {
		IDXGISwapChain3_Release(chain);
		return status;
	}
	*swapchain = NATIVE(chain);
	return DX12_OK;
}

int32_t dx12SwapchainBuffer(uint64_t swapchain, uint32_t index, uint64_t *resource) {
	ID3D12Resource *buffer = NULL;
	HRESULT hr = IDXGISwapChain3_GetBuffer(SWAPCHAIN(swapchain), index, &IID_ID3D12Resource, (void **)&buffer);
	*resource = NATIVE(buffer);
	return FAILED(hr) ? failCall("IDXGISwapChain3::GetBuffer", hr) : DX12_OK;
}

int32_t dx12SwapchainCurrent(uint64_t swapchain, uint32_t *index) {
	*index = IDXGISwapChain3_GetCurrentBackBufferIndex(SWAPCHAIN(swapchain));
	return DX12_OK;
}

int32_t dx12SwapchainResize(uint64_t swapchain, uint32_t bufferCount, uint32_t width, uint32_t height, uint32_t flags) {
	HRESULT hr = IDXGISwapChain3_ResizeBuffers(SWAPCHAIN(swapchain), bufferCount, width, height, DXGI_FORMAT_UNKNOWN, flags);
	return FAILED(hr) ? failCall("IDXGISwapChain3::ResizeBuffers", hr) : DX12_OK;
}

int32_t dx12SwapchainPresent(uint64_t swapchain, uint32_t interval, uint32_t flags, int32_t *result) {
	HRESULT hr = IDXGISwapChain3_Present(SWAPCHAIN(swapchain), interval, flags);
	*result = (int32_t)hr;
	if (SUCCEEDED(hr) || (hr == DXGI_ERROR_WAS_STILL_DRAWING && (flags & DXGI_PRESENT_DO_NOT_WAIT))) return DX12_OK;
	return failCall("IDXGISwapChain3::Present", hr);
}

int32_t dx12SwapchainRelease(uint64_t swapchain, uint64_t waitable) {
	if (waitable != 0 && !CloseHandle(HANDLE_OF(waitable))) {
		return fail(DX12_ERROR_CALL, "CloseHandle on the frame latency waitable failed with error %lu", GetLastError());
	}
	if (swapchain != 0) IDXGISwapChain3_Release(SWAPCHAIN(swapchain));
	return DX12_OK;
}

int32_t dx12RemovedReason(uint64_t device, int32_t *reason) {
	*reason = (int32_t)ID3D12Device_GetDeviceRemovedReason(DEVICE(device));
	return DX12_OK;
}

int32_t dx12PointerBits(void *pointer, uint64_t *bits) {
	*bits = NATIVE(pointer);
	return DX12_OK;
}

int32_t dx12Release(uint64_t object) {
	if (object != 0) IUnknown_Release((IUnknown *)(uintptr_t)object);
	return DX12_OK;
}
