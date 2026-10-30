#pragma once
#include <stdint.h>

#define DX12_OK 0
#define DX12_ERROR_CALL -1
#define DX12_ERROR_ADAPTER -2
#define DX12_ERROR_DEBUG_LAYER -3
#define DX12_OUT_OF_MEMORY -4
#define DX12_DEVICE_REMOVED -5

const char *dx12Error(void);

int32_t dx12DeviceCreate(int32_t warp, int32_t debug, uint64_t *device, uint64_t *adapter);
int32_t dx12InfoDrain(uint64_t device, uint64_t *count);
int32_t dx12AdapterDescribe(uint64_t adapter, uint32_t *vendorId, uint32_t *deviceId);
const char *dx12AdapterDescription(void);

int32_t dx12QueueCreate(uint64_t device, uint64_t *queue);
int32_t dx12QueueSignal(uint64_t queue, uint64_t fence, uint64_t value);
int32_t dx12QueueExecute(uint64_t queue, uint64_t list);

int32_t dx12FenceCreate(uint64_t device, uint64_t *fence, uint64_t *event);
int32_t dx12FenceCompleted(uint64_t fence, uint64_t *value);
int32_t dx12FenceWait(uint64_t fence, uint64_t event, uint64_t value);
int32_t dx12EventClose(uint64_t event);

int32_t dx12AllocatorCreate(uint64_t device, uint64_t *allocator);
int32_t dx12AllocatorReset(uint64_t allocator);
int32_t dx12ListCreate(uint64_t device, uint64_t allocator, uint64_t *list);
int32_t dx12ListReset(uint64_t list, uint64_t allocator);
int32_t dx12ListClose(uint64_t list);

int32_t dx12BufferCreate(uint64_t device, uint64_t size, int32_t heap, uint32_t state, int32_t unordered, uint64_t *resource);
int32_t dx12ResourceAddress(uint64_t resource, uint64_t *address);
int32_t dx12ResourceMap(uint64_t resource, uint64_t readBegin, uint64_t readEnd, uint64_t *pointer);
int32_t dx12ResourceUnmap(uint64_t resource, uint64_t writtenBegin, uint64_t writtenEnd);
int32_t dx12MemoryWrite(uint64_t pointer, void *data, uint64_t bytes);
int32_t dx12MemoryRead(uint64_t pointer, void *out, uint64_t bytes);

int32_t dx12CopyBufferRegion(uint64_t list, uint64_t target, uint64_t targetOffset, uint64_t source, uint64_t sourceOffset, uint64_t bytes);
int32_t dx12BarrierTransition(uint64_t resource, uint32_t before, uint32_t after);
int32_t dx12BarrierFlush(uint64_t list, int32_t uav);

int32_t dx12Release(uint64_t object);
