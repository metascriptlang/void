#pragma once
#include <stdint.h>

#define VULKAN_OK 0
#define VULKAN_ERROR_LIBRARY 1
#define VULKAN_ERROR_FUNCTION 2
#define VULKAN_ERROR_CALL 3
#define VULKAN_ERROR_EXTENSION 4
#define VULKAN_ERROR_ADAPTER 5
#define VULKAN_ERROR_ORDER 6

#define VULKAN_POWER_DEFAULT 0
#define VULKAN_POWER_LOW 1
#define VULKAN_POWER_HIGH 2

#define VULKAN_FEATURE_BC 0x2
#define VULKAN_FEATURE_ETC2 0x4
#define VULKAN_FEATURE_ASTC 0x8

#define VULKAN_LIMIT_TEXTURE_DIMENSION_1D 0
#define VULKAN_LIMIT_TEXTURE_DIMENSION_2D 1
#define VULKAN_LIMIT_TEXTURE_DIMENSION_3D 2
#define VULKAN_LIMIT_TEXTURE_ARRAY_LAYERS 3
#define VULKAN_LIMIT_BIND_GROUPS 4
#define VULKAN_LIMIT_SAMPLED_TEXTURES_PER_STAGE 5
#define VULKAN_LIMIT_SAMPLERS_PER_STAGE 6
#define VULKAN_LIMIT_STORAGE_BUFFERS_PER_STAGE 7
#define VULKAN_LIMIT_STORAGE_TEXTURES_PER_STAGE 8
#define VULKAN_LIMIT_UNIFORM_BUFFERS_PER_STAGE 9
#define VULKAN_LIMIT_UNIFORM_BUFFER_BINDING_SIZE 10
#define VULKAN_LIMIT_STORAGE_BUFFER_BINDING_SIZE 11
#define VULKAN_LIMIT_VERTEX_BUFFERS 12
#define VULKAN_LIMIT_VERTEX_ATTRIBUTES 13
#define VULKAN_LIMIT_COLOR_ATTACHMENTS 14
#define VULKAN_LIMIT_WORKGROUP_SIZE_X 15
#define VULKAN_LIMIT_WORKGROUP_SIZE_Y 16
#define VULKAN_LIMIT_WORKGROUP_SIZE_Z 17
#define VULKAN_LIMIT_WORKGROUP_INVOCATIONS 18
#define VULKAN_LIMIT_WORKGROUPS_PER_DIMENSION 19
#define VULKAN_LIMIT_UNIFORM_OFFSET_ALIGNMENT 20
#define VULKAN_LIMIT_STORAGE_OFFSET_ALIGNMENT 21

int32_t vulkanLoaderOpen(void);
const char *vulkanError(void);

int32_t vulkanInstanceCreate(void);
int32_t vulkanValidationEnabled(void);
int32_t vulkanValidationErrors(void);
int32_t vulkanValidationWarnings(void);

int32_t vulkanSurfaceCreateWin32(void *hinstance, void *hwnd);
int32_t vulkanSurfaceCreateXlib(void *display, uint64_t window);
int32_t vulkanSurfaceCreateAndroid(void *window);

int32_t vulkanAdapterSelect(int32_t powerPreference);
uint32_t vulkanAdapterVendorId(void);
uint32_t vulkanAdapterDeviceId(void);
const char *vulkanAdapterName(void);
uint32_t vulkanAdapterDriverVersion(void);
uint32_t vulkanAdapterApiVersion(void);
int32_t vulkanAdapterQueueFamily(void);
int64_t vulkanAdapterLimit(int32_t limit);

int32_t vulkanDeviceCreate(void);
uint32_t vulkanDeviceFeatures(void);

void vulkanShutdown(void);
