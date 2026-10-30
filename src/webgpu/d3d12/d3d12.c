#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d12.h>
#include <d3d12sdklayers.h>
#include <dxgi1_6.h>
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

int32_t dx12Release(uint64_t object) {
	if (object != 0) IUnknown_Release((IUnknown *)(uintptr_t)object);
	return DX12_OK;
}
