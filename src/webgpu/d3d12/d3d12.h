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

int32_t dx12Release(uint64_t object);
