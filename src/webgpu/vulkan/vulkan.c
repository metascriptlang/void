#if defined(_WIN32)
#ifndef VK_USE_PLATFORM_WIN32_KHR
#define VK_USE_PLATFORM_WIN32_KHR
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#elif defined(__ANDROID__)
#ifndef VK_USE_PLATFORM_ANDROID_KHR
#define VK_USE_PLATFORM_ANDROID_KHR
#endif
#include <dlfcn.h>
#elif defined(__linux__)
#ifndef VK_USE_PLATFORM_XLIB_KHR
#define VK_USE_PLATFORM_XLIB_KHR
#endif
#include <dlfcn.h>
#else
#error "the Vulkan backend covers Windows, Linux X11 and Android; another platform needs its library name and surface extension here"
#endif

#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "vulkan.h"

#if VK_USE_64_BIT_PTR_DEFINES == 1
#define HANDLE_OUT(handle) ((uint64_t)(uintptr_t)(handle))
#define HANDLE_IN(type, value) ((type)(uintptr_t)(value))
#else
#define HANDLE_OUT(handle) ((uint64_t)(handle))
#define HANDLE_IN(type, value) ((type)(value))
#endif

#define VULKAN_GLOBAL_FUNCS(X) \
	X(vkCreateInstance) \
	X(vkEnumerateInstanceExtensionProperties) \
	X(vkEnumerateInstanceLayerProperties) \
	X(vkEnumerateInstanceVersion)

#define VULKAN_INSTANCE_FUNCS(X) \
	X(vkDestroyInstance) \
	X(vkEnumeratePhysicalDevices) \
	X(vkGetPhysicalDeviceProperties) \
	X(vkGetPhysicalDeviceFeatures) \
	X(vkGetPhysicalDeviceQueueFamilyProperties) \
	X(vkGetPhysicalDeviceMemoryProperties) \
	X(vkGetPhysicalDeviceFormatProperties) \
	X(vkEnumerateDeviceExtensionProperties) \
	X(vkCreateDevice) \
	X(vkGetDeviceProcAddr) \
	X(vkDestroySurfaceKHR) \
	X(vkGetPhysicalDeviceSurfaceSupportKHR) \
	X(vkGetPhysicalDeviceSurfaceCapabilitiesKHR) \
	X(vkGetPhysicalDeviceSurfaceFormatsKHR) \
	X(vkGetPhysicalDeviceSurfacePresentModesKHR)

#if defined(VK_USE_PLATFORM_WIN32_KHR)
#define VULKAN_SURFACE_EXTENSION VK_KHR_WIN32_SURFACE_EXTENSION_NAME
#define VULKAN_SURFACE_FUNCS(X) X(vkCreateWin32SurfaceKHR)
#elif defined(VK_USE_PLATFORM_ANDROID_KHR)
#define VULKAN_SURFACE_EXTENSION VK_KHR_ANDROID_SURFACE_EXTENSION_NAME
#define VULKAN_SURFACE_FUNCS(X) X(vkCreateAndroidSurfaceKHR)
#else
#define VULKAN_SURFACE_EXTENSION VK_KHR_XLIB_SURFACE_EXTENSION_NAME
#define VULKAN_SURFACE_FUNCS(X) X(vkCreateXlibSurfaceKHR)
#endif

#define VULKAN_DEBUG_FUNCS(X) \
	X(vkCreateDebugUtilsMessengerEXT) \
	X(vkDestroyDebugUtilsMessengerEXT) \
	X(vkSetDebugUtilsObjectNameEXT) \
	X(vkCmdBeginDebugUtilsLabelEXT) \
	X(vkCmdEndDebugUtilsLabelEXT) \
	X(vkCmdInsertDebugUtilsLabelEXT)

#define VULKAN_DEVICE_FUNCS(X) \
	X(vkDestroyDevice) \
	X(vkDeviceWaitIdle) \
	X(vkGetDeviceQueue) \
	X(vkQueueSubmit) \
	X(vkQueueWaitIdle) \
	X(vkAllocateMemory) \
	X(vkFreeMemory) \
	X(vkMapMemory) \
	X(vkUnmapMemory) \
	X(vkFlushMappedMemoryRanges) \
	X(vkInvalidateMappedMemoryRanges) \
	X(vkCreateBuffer) \
	X(vkDestroyBuffer) \
	X(vkGetBufferMemoryRequirements) \
	X(vkGetBufferMemoryRequirements2) \
	X(vkBindBufferMemory) \
	X(vkCreateImage) \
	X(vkDestroyImage) \
	X(vkGetImageMemoryRequirements) \
	X(vkGetImageMemoryRequirements2) \
	X(vkBindImageMemory) \
	X(vkCreateImageView) \
	X(vkDestroyImageView) \
	X(vkCreateSampler) \
	X(vkDestroySampler) \
	X(vkCreateDescriptorSetLayout) \
	X(vkDestroyDescriptorSetLayout) \
	X(vkCreateDescriptorPool) \
	X(vkDestroyDescriptorPool) \
	X(vkResetDescriptorPool) \
	X(vkAllocateDescriptorSets) \
	X(vkUpdateDescriptorSets) \
	X(vkCreatePipelineLayout) \
	X(vkDestroyPipelineLayout) \
	X(vkCreateShaderModule) \
	X(vkDestroyShaderModule) \
	X(vkCreateGraphicsPipelines) \
	X(vkCreateComputePipelines) \
	X(vkDestroyPipeline) \
	X(vkCreateRenderPass) \
	X(vkDestroyRenderPass) \
	X(vkCreateFramebuffer) \
	X(vkDestroyFramebuffer) \
	X(vkCreateCommandPool) \
	X(vkDestroyCommandPool) \
	X(vkResetCommandPool) \
	X(vkAllocateCommandBuffers) \
	X(vkFreeCommandBuffers) \
	X(vkBeginCommandBuffer) \
	X(vkEndCommandBuffer) \
	X(vkCmdBeginRenderPass) \
	X(vkCmdEndRenderPass) \
	X(vkCmdBindPipeline) \
	X(vkCmdBindDescriptorSets) \
	X(vkCmdBindVertexBuffers) \
	X(vkCmdBindIndexBuffer) \
	X(vkCmdPushConstants) \
	X(vkCmdSetViewport) \
	X(vkCmdSetScissor) \
	X(vkCmdSetBlendConstants) \
	X(vkCmdSetStencilReference) \
	X(vkCmdDraw) \
	X(vkCmdDrawIndexed) \
	X(vkCmdDrawIndirect) \
	X(vkCmdDrawIndexedIndirect) \
	X(vkCmdDispatch) \
	X(vkCmdDispatchIndirect) \
	X(vkCmdCopyBuffer) \
	X(vkCmdCopyBufferToImage) \
	X(vkCmdCopyImageToBuffer) \
	X(vkCmdCopyImage) \
	X(vkCmdPipelineBarrier) \
	X(vkCreateQueryPool) \
	X(vkDestroyQueryPool) \
	X(vkCmdResetQueryPool) \
	X(vkCmdBeginQuery) \
	X(vkCmdEndQuery) \
	X(vkCmdWriteTimestamp) \
	X(vkCmdCopyQueryPoolResults) \
	X(vkCreateFence) \
	X(vkDestroyFence) \
	X(vkWaitForFences) \
	X(vkResetFences) \
	X(vkGetFenceStatus) \
	X(vkCreateSemaphore) \
	X(vkDestroySemaphore) \
	X(vkCreateSwapchainKHR) \
	X(vkDestroySwapchainKHR) \
	X(vkGetSwapchainImagesKHR) \
	X(vkAcquireNextImageKHR) \
	X(vkQueuePresentKHR)

#define VULKAN_MEMBER(name) PFN_##name name;
static struct {
	PFN_vkGetInstanceProcAddr vkGetInstanceProcAddr;
	VULKAN_GLOBAL_FUNCS(VULKAN_MEMBER)
} vkb;
static struct {
	VULKAN_INSTANCE_FUNCS(VULKAN_MEMBER)
	VULKAN_SURFACE_FUNCS(VULKAN_MEMBER)
	VULKAN_DEBUG_FUNCS(VULKAN_MEMBER)
} vki;
static struct {
	VULKAN_DEVICE_FUNCS(VULKAN_MEMBER)
} vkd;
#undef VULKAN_MEMBER

#define VULKAN_LOAD_GLOBAL(name) \
	vkb.name = (PFN_##name)required(vkb.vkGetInstanceProcAddr(NULL, #name), #name);
#define VULKAN_LOAD_INSTANCE(name) \
	vki.name = (PFN_##name)required(vkb.vkGetInstanceProcAddr(s_vk.instance, #name), #name);
#define VULKAN_LOAD_DEVICE(name) \
	vkd.name = (PFN_##name)required(vki.vkGetDeviceProcAddr(s_vk.device, #name), #name);

#define VALIDATION_LAYER "VK_LAYER_KHRONOS_validation"

static struct {
	void *library;
	VkInstance instance;
	VkDebugUtilsMessengerEXT messenger;
	VkSurfaceKHR surface;
	VkPhysicalDevice physicalDevice;
	VkPhysicalDeviceProperties properties;
	VkPhysicalDeviceFeatures supported;
	VkPhysicalDeviceMemoryProperties memory;
	uint32_t queueFamily;
	VkDevice device;
	VkQueue queue;
	VkCommandPool commandPool;
	uint32_t features;
	int32_t validation;
} s_vk;

#define MAX_COLOR_ATTACHMENTS 8
#define COLOR_KEY_WORDS 5
#define DEPTH_KEY_WORDS 8
#define MAX_KEY_WORDS (1 + MAX_COLOR_ATTACHMENTS * COLOR_KEY_WORDS + DEPTH_KEY_WORDS)
#define MAX_PASS_ATTACHMENTS (2 * MAX_COLOR_ATTACHMENTS + 1)
#define MAX_FRAMES 8

typedef struct {
	VkFence fence;
	VkCommandBuffer commands;
	VkCommandBuffer transfer;
	uint64_t serial;
	uint32_t owned;
	VkFramebuffer *framebuffers;
	uint32_t framebufferCount;
} VulkanSubmission;

typedef struct {
	VkCommandPool pool;
	VkCommandBuffer commands;
	VkFence fence;
	VkSemaphore acquired;
	uint64_t serial;
} VulkanFrame;

typedef struct {
	VkImage image;
	VkImageView view;
	VkSemaphore presentReady;
} VulkanSwapImage;

static struct {
	VkSurfaceCapabilitiesKHR capabilities;
	VkSurfaceFormatKHR *formats;
	uint32_t formatCount;
	VkPresentModeKHR *presentModes;
	uint32_t presentModeCount;
	uint32_t queried;
} s_surfaceInfo;

static struct {
	VkSwapchainKHR swapchain;
	VulkanSwapImage *images;
	uint32_t imageCount;
	int32_t acquired;
	uint32_t presentPending;
} s_swap = { .acquired = -1 };

static VulkanFrame s_frames[MAX_FRAMES];
static uint32_t s_frameCount;
static int32_t s_frameOpen = -1;
static uint32_t s_frameAcquired;
static uint32_t s_passOpen;
static VkFramebuffer *s_framebuffers;
static uint32_t s_framebufferCount;
static uint32_t s_framebufferCapacity;

static VkCommandBuffer s_recording;
static VkCommandBuffer s_transfer;
static uint32_t s_queueStream;
static VulkanSubmission *s_submissions;
static uint32_t s_submissionCount;
static uint32_t s_submissionCapacity;
static uint64_t s_submitted;
static uint64_t s_completed;
static VkImageMemoryBarrier *s_imageBarriers;
static uint32_t s_imageBarrierCount;
static uint32_t s_imageBarrierCapacity;

static int32_t s_validationErrors;
static int32_t s_validationWarnings;
static char s_error[512];
static char s_missing[96];

static int32_t fail(int32_t code, const char *format, ...) {
	va_list args;
	va_start(args, format);
	vsnprintf(s_error, sizeof s_error, format, args);
	va_end(args);
	return code;
}

static int32_t failCall(const char *call, VkResult result) {
	int32_t code = result == VK_ERROR_DEVICE_LOST ? VULKAN_DEVICE_LOST
		: result == VK_ERROR_OUT_OF_HOST_MEMORY || result == VK_ERROR_OUT_OF_DEVICE_MEMORY ? VULKAN_OUT_OF_MEMORY
		: VULKAN_ERROR_CALL;
	return fail(code, "%s returned VkResult %d", call, (int)result);
}

static PFN_vkVoidFunction required(PFN_vkVoidFunction address, const char *name) {
	if (address == NULL && s_missing[0] == 0) snprintf(s_missing, sizeof s_missing, "%s", name);
	return address;
}

static int32_t failMissing(const char *loader) {
	return fail(VULKAN_ERROR_FUNCTION, "%s returned NULL for %s", loader, s_missing);
}

const char *vulkanError(void) { return s_error; }

static void *libraryOpen(void) {
#if defined(_WIN32)
	return (void *)LoadLibraryA("vulkan-1.dll");
#elif defined(__ANDROID__)
	return dlopen("libvulkan.so", RTLD_NOW | RTLD_LOCAL);
#else
	void *library = dlopen("libvulkan.so.1", RTLD_NOW | RTLD_LOCAL);
	return library != NULL ? library : dlopen("libvulkan.so", RTLD_NOW | RTLD_LOCAL);
#endif
}

static PFN_vkGetInstanceProcAddr librarySymbol(void *library) {
#if defined(_WIN32)
	return (PFN_vkGetInstanceProcAddr)(void *)GetProcAddress((HMODULE)library, "vkGetInstanceProcAddr");
#else
	return (PFN_vkGetInstanceProcAddr)dlsym(library, "vkGetInstanceProcAddr");
#endif
}

static void libraryClose(void *library) {
#if defined(_WIN32)
	FreeLibrary((HMODULE)library);
#else
	dlclose(library);
#endif
}

int32_t vulkanLoaderOpen(void) {
	if (s_vk.library != NULL) return fail(VULKAN_ERROR_ORDER, "vulkanLoaderOpen called twice");
	s_vk.library = libraryOpen();
	if (s_vk.library == NULL) {
#if defined(_WIN32)
		return fail(VULKAN_ERROR_LIBRARY, "LoadLibraryA found no vulkan-1.dll");
#elif defined(__ANDROID__)
		return fail(VULKAN_ERROR_LIBRARY, "dlopen found no libvulkan.so");
#else
		return fail(VULKAN_ERROR_LIBRARY, "dlopen found neither libvulkan.so.1 nor libvulkan.so");
#endif
	}
	vkb.vkGetInstanceProcAddr = librarySymbol(s_vk.library);
	if (vkb.vkGetInstanceProcAddr == NULL) {
		return fail(VULKAN_ERROR_FUNCTION, "the Vulkan library exports no vkGetInstanceProcAddr");
	}
	s_missing[0] = 0;
	VULKAN_GLOBAL_FUNCS(VULKAN_LOAD_GLOBAL)
	if (s_missing[0] != 0) return failMissing("vkGetInstanceProcAddr");
	return VULKAN_OK;
}

static int32_t validationRequested(void) {
#if defined(VOID_VULKAN_DEBUG)
	return 1;
#else
	const char *value = getenv("VOID_VULKAN_VALIDATION");
	return value != NULL && strcmp(value, "1") == 0;
#endif
}

static VKAPI_ATTR VkBool32 VKAPI_CALL validationMessage(
	VkDebugUtilsMessageSeverityFlagBitsEXT severity,
	VkDebugUtilsMessageTypeFlagsEXT types,
	const VkDebugUtilsMessengerCallbackDataEXT *data,
	void *user) {
	(void)types;
	(void)user;
	int32_t error = (severity & VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT) != 0;
	if (error) s_validationErrors += 1;
	else s_validationWarnings += 1;
	fprintf(stderr, "vulkan %s: %s\n", error ? "error" : "warning", data->pMessage);
	return VK_FALSE;
}

static int32_t hasLayer(const char *name) {
	uint32_t count = 0;
	if (vkb.vkEnumerateInstanceLayerProperties(&count, NULL) != VK_SUCCESS || count == 0) return 0;
	VkLayerProperties *layers = malloc(sizeof *layers * count);
	if (layers == NULL) return 0;
	int32_t found = 0;
	if (vkb.vkEnumerateInstanceLayerProperties(&count, layers) == VK_SUCCESS) {
		for (uint32_t i = 0; i < count && !found; i++) found = strcmp(layers[i].layerName, name) == 0;
	}
	free(layers);
	return found;
}

static int32_t hasInstanceExtension(const char *layer, const char *name) {
	uint32_t count = 0;
	if (vkb.vkEnumerateInstanceExtensionProperties(layer, &count, NULL) != VK_SUCCESS || count == 0) return 0;
	VkExtensionProperties *extensions = malloc(sizeof *extensions * count);
	if (extensions == NULL) return 0;
	int32_t found = 0;
	if (vkb.vkEnumerateInstanceExtensionProperties(layer, &count, extensions) == VK_SUCCESS) {
		for (uint32_t i = 0; i < count && !found; i++) found = strcmp(extensions[i].extensionName, name) == 0;
	}
	free(extensions);
	return found;
}

static int32_t hasDeviceExtension(VkPhysicalDevice device, const char *name) {
	uint32_t count = 0;
	if (vki.vkEnumerateDeviceExtensionProperties(device, NULL, &count, NULL) != VK_SUCCESS || count == 0) return 0;
	VkExtensionProperties *extensions = malloc(sizeof *extensions * count);
	if (extensions == NULL) return 0;
	int32_t found = 0;
	if (vki.vkEnumerateDeviceExtensionProperties(device, NULL, &count, extensions) == VK_SUCCESS) {
		for (uint32_t i = 0; i < count && !found; i++) found = strcmp(extensions[i].extensionName, name) == 0;
	}
	free(extensions);
	return found;
}

int32_t vulkanInstanceCreate(void) {
	if (s_vk.library == NULL) return fail(VULKAN_ERROR_ORDER, "vulkanInstanceCreate before vulkanLoaderOpen");
	if (s_vk.instance != NULL) return fail(VULKAN_ERROR_ORDER, "vulkanInstanceCreate called twice");
	uint32_t version = 0;
	VkResult result = vkb.vkEnumerateInstanceVersion(&version);
	if (result != VK_SUCCESS) return failCall("vkEnumerateInstanceVersion", result);
	if (version < VK_API_VERSION_1_1) {
		return fail(
			VULKAN_ERROR_LIBRARY,
			"the Vulkan loader is %u.%u, Void needs 1.1",
			VK_API_VERSION_MAJOR(version),
			VK_API_VERSION_MINOR(version));
	}

	const char *extensions[3] = { VK_KHR_SURFACE_EXTENSION_NAME, VULKAN_SURFACE_EXTENSION, NULL };
	uint32_t extensionCount = 2;
	for (uint32_t i = 0; i < extensionCount; i++) {
		if (!hasInstanceExtension(NULL, extensions[i])) {
			return fail(VULKAN_ERROR_EXTENSION, "the Vulkan instance lacks %s", extensions[i]);
		}
	}

	const char *layers[1] = { VALIDATION_LAYER };
	uint32_t layerCount = 0;
	int32_t debugUtils = 0;
	if (validationRequested()) {
		if (!hasLayer(VALIDATION_LAYER)) {
			return fail(VULKAN_ERROR_EXTENSION, "validation was asked for, but %s is not installed", VALIDATION_LAYER);
		}
		layerCount = 1;
		debugUtils = hasInstanceExtension(NULL, VK_EXT_DEBUG_UTILS_EXTENSION_NAME) ||
			hasInstanceExtension(VALIDATION_LAYER, VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
		if (!debugUtils) {
			return fail(VULKAN_ERROR_EXTENSION, "validation was asked for, but %s reports through no %s", VALIDATION_LAYER, VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
		}
	}
	if (debugUtils) extensions[extensionCount++] = VK_EXT_DEBUG_UTILS_EXTENSION_NAME;

	VkDebugUtilsMessengerCreateInfoEXT messengerInfo = { .sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT };
	messengerInfo.messageSeverity =
		VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT;
	messengerInfo.messageType = VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
		VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
		VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT;
	messengerInfo.pfnUserCallback = validationMessage;

	VkApplicationInfo application = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO };
	application.pApplicationName = "void";
	application.pEngineName = "void";
	application.apiVersion = VK_API_VERSION_1_1;

	VkInstanceCreateInfo info = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO };
	info.pNext = debugUtils ? &messengerInfo : NULL;
	info.pApplicationInfo = &application;
	info.enabledLayerCount = layerCount;
	info.ppEnabledLayerNames = layers;
	info.enabledExtensionCount = extensionCount;
	info.ppEnabledExtensionNames = extensions;

	s_validationErrors = 0;
	s_validationWarnings = 0;
	result = vkb.vkCreateInstance(&info, NULL, &s_vk.instance);
	if (result != VK_SUCCESS) {
		s_vk.instance = NULL;
		return failCall("vkCreateInstance", result);
	}
	s_vk.validation = layerCount == 1;

	s_missing[0] = 0;
	VULKAN_INSTANCE_FUNCS(VULKAN_LOAD_INSTANCE)
	VULKAN_SURFACE_FUNCS(VULKAN_LOAD_INSTANCE)
	if (debugUtils) {
		VULKAN_DEBUG_FUNCS(VULKAN_LOAD_INSTANCE)
	}
	if (s_missing[0] != 0) return failMissing("vkGetInstanceProcAddr");

	if (debugUtils) {
		result = vki.vkCreateDebugUtilsMessengerEXT(s_vk.instance, &messengerInfo, NULL, &s_vk.messenger);
		if (result != VK_SUCCESS) return failCall("vkCreateDebugUtilsMessengerEXT", result);
	}
	return VULKAN_OK;
}

int32_t vulkanValidationEnabled(void) { return s_vk.validation; }
int32_t vulkanValidationErrors(void) { return s_validationErrors; }
int32_t vulkanValidationWarnings(void) { return s_validationWarnings; }

static int32_t surfaceReady(const char *caller) {
	if (s_vk.instance == NULL) return fail(VULKAN_ERROR_ORDER, "%s before vulkanInstanceCreate", caller);
	if (s_vk.surface != VK_NULL_HANDLE) return fail(VULKAN_ERROR_ORDER, "%s with a surface already made", caller);
	return VULKAN_OK;
}

static int32_t surfaceMade(const char *call, VkResult result) {
	if (result != VK_SUCCESS) {
		s_vk.surface = VK_NULL_HANDLE;
		return failCall(call, result);
	}
	if (s_vk.physicalDevice == NULL) return VULKAN_OK;
	VkBool32 present = VK_FALSE;
	result = vki.vkGetPhysicalDeviceSurfaceSupportKHR(s_vk.physicalDevice, s_vk.queueFamily, s_vk.surface, &present);
	if (result == VK_SUCCESS && present) return VULKAN_OK;
	vki.vkDestroySurfaceKHR(s_vk.instance, s_vk.surface, NULL);
	s_vk.surface = VK_NULL_HANDLE;
	if (result != VK_SUCCESS) return failCall("vkGetPhysicalDeviceSurfaceSupportKHR", result);
	return fail(VULKAN_ERROR_ADAPTER, "%s cannot present to the new surface from queue family %u",
		s_vk.properties.deviceName, s_vk.queueFamily);
}

#if defined(VK_USE_PLATFORM_WIN32_KHR)
int32_t vulkanSurfaceCreateWin32(void *hinstance, void *hwnd) {
	int32_t ready = surfaceReady("vulkanSurfaceCreateWin32");
	if (ready != VULKAN_OK) return ready;
	VkWin32SurfaceCreateInfoKHR info = { .sType = VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR };
	info.hinstance = (HINSTANCE)hinstance;
	info.hwnd = (HWND)hwnd;
	VkResult result = vki.vkCreateWin32SurfaceKHR(s_vk.instance, &info, NULL, &s_vk.surface);
	return surfaceMade("vkCreateWin32SurfaceKHR", result);
}
#endif

#if defined(VK_USE_PLATFORM_XLIB_KHR)
int32_t vulkanSurfaceCreateXlib(void *display, uint64_t window) {
	int32_t ready = surfaceReady("vulkanSurfaceCreateXlib");
	if (ready != VULKAN_OK) return ready;
	VkXlibSurfaceCreateInfoKHR info = { .sType = VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR };
	info.dpy = (Display *)display;
	info.window = (Window)window;
	VkResult result = vki.vkCreateXlibSurfaceKHR(s_vk.instance, &info, NULL, &s_vk.surface);
	return surfaceMade("vkCreateXlibSurfaceKHR", result);
}
#endif

#if defined(VK_USE_PLATFORM_ANDROID_KHR)
int32_t vulkanSurfaceCreateAndroid(void *window) {
	int32_t ready = surfaceReady("vulkanSurfaceCreateAndroid");
	if (ready != VULKAN_OK) return ready;
	VkAndroidSurfaceCreateInfoKHR info = { .sType = VK_STRUCTURE_TYPE_ANDROID_SURFACE_CREATE_INFO_KHR };
	info.window = (struct ANativeWindow *)window;
	VkResult result = vki.vkCreateAndroidSurfaceKHR(s_vk.instance, &info, NULL, &s_vk.surface);
	return surfaceMade("vkCreateAndroidSurfaceKHR", result);
}
#endif

static int32_t surfaceFailure(const char *call, VkResult result) {
	if (result == VK_ERROR_SURFACE_LOST_KHR) return fail(VULKAN_SURFACE_LOST, "%s: the surface is lost", call);
	return failCall(call, result);
}

static int32_t surfaceList(const char *call, VkResult result) {
	return result == VK_SUCCESS || result == VK_INCOMPLETE ? VULKAN_OK : surfaceFailure(call, result);
}

int32_t vulkanSurfaceQuery(void) {
	if (s_vk.physicalDevice == NULL) return fail(VULKAN_ERROR_ORDER, "vulkanSurfaceQuery before vulkanAdapterSelect");
	if (s_vk.surface == VK_NULL_HANDLE) return fail(VULKAN_ERROR_ORDER, "vulkanSurfaceQuery without a surface");
	s_surfaceInfo.queried = 0;
	VkPhysicalDevice device = s_vk.physicalDevice;
	VkResult result = vki.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, s_vk.surface, &s_surfaceInfo.capabilities);
	if (result != VK_SUCCESS) return surfaceFailure("vkGetPhysicalDeviceSurfaceCapabilitiesKHR", result);

	uint32_t formats = 0;
	int32_t status = surfaceList("vkGetPhysicalDeviceSurfaceFormatsKHR",
		vki.vkGetPhysicalDeviceSurfaceFormatsKHR(device, s_vk.surface, &formats, NULL));
	if (status != VULKAN_OK) return status;
	VkSurfaceFormatKHR *formatList = realloc(s_surfaceInfo.formats, sizeof *formatList * (formats > 0 ? formats : 1));
	if (formatList == NULL) return fail(VULKAN_OUT_OF_MEMORY, "out of memory listing %u surface formats", formats);
	s_surfaceInfo.formats = formatList;
	status = surfaceList("vkGetPhysicalDeviceSurfaceFormatsKHR",
		vki.vkGetPhysicalDeviceSurfaceFormatsKHR(device, s_vk.surface, &formats, formatList));
	if (status != VULKAN_OK) return status;
	s_surfaceInfo.formatCount = formats;

	uint32_t modes = 0;
	status = surfaceList("vkGetPhysicalDeviceSurfacePresentModesKHR",
		vki.vkGetPhysicalDeviceSurfacePresentModesKHR(device, s_vk.surface, &modes, NULL));
	if (status != VULKAN_OK) return status;
	VkPresentModeKHR *modeList = realloc(s_surfaceInfo.presentModes, sizeof *modeList * (modes > 0 ? modes : 1));
	if (modeList == NULL) return fail(VULKAN_OUT_OF_MEMORY, "out of memory listing %u present modes", modes);
	s_surfaceInfo.presentModes = modeList;
	status = surfaceList("vkGetPhysicalDeviceSurfacePresentModesKHR",
		vki.vkGetPhysicalDeviceSurfacePresentModesKHR(device, s_vk.surface, &modes, modeList));
	if (status != VULKAN_OK) return status;
	s_surfaceInfo.presentModeCount = modes;
	s_surfaceInfo.queried = 1;
	return VULKAN_OK;
}

static int32_t surfaceQueried(const char *caller) {
	if (!s_surfaceInfo.queried) return fail(VULKAN_ERROR_ORDER, "%s before vulkanSurfaceQuery", caller);
	return VULKAN_OK;
}

uint32_t vulkanSurfaceCapability(int32_t field) {
	if (surfaceQueried("vulkanSurfaceCapability") != VULKAN_OK) return 0;
	const VkSurfaceCapabilitiesKHR *c = &s_surfaceInfo.capabilities;
	switch (field) {
	case VULKAN_SURFACE_MIN_IMAGES: return c->minImageCount;
	case VULKAN_SURFACE_MAX_IMAGES: return c->maxImageCount;
	case VULKAN_SURFACE_CURRENT_WIDTH: return c->currentExtent.width;
	case VULKAN_SURFACE_CURRENT_HEIGHT: return c->currentExtent.height;
	case VULKAN_SURFACE_MIN_WIDTH: return c->minImageExtent.width;
	case VULKAN_SURFACE_MIN_HEIGHT: return c->minImageExtent.height;
	case VULKAN_SURFACE_MAX_WIDTH: return c->maxImageExtent.width;
	case VULKAN_SURFACE_MAX_HEIGHT: return c->maxImageExtent.height;
	case VULKAN_SURFACE_CURRENT_TRANSFORM: return (uint32_t)c->currentTransform;
	case VULKAN_SURFACE_TRANSFORMS: return c->supportedTransforms;
	case VULKAN_SURFACE_COMPOSITE_ALPHA: return c->supportedCompositeAlpha;
	case VULKAN_SURFACE_USAGE: return c->supportedUsageFlags;
	default:
		fail(VULKAN_ERROR_ORDER, "vulkanSurfaceCapability has no field %d", (int)field);
		return 0;
	}
}

int32_t vulkanSurfaceFormatCount(void) {
	if (surfaceQueried("vulkanSurfaceFormatCount") != VULKAN_OK) return -1;
	return (int32_t)s_surfaceInfo.formatCount;
}

int32_t vulkanSurfaceFormat(int32_t index, int32_t *format, uint32_t *colorSpace) {
	if (surfaceQueried("vulkanSurfaceFormat") != VULKAN_OK) return VULKAN_ERROR_ORDER;
	if (index < 0 || (uint32_t)index >= s_surfaceInfo.formatCount) {
		return fail(VULKAN_ERROR_ORDER, "vulkanSurfaceFormat %d is not below the %u surface formats",
			(int)index, s_surfaceInfo.formatCount);
	}
	*format = (int32_t)s_surfaceInfo.formats[index].format;
	*colorSpace = (uint32_t)s_surfaceInfo.formats[index].colorSpace;
	return VULKAN_OK;
}

int32_t vulkanSurfacePresentModeCount(void) {
	if (surfaceQueried("vulkanSurfacePresentModeCount") != VULKAN_OK) return -1;
	return (int32_t)s_surfaceInfo.presentModeCount;
}

uint32_t vulkanSurfacePresentMode(int32_t index) {
	if (surfaceQueried("vulkanSurfacePresentMode") != VULKAN_OK) return 0;
	if (index < 0 || (uint32_t)index >= s_surfaceInfo.presentModeCount) {
		fail(VULKAN_ERROR_ORDER, "vulkanSurfacePresentMode %d is not below the %u present modes",
			(int)index, s_surfaceInfo.presentModeCount);
		return 0;
	}
	return (uint32_t)s_surfaceInfo.presentModes[index];
}

static const char *missingFeature(const VkPhysicalDeviceFeatures *features) {
	if (!features->independentBlend) return "independentBlend";
	if (!features->fullDrawIndexUint32) return "fullDrawIndexUint32";
	if (!features->imageCubeArray) return "imageCubeArray";
	if (!features->sampleRateShading) return "sampleRateShading";
	if (!features->depthBiasClamp) return "depthBiasClamp";
	if (!features->fragmentStoresAndAtomics) return "fragmentStoresAndAtomics";
	if (!features->samplerAnisotropy) return "samplerAnisotropy";
	return NULL;
}

static int32_t queueFamilyOf(VkPhysicalDevice device, uint32_t *family) {
	uint32_t count = 0;
	vki.vkGetPhysicalDeviceQueueFamilyProperties(device, &count, NULL);
	VkQueueFamilyProperties *families = malloc(sizeof *families * (count > 0 ? count : 1));
	if (families == NULL) return 0;
	vki.vkGetPhysicalDeviceQueueFamilyProperties(device, &count, families);
	VkQueueFlags wanted = VK_QUEUE_GRAPHICS_BIT | VK_QUEUE_COMPUTE_BIT;
	int32_t found = 0;
	for (uint32_t i = 0; i < count && !found; i++) {
		if ((families[i].queueFlags & wanted) != wanted) continue;
		VkBool32 present = VK_TRUE;
		if (s_vk.surface != VK_NULL_HANDLE) {
			VkResult result = vki.vkGetPhysicalDeviceSurfaceSupportKHR(device, i, s_vk.surface, &present);
			if (result != VK_SUCCESS) present = VK_FALSE;
		}
		if (present) {
			*family = i;
			found = 1;
		}
	}
	free(families);
	return found;
}

static const char *unsuitable(VkPhysicalDevice device, const VkPhysicalDeviceProperties *properties, uint32_t *family) {
	if (properties->apiVersion < VK_API_VERSION_1_1) return "supports Vulkan below 1.1";
	VkPhysicalDeviceFeatures features;
	vki.vkGetPhysicalDeviceFeatures(device, &features);
	const char *feature = missingFeature(&features);
	if (feature != NULL) return feature;
	if (!hasDeviceExtension(device, VK_KHR_SWAPCHAIN_EXTENSION_NAME)) return VK_KHR_SWAPCHAIN_EXTENSION_NAME;
	if (!queueFamilyOf(device, family)) {
		return s_vk.surface != VK_NULL_HANDLE ? "a graphics+compute+present queue family" : "a graphics+compute queue family";
	}
	return NULL;
}

static uint32_t adapterScore(const VkPhysicalDeviceProperties *properties, int32_t powerPreference) {
	uint32_t score = 0;
	if (properties->deviceType == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU && powerPreference == VULKAN_POWER_LOW) {
		score += 1000;
	}
	if (properties->deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU && powerPreference == VULKAN_POWER_HIGH) {
		score += 1000;
	}
	return score + properties->limits.maxImageDimension2D;
}

static int32_t chooseAdapter(VkPhysicalDevice *devices, uint32_t count, int32_t powerPreference) {
	const char *forced = getenv("VOID_VULKAN_ADAPTER");
	VkPhysicalDeviceProperties properties;
	uint32_t family = 0;
	if (forced != NULL && forced[0] != 0) {
		char *end = NULL;
		long index = strtol(forced, &end, 10);
		if (*end != 0 || index < 0 || index >= (long)count) {
			return fail(VULKAN_ERROR_ADAPTER, "VOID_VULKAN_ADAPTER=%s is not an index below %u", forced, count);
		}
		vki.vkGetPhysicalDeviceProperties(devices[index], &properties);
		const char *reason = unsuitable(devices[index], &properties, &family);
		if (reason != NULL) {
			return fail(VULKAN_ERROR_ADAPTER, "VOID_VULKAN_ADAPTER=%s picks %s, which lacks %s", forced, properties.deviceName, reason);
		}
		s_vk.physicalDevice = devices[index];
		s_vk.properties = properties;
		s_vk.queueFamily = family;
		return VULKAN_OK;
	}
	uint32_t bestScore = 0;
	for (uint32_t i = 0; i < count; i++) {
		vki.vkGetPhysicalDeviceProperties(devices[i], &properties);
		const char *reason = unsuitable(devices[i], &properties, &family);
		if (reason != NULL) {
			fprintf(stderr, "vulkan: skipping %s, which lacks %s\n", properties.deviceName, reason);
			continue;
		}
		uint32_t score = adapterScore(&properties, powerPreference);
		if (s_vk.physicalDevice == NULL || score > bestScore) {
			bestScore = score;
			s_vk.physicalDevice = devices[i];
			s_vk.properties = properties;
			s_vk.queueFamily = family;
		}
	}
	if (s_vk.physicalDevice == NULL) {
		return fail(VULKAN_ERROR_ADAPTER, "none of the %u Vulkan devices has what Void needs; stderr names what each lacks", count);
	}
	return VULKAN_OK;
}

int32_t vulkanAdapterSelect(int32_t powerPreference) {
	if (s_vk.instance == NULL) return fail(VULKAN_ERROR_ORDER, "vulkanAdapterSelect before vulkanInstanceCreate");
	if (s_vk.physicalDevice != NULL) return fail(VULKAN_ERROR_ORDER, "vulkanAdapterSelect called twice");
	uint32_t count = 0;
	VkResult result = vki.vkEnumeratePhysicalDevices(s_vk.instance, &count, NULL);
	if (result != VK_SUCCESS) return failCall("vkEnumeratePhysicalDevices", result);
	if (count == 0) return fail(VULKAN_ERROR_ADAPTER, "vkEnumeratePhysicalDevices found no device");
	VkPhysicalDevice *devices = malloc(sizeof *devices * count);
	if (devices == NULL) return fail(VULKAN_ERROR_ADAPTER, "out of memory listing %u Vulkan devices", count);
	result = vki.vkEnumeratePhysicalDevices(s_vk.instance, &count, devices);
	int32_t status = result == VK_SUCCESS || result == VK_INCOMPLETE
		? chooseAdapter(devices, count, powerPreference)
		: failCall("vkEnumeratePhysicalDevices", result);
	free(devices);
	if (status == VULKAN_OK) {
		vki.vkGetPhysicalDeviceFeatures(s_vk.physicalDevice, &s_vk.supported);
		vki.vkGetPhysicalDeviceMemoryProperties(s_vk.physicalDevice, &s_vk.memory);
	}
	return status;
}

uint32_t vulkanAdapterVendorId(void) { return s_vk.properties.vendorID; }
uint32_t vulkanAdapterDeviceId(void) { return s_vk.properties.deviceID; }
const char *vulkanAdapterName(void) { return s_vk.properties.deviceName; }
uint32_t vulkanAdapterDriverVersion(void) { return s_vk.properties.driverVersion; }
uint32_t vulkanAdapterApiVersion(void) { return s_vk.properties.apiVersion; }
int32_t vulkanAdapterQueueFamily(void) { return s_vk.physicalDevice != NULL ? (int32_t)s_vk.queueFamily : -1; }

static uint32_t smallest(uint32_t a, uint32_t b) { return a < b ? a : b; }

int64_t vulkanAdapterLimit(int32_t limit) {
	const VkPhysicalDeviceLimits *l = &s_vk.properties.limits;
	switch (limit) {
	case VULKAN_LIMIT_TEXTURE_DIMENSION_1D: return l->maxImageDimension1D;
	case VULKAN_LIMIT_TEXTURE_DIMENSION_2D:
		return smallest(smallest(l->maxImageDimension2D, l->maxImageDimensionCube),
			smallest(l->maxFramebufferWidth, l->maxFramebufferHeight));
	case VULKAN_LIMIT_TEXTURE_DIMENSION_3D: return l->maxImageDimension3D;
	case VULKAN_LIMIT_TEXTURE_ARRAY_LAYERS: return l->maxImageArrayLayers;
	case VULKAN_LIMIT_BIND_GROUPS: return l->maxBoundDescriptorSets;
	case VULKAN_LIMIT_SAMPLED_TEXTURES_PER_STAGE: return l->maxPerStageDescriptorSampledImages;
	case VULKAN_LIMIT_SAMPLERS_PER_STAGE: return l->maxPerStageDescriptorSamplers;
	case VULKAN_LIMIT_STORAGE_BUFFERS_PER_STAGE: return l->maxPerStageDescriptorStorageBuffers;
	case VULKAN_LIMIT_STORAGE_TEXTURES_PER_STAGE: return l->maxPerStageDescriptorStorageImages;
	case VULKAN_LIMIT_UNIFORM_BUFFERS_PER_STAGE: return l->maxPerStageDescriptorUniformBuffers;
	case VULKAN_LIMIT_UNIFORM_BUFFER_BINDING_SIZE: return l->maxUniformBufferRange;
	case VULKAN_LIMIT_STORAGE_BUFFER_BINDING_SIZE: return l->maxStorageBufferRange;
	case VULKAN_LIMIT_VERTEX_BUFFERS: return l->maxVertexInputBindings;
	case VULKAN_LIMIT_VERTEX_ATTRIBUTES: return l->maxVertexInputAttributes;
	case VULKAN_LIMIT_COLOR_ATTACHMENTS: return l->maxColorAttachments;
	case VULKAN_LIMIT_WORKGROUP_SIZE_X: return l->maxComputeWorkGroupSize[0];
	case VULKAN_LIMIT_WORKGROUP_SIZE_Y: return l->maxComputeWorkGroupSize[1];
	case VULKAN_LIMIT_WORKGROUP_SIZE_Z: return l->maxComputeWorkGroupSize[2];
	case VULKAN_LIMIT_WORKGROUP_INVOCATIONS: return l->maxComputeWorkGroupInvocations;
	case VULKAN_LIMIT_WORKGROUPS_PER_DIMENSION:
		return smallest(smallest(l->maxComputeWorkGroupCount[0], l->maxComputeWorkGroupCount[1]),
			l->maxComputeWorkGroupCount[2]);
	case VULKAN_LIMIT_UNIFORM_OFFSET_ALIGNMENT: return (int64_t)l->minUniformBufferOffsetAlignment;
	case VULKAN_LIMIT_STORAGE_OFFSET_ALIGNMENT: return (int64_t)l->minStorageBufferOffsetAlignment;
	case VULKAN_LIMIT_NON_COHERENT_ATOM_SIZE: return (int64_t)l->nonCoherentAtomSize;
	case VULKAN_LIMIT_MEMORY_ALLOCATION_COUNT: return l->maxMemoryAllocationCount;
	default:
		fail(VULKAN_ERROR_ORDER, "vulkanAdapterLimit has no limit %d", (int)limit);
		return -1;
	}
}

int32_t vulkanDeviceCreate(void) {
	if (s_vk.physicalDevice == NULL) return fail(VULKAN_ERROR_ORDER, "vulkanDeviceCreate before vulkanAdapterSelect");
	if (s_vk.device != NULL) return fail(VULKAN_ERROR_ORDER, "vulkanDeviceCreate called twice");

	float priority = 1.0f;
	VkDeviceQueueCreateInfo queue = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO };
	queue.queueFamilyIndex = s_vk.queueFamily;
	queue.queueCount = 1;
	queue.pQueuePriorities = &priority;

	VkPhysicalDeviceFeatures enabled = { 0 };
	enabled.independentBlend = VK_TRUE;
	enabled.fullDrawIndexUint32 = VK_TRUE;
	enabled.imageCubeArray = VK_TRUE;
	enabled.sampleRateShading = VK_TRUE;
	enabled.depthBiasClamp = VK_TRUE;
	enabled.fragmentStoresAndAtomics = VK_TRUE;
	enabled.samplerAnisotropy = VK_TRUE;
	uint32_t features = 0;
#if defined(__ANDROID__)
	if (s_vk.supported.textureCompressionETC2) {
		enabled.textureCompressionETC2 = VK_TRUE;
		features |= VULKAN_FEATURE_ETC2;
	}
	if (s_vk.supported.textureCompressionASTC_LDR) {
		enabled.textureCompressionASTC_LDR = VK_TRUE;
		features |= VULKAN_FEATURE_ASTC;
	}
#else
	if (s_vk.supported.textureCompressionBC) {
		enabled.textureCompressionBC = VK_TRUE;
		features |= VULKAN_FEATURE_BC;
	}
#endif

	const char *extensions[1] = { VK_KHR_SWAPCHAIN_EXTENSION_NAME };
	VkDeviceCreateInfo info = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO };
	info.queueCreateInfoCount = 1;
	info.pQueueCreateInfos = &queue;
	info.enabledExtensionCount = 1;
	info.ppEnabledExtensionNames = extensions;
	info.pEnabledFeatures = &enabled;
	VkResult result = vki.vkCreateDevice(s_vk.physicalDevice, &info, NULL, &s_vk.device);
	if (result != VK_SUCCESS) {
		s_vk.device = NULL;
		return failCall("vkCreateDevice", result);
	}
	s_vk.features = features;

	s_missing[0] = 0;
	VULKAN_DEVICE_FUNCS(VULKAN_LOAD_DEVICE)
	if (s_missing[0] != 0) return failMissing("vkGetDeviceProcAddr");
	vkd.vkGetDeviceQueue(s_vk.device, s_vk.queueFamily, 0, &s_vk.queue);

	VkCommandPoolCreateInfo pool = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO };
	pool.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
	pool.queueFamilyIndex = s_vk.queueFamily;
	result = vkd.vkCreateCommandPool(s_vk.device, &pool, NULL, &s_vk.commandPool);
	return result == VK_SUCCESS ? VULKAN_OK : failCall("vkCreateCommandPool", result);
}

uint32_t vulkanDeviceFeatures(void) { return s_vk.features; }

int32_t vulkanMemoryTypeCount(void) { return (int32_t)s_vk.memory.memoryTypeCount; }

int32_t vulkanMemoryType(int32_t index, uint32_t *flags, int32_t *heap) {
	if (index < 0 || (uint32_t)index >= s_vk.memory.memoryTypeCount) {
		return fail(VULKAN_ERROR_ORDER, "vulkanMemoryType %d is not below the %u memory types",
			(int)index, s_vk.memory.memoryTypeCount);
	}
	*flags = s_vk.memory.memoryTypes[index].propertyFlags;
	*heap = (int32_t)s_vk.memory.memoryTypes[index].heapIndex;
	return VULKAN_OK;
}

int32_t vulkanMemoryHeapCount(void) { return (int32_t)s_vk.memory.memoryHeapCount; }

uint64_t vulkanMemoryHeapSize(int32_t heap) {
	if (heap < 0 || (uint32_t)heap >= s_vk.memory.memoryHeapCount) {
		fail(VULKAN_ERROR_ORDER, "vulkanMemoryHeapSize %d is not below the %u memory heaps",
			(int)heap, s_vk.memory.memoryHeapCount);
		return 0;
	}
	return s_vk.memory.memoryHeaps[heap].size;
}

static int32_t deviceReady(const char *caller) {
	if (s_vk.device == NULL) return fail(VULKAN_ERROR_ORDER, "%s before vulkanDeviceCreate", caller);
	return VULKAN_OK;
}

int32_t vulkanDeviceReady(void) { return deviceReady("requestDevice"); }

uint32_t vulkanFormatOptimalFeatures(int32_t format) {
	if (s_vk.physicalDevice == NULL) {
		fail(VULKAN_ERROR_ORDER, "vulkanFormatOptimalFeatures before vulkanAdapterSelect");
		return 0;
	}
	VkFormatProperties properties;
	vki.vkGetPhysicalDeviceFormatProperties(s_vk.physicalDevice, (VkFormat)format, &properties);
	return properties.optimalTilingFeatures;
}

int32_t vulkanMemoryAllocate(
	int32_t typeIndex,
	uint64_t size,
	uint64_t dedicatedBuffer,
	uint64_t dedicatedImage,
	uint64_t *memory) {
	*memory = 0;
	if (deviceReady("vulkanMemoryAllocate") != VULKAN_OK) return VULKAN_ERROR_ORDER;
	if (typeIndex < 0 || (uint32_t)typeIndex >= s_vk.memory.memoryTypeCount || size == 0) {
		return fail(VULKAN_ERROR_ORDER, "vulkanMemoryAllocate of %llu bytes on memory type %d of %u",
			(unsigned long long)size, (int)typeIndex, s_vk.memory.memoryTypeCount);
	}
	if (dedicatedBuffer != 0 && dedicatedImage != 0) {
		return fail(VULKAN_ERROR_ORDER, "vulkanMemoryAllocate dedicated to a buffer and an image at once");
	}
	VkMemoryDedicatedAllocateInfo dedicated = { .sType = VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO };
	dedicated.buffer = HANDLE_IN(VkBuffer, dedicatedBuffer);
	dedicated.image = HANDLE_IN(VkImage, dedicatedImage);
	VkMemoryAllocateInfo info = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO };
	info.pNext = dedicatedBuffer != 0 || dedicatedImage != 0 ? &dedicated : NULL;
	info.allocationSize = size;
	info.memoryTypeIndex = (uint32_t)typeIndex;
	VkDeviceMemory fresh = VK_NULL_HANDLE;
	VkResult result = vkd.vkAllocateMemory(s_vk.device, &info, NULL, &fresh);
	if (result != VK_SUCCESS) return failCall("vkAllocateMemory", result);
	*memory = HANDLE_OUT(fresh);
	return VULKAN_OK;
}

int32_t vulkanMemoryMap(uint64_t memory, uint64_t *address) {
	void *mapped = NULL;
	VkResult result = vkd.vkMapMemory(s_vk.device, HANDLE_IN(VkDeviceMemory, memory), 0, VK_WHOLE_SIZE, 0, &mapped);
	*address = result == VK_SUCCESS ? (uint64_t)(uintptr_t)mapped : 0;
	return result == VK_SUCCESS ? VULKAN_OK : failCall("vkMapMemory", result);
}

void vulkanMemoryFree(uint64_t memory) {
	vkd.vkFreeMemory(s_vk.device, HANDLE_IN(VkDeviceMemory, memory), NULL);
}

static VkMappedMemoryRange mappedRange(uint64_t memory, uint64_t offset, uint64_t size) {
	VkMappedMemoryRange range = { .sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE };
	range.memory = HANDLE_IN(VkDeviceMemory, memory);
	range.offset = offset;
	range.size = size;
	return range;
}

int32_t vulkanMappedWrite(
	uint64_t memory,
	uint64_t address,
	uint64_t offset,
	void *data,
	uint64_t dataOffset,
	uint64_t rowBytes,
	uint64_t sourcePitch,
	uint64_t targetPitch,
	uint32_t rows,
	uint64_t flushOffset,
	uint64_t flushSize) {
	if (address == 0) return fail(VULKAN_ERROR_ORDER, "vulkanMappedWrite to memory that is not mapped");
	if (rows == 0 || rowBytes == 0) return VULKAN_OK;
	if (rowBytes > targetPitch && rows > 1) {
		return fail(VULKAN_ERROR_ORDER, "vulkanMappedWrite: rows of %llu bytes overlap at a pitch of %llu",
			(unsigned long long)rowBytes, (unsigned long long)targetPitch);
	}
	uint8_t *target = (uint8_t *)(uintptr_t)address + offset;
	const uint8_t *source = (const uint8_t *)data + dataOffset;
	if (sourcePitch == rowBytes && targetPitch == rowBytes) {
		memcpy(target, source, (uint64_t)(rows - 1) * targetPitch + rowBytes);
	} else {
		for (uint32_t row = 0; row < rows; row++) {
			memcpy(target + row * targetPitch, source + row * sourcePitch, rowBytes);
		}
	}
	if (flushSize == 0) return VULKAN_OK;
	VkMappedMemoryRange range = mappedRange(memory, flushOffset, flushSize);
	VkResult result = vkd.vkFlushMappedMemoryRanges(s_vk.device, 1, &range);
	return result == VK_SUCCESS ? VULKAN_OK : failCall("vkFlushMappedMemoryRanges", result);
}

int32_t vulkanMappedRead(
	uint64_t memory,
	uint64_t address,
	uint64_t offset,
	void *out,
	uint64_t bytes,
	uint64_t invalidateOffset,
	uint64_t invalidateSize) {
	if (address == 0) return fail(VULKAN_ERROR_ORDER, "vulkanMappedRead from memory that is not mapped");
	if (invalidateSize != 0) {
		VkMappedMemoryRange range = mappedRange(memory, invalidateOffset, invalidateSize);
		VkResult result = vkd.vkInvalidateMappedMemoryRanges(s_vk.device, 1, &range);
		if (result != VK_SUCCESS) return failCall("vkInvalidateMappedMemoryRanges", result);
	}
	memcpy(out, (const uint8_t *)(uintptr_t)address + offset, bytes);
	return VULKAN_OK;
}

static void requirementsOut(
	const VkMemoryRequirements2 *requirements,
	const VkMemoryDedicatedRequirements *dedicated,
	uint64_t *size,
	uint64_t *alignment,
	uint32_t *typeBits,
	int32_t *dedication) {
	*size = requirements->memoryRequirements.size;
	*alignment = requirements->memoryRequirements.alignment;
	*typeBits = requirements->memoryRequirements.memoryTypeBits;
	*dedication = dedicated->requiresDedicatedAllocation ? VULKAN_DEDICATED_REQUIRED
		: dedicated->prefersDedicatedAllocation ? VULKAN_DEDICATED_PREFERRED
		: VULKAN_DEDICATED_NONE;
}

int32_t vulkanBufferCreate(uint64_t size, uint32_t usage, uint64_t *buffer) {
	*buffer = 0;
	if (deviceReady("vulkanBufferCreate") != VULKAN_OK) return VULKAN_ERROR_ORDER;
	if (size == 0) return fail(VULKAN_ERROR_ORDER, "vulkanBufferCreate of 0 bytes");
	VkBufferCreateInfo info = { .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO };
	info.size = size;
	info.usage = usage;
	info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
	VkBuffer fresh = VK_NULL_HANDLE;
	VkResult result = vkd.vkCreateBuffer(s_vk.device, &info, NULL, &fresh);
	if (result != VK_SUCCESS) return failCall("vkCreateBuffer", result);
	*buffer = HANDLE_OUT(fresh);
	return VULKAN_OK;
}

void vulkanBufferRequirements(uint64_t buffer, uint64_t *size, uint64_t *alignment, uint32_t *typeBits, int32_t *dedication) {
	VkBufferMemoryRequirementsInfo2 info = { .sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_REQUIREMENTS_INFO_2 };
	info.buffer = HANDLE_IN(VkBuffer, buffer);
	VkMemoryDedicatedRequirements dedicated = { .sType = VK_STRUCTURE_TYPE_MEMORY_DEDICATED_REQUIREMENTS };
	VkMemoryRequirements2 requirements = { .sType = VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2 };
	requirements.pNext = &dedicated;
	vkd.vkGetBufferMemoryRequirements2(s_vk.device, &info, &requirements);
	requirementsOut(&requirements, &dedicated, size, alignment, typeBits, dedication);
}

int32_t vulkanBufferBind(uint64_t buffer, uint64_t memory, uint64_t offset) {
	VkResult result = vkd.vkBindBufferMemory(
		s_vk.device, HANDLE_IN(VkBuffer, buffer), HANDLE_IN(VkDeviceMemory, memory), offset);
	return result == VK_SUCCESS ? VULKAN_OK : failCall("vkBindBufferMemory", result);
}

void vulkanBufferDestroy(uint64_t buffer) {
	vkd.vkDestroyBuffer(s_vk.device, HANDLE_IN(VkBuffer, buffer), NULL);
}

int32_t vulkanImageCreate(
	int32_t imageType,
	int32_t format,
	uint32_t width,
	uint32_t height,
	uint32_t depth,
	uint32_t mipLevels,
	uint32_t layers,
	uint32_t samples,
	uint32_t usage,
	uint32_t flags,
	uint64_t *image) {
	*image = 0;
	if (deviceReady("vulkanImageCreate") != VULKAN_OK) return VULKAN_ERROR_ORDER;
	VkImageCreateInfo info = { .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO };
	info.flags = flags;
	info.imageType = (VkImageType)imageType;
	info.format = (VkFormat)format;
	info.extent.width = width;
	info.extent.height = height;
	info.extent.depth = depth;
	info.mipLevels = mipLevels;
	info.arrayLayers = layers;
	info.samples = (VkSampleCountFlagBits)samples;
	info.tiling = VK_IMAGE_TILING_OPTIMAL;
	info.usage = usage;
	info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
	info.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
	VkImage fresh = VK_NULL_HANDLE;
	VkResult result = vkd.vkCreateImage(s_vk.device, &info, NULL, &fresh);
	if (result != VK_SUCCESS) return failCall("vkCreateImage", result);
	*image = HANDLE_OUT(fresh);
	return VULKAN_OK;
}

void vulkanImageRequirements(uint64_t image, uint64_t *size, uint64_t *alignment, uint32_t *typeBits, int32_t *dedication) {
	VkImageMemoryRequirementsInfo2 info = { .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_REQUIREMENTS_INFO_2 };
	info.image = HANDLE_IN(VkImage, image);
	VkMemoryDedicatedRequirements dedicated = { .sType = VK_STRUCTURE_TYPE_MEMORY_DEDICATED_REQUIREMENTS };
	VkMemoryRequirements2 requirements = { .sType = VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2 };
	requirements.pNext = &dedicated;
	vkd.vkGetImageMemoryRequirements2(s_vk.device, &info, &requirements);
	requirementsOut(&requirements, &dedicated, size, alignment, typeBits, dedication);
}

int32_t vulkanImageBind(uint64_t image, uint64_t memory, uint64_t offset) {
	VkResult result = vkd.vkBindImageMemory(
		s_vk.device, HANDLE_IN(VkImage, image), HANDLE_IN(VkDeviceMemory, memory), offset);
	return result == VK_SUCCESS ? VULKAN_OK : failCall("vkBindImageMemory", result);
}

void vulkanImageDestroy(uint64_t image) {
	vkd.vkDestroyImage(s_vk.device, HANDLE_IN(VkImage, image), NULL);
}

static int32_t viewMake(
	VkImage image,
	VkImageViewType viewType,
	VkFormat format,
	VkImageAspectFlags aspect,
	uint32_t baseMip,
	uint32_t mipCount,
	uint32_t baseLayer,
	uint32_t layerCount,
	VkImageView *view) {
	VkImageViewCreateInfo info = { .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO };
	info.image = image;
	info.viewType = viewType;
	info.format = format;
	info.components.r = VK_COMPONENT_SWIZZLE_IDENTITY;
	info.components.g = VK_COMPONENT_SWIZZLE_IDENTITY;
	info.components.b = VK_COMPONENT_SWIZZLE_IDENTITY;
	info.components.a = VK_COMPONENT_SWIZZLE_IDENTITY;
	info.subresourceRange.aspectMask = aspect;
	info.subresourceRange.baseMipLevel = baseMip;
	info.subresourceRange.levelCount = mipCount;
	info.subresourceRange.baseArrayLayer = baseLayer;
	info.subresourceRange.layerCount = layerCount;
	VkResult result = vkd.vkCreateImageView(s_vk.device, &info, NULL, view);
	if (result != VK_SUCCESS) {
		*view = VK_NULL_HANDLE;
		return failCall("vkCreateImageView", result);
	}
	return VULKAN_OK;
}

int32_t vulkanViewCreate(
	uint64_t image,
	int32_t viewType,
	int32_t format,
	uint32_t aspect,
	uint32_t baseMip,
	uint32_t mipCount,
	uint32_t baseLayer,
	uint32_t layerCount,
	uint64_t *view) {
	VkImageView fresh = VK_NULL_HANDLE;
	int32_t status = viewMake(HANDLE_IN(VkImage, image), (VkImageViewType)viewType, (VkFormat)format, aspect,
		baseMip, mipCount, baseLayer, layerCount, &fresh);
	*view = HANDLE_OUT(fresh);
	return status;
}

void vulkanViewDestroy(uint64_t view) {
	vkd.vkDestroyImageView(s_vk.device, HANDLE_IN(VkImageView, view), NULL);
}

int32_t vulkanSamplerCreate(
	int32_t magFilter,
	int32_t minFilter,
	int32_t mipmapMode,
	int32_t addressU,
	int32_t addressV,
	int32_t addressW,
	float lodMin,
	float lodMax,
	int32_t compareOp,
	uint32_t maxAnisotropy,
	uint64_t *sampler) {
	*sampler = 0;
	if (deviceReady("vulkanSamplerCreate") != VULKAN_OK) return VULKAN_ERROR_ORDER;
	VkSamplerCreateInfo info = { .sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO };
	info.magFilter = (VkFilter)magFilter;
	info.minFilter = (VkFilter)minFilter;
	info.mipmapMode = (VkSamplerMipmapMode)mipmapMode;
	info.addressModeU = (VkSamplerAddressMode)addressU;
	info.addressModeV = (VkSamplerAddressMode)addressV;
	info.addressModeW = (VkSamplerAddressMode)addressW;
	info.mipLodBias = 0.0f;
	info.anisotropyEnable = maxAnisotropy > 1 ? VK_TRUE : VK_FALSE;
	info.maxAnisotropy = (float)maxAnisotropy;
	info.compareEnable = compareOp >= 0 ? VK_TRUE : VK_FALSE;
	info.compareOp = compareOp >= 0 ? (VkCompareOp)compareOp : VK_COMPARE_OP_NEVER;
	info.minLod = lodMin;
	info.maxLod = lodMax;
	info.borderColor = VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK;
	info.unnormalizedCoordinates = VK_FALSE;
	VkSampler fresh = VK_NULL_HANDLE;
	VkResult result = vkd.vkCreateSampler(s_vk.device, &info, NULL, &fresh);
	if (result != VK_SUCCESS) return failCall("vkCreateSampler", result);
	*sampler = HANDLE_OUT(fresh);
	return VULKAN_OK;
}

void vulkanSamplerDestroy(uint64_t sampler) {
	vkd.vkDestroySampler(s_vk.device, HANDLE_IN(VkSampler, sampler), NULL);
}

static int32_t commandsOpen(const char *caller, VkCommandBuffer *opened) {
	if (*opened != NULL) return VULKAN_OK;
	if (s_vk.commandPool == VK_NULL_HANDLE) return fail(VULKAN_ERROR_ORDER, "%s before vulkanDeviceCreate", caller);
	VkCommandBufferAllocateInfo info = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO };
	info.commandPool = s_vk.commandPool;
	info.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
	info.commandBufferCount = 1;
	VkCommandBuffer fresh = NULL;
	VkResult result = vkd.vkAllocateCommandBuffers(s_vk.device, &info, &fresh);
	if (result != VK_SUCCESS) return failCall("vkAllocateCommandBuffers", result);
	VkCommandBufferBeginInfo begin = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
	begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
	result = vkd.vkBeginCommandBuffer(fresh, &begin);
	if (result != VK_SUCCESS) {
		vkd.vkFreeCommandBuffers(s_vk.device, s_vk.commandPool, 1, &fresh);
		return failCall("vkBeginCommandBuffer", result);
	}
	*opened = fresh;
	return VULKAN_OK;
}

static int32_t recording(const char *caller, VkCommandBuffer *commands) {
	*commands = s_recording;
	if (s_queueStream) return fail(VULKAN_ERROR_ORDER, "%s while the queue stream records", caller);
	if (s_passOpen) return fail(VULKAN_ERROR_ORDER, "%s inside a render pass", caller);
	int32_t status = commandsOpen(caller, &s_recording);
	*commands = s_recording;
	return status;
}

static int32_t streamed(const char *caller, VkCommandBuffer *commands) {
	if (!s_queueStream) return recording(caller, commands);
	int32_t status = commandsOpen(caller, &s_transfer);
	*commands = s_transfer;
	return status;
}

int32_t vulkanQueueStream(uint32_t on) {
	if (s_imageBarrierCount != 0) {
		return fail(VULKAN_ERROR_ORDER, "vulkanQueueStream with %u image barriers never flushed", s_imageBarrierCount);
	}
	s_queueStream = on != 0;
	return VULKAN_OK;
}

int32_t vulkanBarrierImage(uint64_t image, uint32_t aspect, uint32_t sourceAccess, uint32_t targetAccess, int32_t oldLayout, int32_t newLayout) {
	if (s_imageBarrierCount == s_imageBarrierCapacity) {
		uint32_t capacity = s_imageBarrierCapacity > 0 ? s_imageBarrierCapacity * 2 : 16;
		VkImageMemoryBarrier *grown = realloc(s_imageBarriers, sizeof *grown * capacity);
		if (grown == NULL) return fail(VULKAN_OUT_OF_MEMORY, "out of memory growing the image barrier list to %u", capacity);
		s_imageBarriers = grown;
		s_imageBarrierCapacity = capacity;
	}
	VkImageMemoryBarrier *barrier = &s_imageBarriers[s_imageBarrierCount++];
	memset(barrier, 0, sizeof *barrier);
	barrier->sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
	barrier->srcAccessMask = sourceAccess;
	barrier->dstAccessMask = targetAccess;
	barrier->oldLayout = (VkImageLayout)oldLayout;
	barrier->newLayout = (VkImageLayout)newLayout;
	barrier->srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
	barrier->dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
	barrier->image = HANDLE_IN(VkImage, image);
	barrier->subresourceRange.aspectMask = aspect;
	barrier->subresourceRange.baseMipLevel = 0;
	barrier->subresourceRange.levelCount = VK_REMAINING_MIP_LEVELS;
	barrier->subresourceRange.baseArrayLayer = 0;
	barrier->subresourceRange.layerCount = VK_REMAINING_ARRAY_LAYERS;
	return VULKAN_OK;
}

int32_t vulkanBarrierFlush(uint32_t sourceStages, uint32_t targetStages, uint32_t sourceAccess, uint32_t targetAccess) {
	if ((sourceStages | targetStages) == 0 && s_imageBarrierCount == 0) return VULKAN_OK;
	uint32_t images = s_imageBarrierCount;
	s_imageBarrierCount = 0;
	if (targetStages == 0) {
		return fail(VULKAN_ERROR_ORDER, "vulkanBarrierFlush with %u image barriers and no target stage", images);
	}
	VkCommandBuffer commands = NULL;
	int32_t status = streamed("vulkanBarrierFlush", &commands);
	if (status != VULKAN_OK) return status;
	VkMemoryBarrier memory = { .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER };
	memory.srcAccessMask = sourceAccess;
	memory.dstAccessMask = targetAccess;
	vkd.vkCmdPipelineBarrier(
		commands,
		sourceStages != 0 ? sourceStages : VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
		targetStages,
		0,
		(sourceAccess | targetAccess) != 0 ? 1 : 0,
		&memory,
		0,
		NULL,
		images,
		s_imageBarriers);
	return VULKAN_OK;
}

int32_t vulkanCopyBuffer(uint64_t source, uint64_t sourceOffset, uint64_t target, uint64_t targetOffset, uint64_t bytes) {
	VkCommandBuffer commands = NULL;
	int32_t status = streamed("vulkanCopyBuffer", &commands);
	if (status != VULKAN_OK) return status;
	VkBufferCopy region = { .srcOffset = sourceOffset, .dstOffset = targetOffset, .size = bytes };
	vkd.vkCmdCopyBuffer(commands, HANDLE_IN(VkBuffer, source), HANDLE_IN(VkBuffer, target), 1, &region);
	return VULKAN_OK;
}

static VkBufferImageCopy imageRegion(
	uint64_t offset,
	uint32_t rowLength,
	uint32_t imageHeight,
	uint32_t aspect,
	uint32_t mip,
	int32_t x,
	int32_t y,
	int32_t z,
	uint32_t baseLayer,
	uint32_t layerCount,
	uint32_t width,
	uint32_t height,
	uint32_t depth) {
	VkBufferImageCopy region = { .bufferOffset = offset, .bufferRowLength = rowLength, .bufferImageHeight = imageHeight };
	region.imageSubresource.aspectMask = aspect;
	region.imageSubresource.mipLevel = mip;
	region.imageSubresource.baseArrayLayer = baseLayer;
	region.imageSubresource.layerCount = layerCount;
	region.imageOffset.x = x;
	region.imageOffset.y = y;
	region.imageOffset.z = z;
	region.imageExtent.width = width;
	region.imageExtent.height = height;
	region.imageExtent.depth = depth;
	return region;
}

int32_t vulkanCopyBufferToImage(
	uint64_t buffer,
	uint64_t offset,
	uint32_t rowLength,
	uint32_t imageHeight,
	uint64_t image,
	uint32_t aspect,
	uint32_t mip,
	int32_t x,
	int32_t y,
	int32_t z,
	uint32_t baseLayer,
	uint32_t layerCount,
	uint32_t width,
	uint32_t height,
	uint32_t depth) {
	VkCommandBuffer commands = NULL;
	int32_t status = streamed("vulkanCopyBufferToImage", &commands);
	if (status != VULKAN_OK) return status;
	VkBufferImageCopy region = imageRegion(offset, rowLength, imageHeight, aspect, mip, x, y, z, baseLayer, layerCount,
		width, height, depth);
	vkd.vkCmdCopyBufferToImage(
		commands, HANDLE_IN(VkBuffer, buffer), HANDLE_IN(VkImage, image), VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
	return VULKAN_OK;
}

int32_t vulkanCopyImageToBuffer(
	uint64_t buffer,
	uint64_t offset,
	uint32_t rowLength,
	uint32_t imageHeight,
	uint64_t image,
	uint32_t aspect,
	uint32_t mip,
	int32_t x,
	int32_t y,
	int32_t z,
	uint32_t baseLayer,
	uint32_t layerCount,
	uint32_t width,
	uint32_t height,
	uint32_t depth) {
	VkCommandBuffer commands = NULL;
	int32_t status = streamed("vulkanCopyImageToBuffer", &commands);
	if (status != VULKAN_OK) return status;
	VkBufferImageCopy region = imageRegion(offset, rowLength, imageHeight, aspect, mip, x, y, z, baseLayer, layerCount,
		width, height, depth);
	vkd.vkCmdCopyImageToBuffer(
		commands, HANDLE_IN(VkImage, image), VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, HANDLE_IN(VkBuffer, buffer), 1, &region);
	return VULKAN_OK;
}

int32_t vulkanCopyImage(
	uint64_t source,
	uint32_t sourceMip,
	int32_t sourceX,
	int32_t sourceY,
	int32_t sourceZ,
	uint32_t sourceLayer,
	uint64_t target,
	uint32_t targetMip,
	int32_t targetX,
	int32_t targetY,
	int32_t targetZ,
	uint32_t targetLayer,
	uint32_t aspect,
	uint32_t layerCount,
	uint32_t width,
	uint32_t height,
	uint32_t depth) {
	VkCommandBuffer commands = NULL;
	int32_t status = streamed("vulkanCopyImage", &commands);
	if (status != VULKAN_OK) return status;
	VkImageCopy region = { 0 };
	region.srcSubresource.aspectMask = aspect;
	region.srcSubresource.mipLevel = sourceMip;
	region.srcSubresource.baseArrayLayer = sourceLayer;
	region.srcSubresource.layerCount = layerCount;
	region.srcOffset.x = sourceX;
	region.srcOffset.y = sourceY;
	region.srcOffset.z = sourceZ;
	region.dstSubresource.aspectMask = aspect;
	region.dstSubresource.mipLevel = targetMip;
	region.dstSubresource.baseArrayLayer = targetLayer;
	region.dstSubresource.layerCount = layerCount;
	region.dstOffset.x = targetX;
	region.dstOffset.y = targetY;
	region.dstOffset.z = targetZ;
	region.extent.width = width;
	region.extent.height = height;
	region.extent.depth = depth;
	vkd.vkCmdCopyImage(commands, HANDLE_IN(VkImage, source), VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, HANDLE_IN(VkImage, target),
		VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
	return VULKAN_OK;
}

static VkDebugUtilsLabelEXT labelOf(const char *label) {
	VkDebugUtilsLabelEXT info = { .sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_LABEL_EXT, .pLabelName = label };
	return info;
}

static int32_t labelled(const char *caller, VkCommandBuffer *commands) {
	if (!s_passOpen || s_queueStream) return recording(caller, commands);
	*commands = s_recording;
	return VULKAN_OK;
}

int32_t vulkanCmdPushLabel(const char *label) {
	VkCommandBuffer commands = NULL;
	int32_t status = labelled("vulkanCmdPushLabel", &commands);
	if (status != VULKAN_OK) return status;
	if (vki.vkCmdBeginDebugUtilsLabelEXT == NULL) return VULKAN_OK;
	VkDebugUtilsLabelEXT info = labelOf(label);
	vki.vkCmdBeginDebugUtilsLabelEXT(commands, &info);
	return VULKAN_OK;
}

int32_t vulkanCmdPopLabel(void) {
	VkCommandBuffer commands = NULL;
	int32_t status = labelled("vulkanCmdPopLabel", &commands);
	if (status != VULKAN_OK) return status;
	if (vki.vkCmdEndDebugUtilsLabelEXT != NULL) vki.vkCmdEndDebugUtilsLabelEXT(commands);
	return VULKAN_OK;
}

int32_t vulkanCmdInsertLabel(const char *label) {
	VkCommandBuffer commands = NULL;
	int32_t status = labelled("vulkanCmdInsertLabel", &commands);
	if (status != VULKAN_OK) return status;
	if (vki.vkCmdInsertDebugUtilsLabelEXT == NULL) return VULKAN_OK;
	VkDebugUtilsLabelEXT info = labelOf(label);
	vki.vkCmdInsertDebugUtilsLabelEXT(commands, &info);
	return VULKAN_OK;
}

static int32_t validLoadStore(uint32_t load, uint32_t store) {
	return load <= VK_ATTACHMENT_LOAD_OP_DONT_CARE && store <= VK_ATTACHMENT_STORE_OP_DONT_CARE;
}

static int32_t validSamples(uint32_t samples) {
	return samples >= 1 && samples <= 64 && (samples & (samples - 1)) == 0;
}

static int32_t keyValid(const char *caller, const uint32_t *key, uint32_t words) {
	uint32_t colors = words > 0 ? key[0] : 0;
	if (words == 0 || colors > MAX_COLOR_ATTACHMENTS || words != 1 + colors * COLOR_KEY_WORDS + DEPTH_KEY_WORDS) {
		return fail(VULKAN_ERROR_ORDER, "%s: a key of %u words does not hold %u color attachments and a depth one",
			caller, words, colors);
	}
	return VULKAN_OK;
}

int32_t vulkanRenderPassCreate(const uint32_t *key, uint32_t words, uint64_t *renderPass) {
	*renderPass = 0;
	if (deviceReady("vulkanRenderPassCreate") != VULKAN_OK) return VULKAN_ERROR_ORDER;
	int32_t valid = keyValid("vulkanRenderPassCreate", key, words);
	if (valid != VULKAN_OK) return valid;
	uint32_t colors = key[0];
	VkAttachmentDescription attachments[MAX_PASS_ATTACHMENTS];
	VkAttachmentReference colorRefs[MAX_COLOR_ATTACHMENTS];
	VkAttachmentReference resolveRefs[MAX_COLOR_ATTACHMENTS];
	uint32_t count = 0;
	uint32_t resolves = 0;
	for (uint32_t i = 0; i < colors; i++) {
		const uint32_t *c = key + 1 + i * COLOR_KEY_WORDS;
		resolveRefs[i] = (VkAttachmentReference){ VK_ATTACHMENT_UNUSED, VK_IMAGE_LAYOUT_UNDEFINED };
		if (c[0] == VK_FORMAT_UNDEFINED) {
			colorRefs[i] = (VkAttachmentReference){ VK_ATTACHMENT_UNUSED, VK_IMAGE_LAYOUT_UNDEFINED };
			continue;
		}
		if (!validLoadStore(c[2], c[3]) || !validSamples(c[1])) {
			return fail(VULKAN_ERROR_ORDER, "vulkanRenderPassCreate: color %u has load op %u, store op %u and %u samples",
				i, c[2], c[3], c[1]);
		}
		VkAttachmentDescription color = { .format = (VkFormat)c[0], .samples = (VkSampleCountFlagBits)c[1] };
		color.loadOp = (VkAttachmentLoadOp)c[2];
		color.storeOp = (VkAttachmentStoreOp)c[3];
		color.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
		color.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
		color.initialLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
		color.finalLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
		colorRefs[i] = (VkAttachmentReference){ count, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };
		attachments[count++] = color;
		if (c[4] != VK_FORMAT_UNDEFINED) {
			VkAttachmentDescription resolve = color;
			resolve.format = (VkFormat)c[4];
			resolve.samples = VK_SAMPLE_COUNT_1_BIT;
			resolve.loadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
			resolve.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
			resolveRefs[i] = (VkAttachmentReference){ count, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };
			attachments[count++] = resolve;
			resolves++;
		}
	}
	const uint32_t *d = key + 1 + colors * COLOR_KEY_WORDS;
	VkAttachmentReference depthRef = { VK_ATTACHMENT_UNUSED, VK_IMAGE_LAYOUT_UNDEFINED };
	if (d[0] != 0) {
		if (!validLoadStore(d[3], d[4]) || !validLoadStore(d[5], d[6]) || !validSamples(d[2])) {
			return fail(VULKAN_ERROR_ORDER, "vulkanRenderPassCreate: the depth attachment has ops %u/%u, stencil ops %u/%u and %u samples",
				d[3], d[4], d[5], d[6], d[2]);
		}
		VkImageLayout layout = d[7] ? VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL : VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
		VkAttachmentDescription depth = { .format = (VkFormat)d[1], .samples = (VkSampleCountFlagBits)d[2] };
		depth.loadOp = (VkAttachmentLoadOp)d[3];
		depth.storeOp = (VkAttachmentStoreOp)d[4];
		depth.stencilLoadOp = (VkAttachmentLoadOp)d[5];
		depth.stencilStoreOp = (VkAttachmentStoreOp)d[6];
		depth.initialLayout = layout;
		depth.finalLayout = layout;
		depthRef = (VkAttachmentReference){ count, layout };
		attachments[count++] = depth;
	}
	VkSubpassDescription subpass = { .pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS };
	subpass.colorAttachmentCount = colors;
	subpass.pColorAttachments = colorRefs;
	subpass.pResolveAttachments = resolves != 0 ? resolveRefs : NULL;
	subpass.pDepthStencilAttachment = d[0] != 0 ? &depthRef : NULL;
	VkRenderPassCreateInfo info = { .sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO };
	info.attachmentCount = count;
	info.pAttachments = attachments;
	info.subpassCount = 1;
	info.pSubpasses = &subpass;

	VkRenderPass fresh = VK_NULL_HANDLE;
	VkResult result = vkd.vkCreateRenderPass(s_vk.device, &info, NULL, &fresh);
	if (result != VK_SUCCESS) return failCall("vkCreateRenderPass", result);
	*renderPass = HANDLE_OUT(fresh);
	return VULKAN_OK;
}

void vulkanRenderPassDestroy(uint64_t renderPass) {
	vkd.vkDestroyRenderPass(s_vk.device, HANDLE_IN(VkRenderPass, renderPass), NULL);
}

static VkClearValue colorClear(VkFormat format, const float *rgba) {
	VkClearValue value;
	switch (format) {
	case VK_FORMAT_R8G8B8A8_UINT:
	case VK_FORMAT_R16G16B16A16_UINT:
	case VK_FORMAT_R32_UINT:
	case VK_FORMAT_R32G32B32A32_UINT:
		for (int i = 0; i < 4; i++) value.color.uint32[i] = (uint32_t)rgba[i];
		break;
	case VK_FORMAT_R8G8B8A8_SINT:
	case VK_FORMAT_R16G16B16A16_SINT:
	case VK_FORMAT_R32_SINT:
	case VK_FORMAT_R32G32B32A32_SINT:
		for (int i = 0; i < 4; i++) value.color.int32[i] = (int32_t)rgba[i];
		break;
	default:
		for (int i = 0; i < 4; i++) value.color.float32[i] = rgba[i];
		break;
	}
	return value;
}

static int32_t framebufferKeep(VkFramebuffer framebuffer) {
	if (s_framebufferCount == s_framebufferCapacity) {
		uint32_t capacity = s_framebufferCapacity > 0 ? s_framebufferCapacity * 2 : 16;
		VkFramebuffer *grown = realloc(s_framebuffers, sizeof *grown * capacity);
		if (grown == NULL) return fail(VULKAN_OUT_OF_MEMORY, "out of memory growing the framebuffer list to %u", capacity);
		s_framebuffers = grown;
		s_framebufferCapacity = capacity;
	}
	s_framebuffers[s_framebufferCount++] = framebuffer;
	return VULKAN_OK;
}

static void framebuffersDestroy(VkFramebuffer *framebuffers, uint32_t count) {
	for (uint32_t i = 0; i < count; i++) vkd.vkDestroyFramebuffer(s_vk.device, framebuffers[i], NULL);
}

int32_t vulkanPassBegin(
	uint64_t renderPass,
	const uint32_t *key,
	uint32_t words,
	const uint64_t *views,
	uint32_t viewCount,
	uint32_t width,
	uint32_t height,
	const float *clears,
	uint32_t clearCount) {
	if (s_passOpen) return fail(VULKAN_ERROR_ORDER, "vulkanPassBegin inside a render pass");
	if (s_imageBarrierCount != 0) {
		return fail(VULKAN_ERROR_ORDER, "vulkanPassBegin with %u image barriers never flushed", s_imageBarrierCount);
	}
	int32_t valid = keyValid("vulkanPassBegin", key, words);
	if (valid != VULKAN_OK) return valid;
	if (width == 0 || height == 0) return fail(VULKAN_ERROR_ORDER, "vulkanPassBegin with a %ux%u render area", width, height);
	uint32_t colors = key[0];
	const uint32_t *depth = key + 1 + colors * COLOR_KEY_WORDS;
	uint32_t attachmentCount = depth[0] != 0 ? 1 : 0;
	for (uint32_t i = 0; i < colors; i++) {
		const uint32_t *c = key + 1 + i * COLOR_KEY_WORDS;
		if (c[0] != VK_FORMAT_UNDEFINED) attachmentCount++;
		if (c[0] != VK_FORMAT_UNDEFINED && c[4] != VK_FORMAT_UNDEFINED) attachmentCount++;
	}
	uint32_t clearWords = colors * 4 + (depth[0] != 0 ? 2 : 0);
	if (viewCount != attachmentCount || clearCount != clearWords) {
		return fail(VULKAN_ERROR_ORDER, "vulkanPassBegin: the render pass takes %u views and %u clear words, given %u and %u",
			attachmentCount, clearWords, viewCount, clearCount);
	}
	VkImageView attachments[MAX_PASS_ATTACHMENTS];
	for (uint32_t i = 0; i < viewCount; i++) attachments[i] = HANDLE_IN(VkImageView, views[i]);
	VkClearValue values[MAX_PASS_ATTACHMENTS];
	uint32_t valueCount = 0;
	for (uint32_t i = 0; i < colors; i++) {
		const uint32_t *c = key + 1 + i * COLOR_KEY_WORDS;
		if (c[0] == VK_FORMAT_UNDEFINED) continue;
		values[valueCount++] = colorClear((VkFormat)c[0], clears + i * 4);
		if (c[4] != VK_FORMAT_UNDEFINED) values[valueCount++] = colorClear((VkFormat)c[4], (const float[4]){ 0, 0, 0, 0 });
	}
	if (depth[0] != 0) {
		values[valueCount].depthStencil.depth = clears[colors * 4];
		values[valueCount].depthStencil.stencil = (uint32_t)clears[colors * 4 + 1];
		valueCount++;
	}
	VkCommandBuffer commands = NULL;
	int32_t status = recording("vulkanPassBegin", &commands);
	if (status != VULKAN_OK) return status;

	VkFramebufferCreateInfo framebufferInfo = { .sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO };
	framebufferInfo.renderPass = HANDLE_IN(VkRenderPass, renderPass);
	framebufferInfo.attachmentCount = viewCount;
	framebufferInfo.pAttachments = attachments;
	framebufferInfo.width = width;
	framebufferInfo.height = height;
	framebufferInfo.layers = 1;
	VkFramebuffer framebuffer = VK_NULL_HANDLE;
	VkResult result = vkd.vkCreateFramebuffer(s_vk.device, &framebufferInfo, NULL, &framebuffer);
	if (result != VK_SUCCESS) return failCall("vkCreateFramebuffer", result);
	status = framebufferKeep(framebuffer);
	if (status != VULKAN_OK) {
		vkd.vkDestroyFramebuffer(s_vk.device, framebuffer, NULL);
		return status;
	}

	VkRect2D area = { .offset = { 0, 0 }, .extent = { width, height } };
	VkRenderPassBeginInfo begin = { .sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO };
	begin.renderPass = HANDLE_IN(VkRenderPass, renderPass);
	begin.framebuffer = framebuffer;
	begin.renderArea = area;
	begin.clearValueCount = valueCount;
	begin.pClearValues = values;
	vkd.vkCmdBeginRenderPass(commands, &begin, VK_SUBPASS_CONTENTS_INLINE);
	VkViewport viewport = { .x = 0, .y = (float)height, .width = (float)width, .height = -(float)height };
	viewport.minDepth = 0.0f;
	viewport.maxDepth = 1.0f;
	vkd.vkCmdSetViewport(commands, 0, 1, &viewport);
	vkd.vkCmdSetScissor(commands, 0, 1, &area);
	vkd.vkCmdSetStencilReference(commands, VK_STENCIL_FACE_FRONT_AND_BACK, 0);
	vkd.vkCmdSetBlendConstants(commands, (const float[4]){ 0, 0, 0, 0 });
	s_passOpen = 1;
	return VULKAN_OK;
}

int32_t vulkanPassEnd(void) {
	if (!s_passOpen) return fail(VULKAN_ERROR_ORDER, "vulkanPassEnd without a render pass");
	vkd.vkCmdEndRenderPass(s_recording);
	s_passOpen = 0;
	return VULKAN_OK;
}

#define SPIRV_MAGIC 0x07230203u
#define SET_LAYOUT_ENTRY_WORDS 3
#define SET_WRITE_WORDS 3
#define MAX_SET_BINDINGS 32
#define MAX_PIPELINE_SETS 4
#define MAX_POOL_SIZES 11
#define MAX_POOL_SETS 512
#define VERTEX_BUFFER_WORDS 3
#define VERTEX_ATTRIBUTE_WORDS 4
#define MAX_VERTEX_BUFFERS 8
#define MAX_VERTEX_ATTRIBUTES 16
#define COLOR_TARGET_WORDS 8
#define RENDER_STATE_WORDS 20

static VkDescriptorSet s_poolSets[MAX_POOL_SETS];
static uint32_t s_poolSetCount;

int32_t vulkanShaderModuleCreate(const uint8_t *code, uint64_t bytes, uint64_t *module) {
	*module = 0;
	if (deviceReady("vulkanShaderModuleCreate") != VULKAN_OK) return VULKAN_ERROR_ORDER;
	if (bytes < 20 || bytes % 4 != 0) {
		return fail(VULKAN_ERROR_ORDER, "vulkanShaderModuleCreate: %llu bytes are not a SPIR-V module of whole words with its header",
			(unsigned long long)bytes);
	}
	uint32_t magic;
	memcpy(&magic, code, sizeof magic);
	if (magic != SPIRV_MAGIC) return fail(VULKAN_ERROR_ORDER, "vulkanShaderModuleCreate: the code starts with 0x%08x, not the SPIR-V magic number", magic);
	const uint32_t *words = (const uint32_t *)(const void *)code;
	uint32_t *copy = NULL;
	if (((uintptr_t)code & 3) != 0) {
		copy = malloc((size_t)bytes);
		if (copy == NULL) return fail(VULKAN_OUT_OF_MEMORY, "out of memory aligning %llu bytes of SPIR-V", (unsigned long long)bytes);
		memcpy(copy, code, (size_t)bytes);
		words = copy;
	}
	VkShaderModuleCreateInfo info = { .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO };
	info.codeSize = (size_t)bytes;
	info.pCode = words;
	VkShaderModule fresh = VK_NULL_HANDLE;
	VkResult result = vkd.vkCreateShaderModule(s_vk.device, &info, NULL, &fresh);
	free(copy);
	if (result != VK_SUCCESS) return failCall("vkCreateShaderModule", result);
	*module = HANDLE_OUT(fresh);
	return VULKAN_OK;
}

void vulkanShaderModuleDestroy(uint64_t module) {
	vkd.vkDestroyShaderModule(s_vk.device, HANDLE_IN(VkShaderModule, module), NULL);
}

int32_t vulkanSetLayoutCreate(const uint32_t *entries, uint32_t count, uint64_t *layout) {
	*layout = 0;
	if (deviceReady("vulkanSetLayoutCreate") != VULKAN_OK) return VULKAN_ERROR_ORDER;
	if (count > MAX_SET_BINDINGS) return fail(VULKAN_ERROR_ORDER, "vulkanSetLayoutCreate: %u bindings are over %u", count, MAX_SET_BINDINGS);
	VkDescriptorSetLayoutBinding bindings[MAX_SET_BINDINGS];
	for (uint32_t i = 0; i < count; i++) {
		const uint32_t *e = entries + i * SET_LAYOUT_ENTRY_WORDS;
		bindings[i] = (VkDescriptorSetLayoutBinding){ .binding = e[0], .descriptorType = (VkDescriptorType)e[1] };
		bindings[i].descriptorCount = 1;
		bindings[i].stageFlags = e[2];
	}
	VkDescriptorSetLayoutCreateInfo info = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO };
	info.bindingCount = count;
	info.pBindings = count != 0 ? bindings : NULL;
	VkDescriptorSetLayout fresh = VK_NULL_HANDLE;
	VkResult result = vkd.vkCreateDescriptorSetLayout(s_vk.device, &info, NULL, &fresh);
	if (result != VK_SUCCESS) return failCall("vkCreateDescriptorSetLayout", result);
	*layout = HANDLE_OUT(fresh);
	return VULKAN_OK;
}

void vulkanSetLayoutDestroy(uint64_t layout) {
	vkd.vkDestroyDescriptorSetLayout(s_vk.device, HANDLE_IN(VkDescriptorSetLayout, layout), NULL);
}

int32_t vulkanPipelineLayoutCreate(const uint64_t *setLayouts, uint32_t count, uint64_t *layout) {
	*layout = 0;
	if (deviceReady("vulkanPipelineLayoutCreate") != VULKAN_OK) return VULKAN_ERROR_ORDER;
	if (count > MAX_PIPELINE_SETS) return fail(VULKAN_ERROR_ORDER, "vulkanPipelineLayoutCreate: %u sets are over %u", count, MAX_PIPELINE_SETS);
	VkDescriptorSetLayout sets[MAX_PIPELINE_SETS];
	for (uint32_t i = 0; i < count; i++) sets[i] = HANDLE_IN(VkDescriptorSetLayout, setLayouts[i]);
	VkPipelineLayoutCreateInfo info = { .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO };
	info.setLayoutCount = count;
	info.pSetLayouts = count != 0 ? sets : NULL;
	VkPipelineLayout fresh = VK_NULL_HANDLE;
	VkResult result = vkd.vkCreatePipelineLayout(s_vk.device, &info, NULL, &fresh);
	if (result != VK_SUCCESS) return failCall("vkCreatePipelineLayout", result);
	*layout = HANDLE_OUT(fresh);
	return VULKAN_OK;
}

void vulkanPipelineLayoutDestroy(uint64_t layout) {
	vkd.vkDestroyPipelineLayout(s_vk.device, HANDLE_IN(VkPipelineLayout, layout), NULL);
}

int32_t vulkanDescriptorPoolCreate(const uint32_t *sizes, uint32_t sizeCount, uint32_t maxSets, uint64_t setLayout, uint64_t *pool) {
	*pool = 0;
	s_poolSetCount = 0;
	if (deviceReady("vulkanDescriptorPoolCreate") != VULKAN_OK) return VULKAN_ERROR_ORDER;
	if (sizeCount > MAX_POOL_SIZES || maxSets == 0 || maxSets > MAX_POOL_SETS) {
		return fail(VULKAN_ERROR_ORDER, "vulkanDescriptorPoolCreate: %u pool sizes and %u sets are outside 0..%u and 1..%u",
			sizeCount, maxSets, MAX_POOL_SIZES, MAX_POOL_SETS);
	}
	VkDescriptorPoolSize poolSizes[MAX_POOL_SIZES];
	for (uint32_t i = 0; i < sizeCount; i++) {
		poolSizes[i] = (VkDescriptorPoolSize){ (VkDescriptorType)sizes[i * 2], sizes[i * 2 + 1] };
	}
	VkDescriptorPoolCreateInfo info = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO };
	info.maxSets = maxSets;
	info.poolSizeCount = sizeCount;
	info.pPoolSizes = sizeCount != 0 ? poolSizes : NULL;
	VkDescriptorPool fresh = VK_NULL_HANDLE;
	VkResult result = vkd.vkCreateDescriptorPool(s_vk.device, &info, NULL, &fresh);
	if (result != VK_SUCCESS) return failCall("vkCreateDescriptorPool", result);
	VkDescriptorSetLayout layouts[MAX_POOL_SETS];
	for (uint32_t i = 0; i < maxSets; i++) layouts[i] = HANDLE_IN(VkDescriptorSetLayout, setLayout);
	VkDescriptorSetAllocateInfo allocate = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO };
	allocate.descriptorPool = fresh;
	allocate.descriptorSetCount = maxSets;
	allocate.pSetLayouts = layouts;
	result = vkd.vkAllocateDescriptorSets(s_vk.device, &allocate, s_poolSets);
	if (result != VK_SUCCESS) {
		vkd.vkDestroyDescriptorPool(s_vk.device, fresh, NULL);
		return failCall("vkAllocateDescriptorSets", result);
	}
	s_poolSetCount = maxSets;
	*pool = HANDLE_OUT(fresh);
	return VULKAN_OK;
}

uint64_t vulkanDescriptorPoolSet(uint32_t index) {
	return index < s_poolSetCount ? HANDLE_OUT(s_poolSets[index]) : 0;
}

void vulkanDescriptorPoolDestroy(uint64_t pool) {
	vkd.vkDestroyDescriptorPool(s_vk.device, HANDLE_IN(VkDescriptorPool, pool), NULL);
}

static int32_t isBufferDescriptor(VkDescriptorType type) {
	return type == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER || type == VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC
		|| type == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER || type == VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC;
}

int32_t vulkanDescriptorSetWrite(
	uint64_t set,
	const uint32_t *words,
	const uint64_t *handles,
	const uint64_t *offsets,
	const uint64_t *ranges,
	uint32_t count) {
	if (deviceReady("vulkanDescriptorSetWrite") != VULKAN_OK) return VULKAN_ERROR_ORDER;
	if (count > MAX_SET_BINDINGS) return fail(VULKAN_ERROR_ORDER, "vulkanDescriptorSetWrite: %u entries are over %u", count, MAX_SET_BINDINGS);
	VkWriteDescriptorSet writes[MAX_SET_BINDINGS];
	VkDescriptorBufferInfo buffers[MAX_SET_BINDINGS];
	VkDescriptorImageInfo images[MAX_SET_BINDINGS];
	for (uint32_t i = 0; i < count; i++) {
		const uint32_t *w = words + i * SET_WRITE_WORDS;
		VkDescriptorType type = (VkDescriptorType)w[1];
		writes[i] = (VkWriteDescriptorSet){ .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET };
		writes[i].dstSet = HANDLE_IN(VkDescriptorSet, set);
		writes[i].dstBinding = w[0];
		writes[i].descriptorCount = 1;
		writes[i].descriptorType = type;
		if (isBufferDescriptor(type)) {
			buffers[i] = (VkDescriptorBufferInfo){ HANDLE_IN(VkBuffer, handles[i]), offsets[i], ranges[i] };
			writes[i].pBufferInfo = &buffers[i];
		} else if (type == VK_DESCRIPTOR_TYPE_SAMPLER) {
			images[i] = (VkDescriptorImageInfo){ .sampler = HANDLE_IN(VkSampler, handles[i]) };
			writes[i].pImageInfo = &images[i];
		} else if (type == VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE || type == VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) {
			images[i] = (VkDescriptorImageInfo){ .imageView = HANDLE_IN(VkImageView, handles[i]), .imageLayout = (VkImageLayout)w[2] };
			writes[i].pImageInfo = &images[i];
		} else {
			return fail(VULKAN_ERROR_ORDER, "vulkanDescriptorSetWrite: binding %u has descriptor type %u, which Void does not write", w[0], w[1]);
		}
	}
	vkd.vkUpdateDescriptorSets(s_vk.device, count, writes, 0, NULL);
	return VULKAN_OK;
}

static VkPipelineShaderStageCreateInfo shaderStage(VkShaderStageFlagBits stage, uint64_t module, const char *entry) {
	VkPipelineShaderStageCreateInfo info = { .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO };
	info.stage = stage;
	info.module = HANDLE_IN(VkShaderModule, module);
	info.pName = entry;
	return info;
}

static VkStencilOpState stencilFace(const uint32_t *face, uint32_t readMask, uint32_t writeMask) {
	VkStencilOpState state = { .failOp = (VkStencilOp)face[0], .passOp = (VkStencilOp)face[1] };
	state.depthFailOp = (VkStencilOp)face[2];
	state.compareOp = (VkCompareOp)face[3];
	state.compareMask = readMask;
	state.writeMask = writeMask;
	state.reference = 0;
	return state;
}

int32_t vulkanRenderPipelineCreate(
	uint64_t layout,
	uint64_t renderPass,
	uint64_t vertexModule,
	const char *vertexEntry,
	uint64_t fragmentModule,
	const char *fragmentEntry,
	const uint32_t *state,
	const uint32_t *vertex,
	uint32_t bufferCount,
	uint32_t attributeCount,
	const uint32_t *targets,
	uint32_t targetCount,
	float depthBiasSlope,
	float depthBiasClamp,
	uint64_t *pipeline) {
	*pipeline = 0;
	if (deviceReady("vulkanRenderPipelineCreate") != VULKAN_OK) return VULKAN_ERROR_ORDER;
	if (bufferCount > MAX_VERTEX_BUFFERS || attributeCount > MAX_VERTEX_ATTRIBUTES || targetCount > MAX_COLOR_ATTACHMENTS) {
		return fail(VULKAN_ERROR_ORDER, "vulkanRenderPipelineCreate: %u vertex buffers, %u attributes and %u color targets are over %u, %u and %u",
			bufferCount, attributeCount, targetCount, MAX_VERTEX_BUFFERS, MAX_VERTEX_ATTRIBUTES, MAX_COLOR_ATTACHMENTS);
	}
	if (!validSamples(state[4])) return fail(VULKAN_ERROR_ORDER, "vulkanRenderPipelineCreate: %u samples", state[4]);
	VkPipelineShaderStageCreateInfo stages[2];
	uint32_t stageCount = 0;
	stages[stageCount++] = shaderStage(VK_SHADER_STAGE_VERTEX_BIT, vertexModule, vertexEntry);
	if (fragmentModule != 0) stages[stageCount++] = shaderStage(VK_SHADER_STAGE_FRAGMENT_BIT, fragmentModule, fragmentEntry);

	VkVertexInputBindingDescription bindings[MAX_VERTEX_BUFFERS];
	for (uint32_t i = 0; i < bufferCount; i++) {
		const uint32_t *b = vertex + i * VERTEX_BUFFER_WORDS;
		bindings[i] = (VkVertexInputBindingDescription){ b[0], b[1], (VkVertexInputRate)b[2] };
	}
	VkVertexInputAttributeDescription attributes[MAX_VERTEX_ATTRIBUTES];
	const uint32_t *attributeWords = vertex + bufferCount * VERTEX_BUFFER_WORDS;
	for (uint32_t i = 0; i < attributeCount; i++) {
		const uint32_t *a = attributeWords + i * VERTEX_ATTRIBUTE_WORDS;
		attributes[i] = (VkVertexInputAttributeDescription){ a[0], a[1], (VkFormat)a[2], a[3] };
	}
	VkPipelineVertexInputStateCreateInfo vertexInput = { .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO };
	vertexInput.vertexBindingDescriptionCount = bufferCount;
	vertexInput.pVertexBindingDescriptions = bufferCount != 0 ? bindings : NULL;
	vertexInput.vertexAttributeDescriptionCount = attributeCount;
	vertexInput.pVertexAttributeDescriptions = attributeCount != 0 ? attributes : NULL;

	VkPipelineInputAssemblyStateCreateInfo inputAssembly = { .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO };
	inputAssembly.topology = (VkPrimitiveTopology)state[0];
	inputAssembly.primitiveRestartEnable = state[1] ? VK_TRUE : VK_FALSE;

	VkPipelineViewportStateCreateInfo viewport = { .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO };
	viewport.viewportCount = 1;
	viewport.scissorCount = 1;

	float depthBias = (float)(int32_t)state[19];
	VkPipelineRasterizationStateCreateInfo rasterization = { .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO };
	rasterization.polygonMode = VK_POLYGON_MODE_FILL;
	rasterization.cullMode = state[2];
	rasterization.frontFace = (VkFrontFace)state[3];
	rasterization.depthBiasEnable = depthBias != 0.0f || depthBiasSlope != 0.0f ? VK_TRUE : VK_FALSE;
	rasterization.depthBiasConstantFactor = depthBias;
	rasterization.depthBiasClamp = depthBiasClamp;
	rasterization.depthBiasSlopeFactor = depthBiasSlope;
	rasterization.lineWidth = 1.0f;

	VkSampleMask sampleMask = 0xFFFFFFFFu;
	VkPipelineMultisampleStateCreateInfo multisample = { .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO };
	multisample.rasterizationSamples = (VkSampleCountFlagBits)state[4];
	multisample.minSampleShading = 1.0f;
	multisample.pSampleMask = &sampleMask;

	VkPipelineDepthStencilStateCreateInfo depthStencil = { .sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO };
	depthStencil.depthTestEnable = state[5] ? VK_TRUE : VK_FALSE;
	depthStencil.depthWriteEnable = state[6] ? VK_TRUE : VK_FALSE;
	depthStencil.depthCompareOp = (VkCompareOp)state[7];
	depthStencil.stencilTestEnable = state[8] ? VK_TRUE : VK_FALSE;
	depthStencil.front = stencilFace(state + 9, state[17], state[18]);
	depthStencil.back = stencilFace(state + 13, state[17], state[18]);
	depthStencil.minDepthBounds = 0.0f;
	depthStencil.maxDepthBounds = 1.0f;

	VkPipelineColorBlendAttachmentState blends[MAX_COLOR_ATTACHMENTS];
	for (uint32_t i = 0; i < targetCount; i++) {
		const uint32_t *t = targets + i * COLOR_TARGET_WORDS;
		blends[i] = (VkPipelineColorBlendAttachmentState){ .blendEnable = t[0] ? VK_TRUE : VK_FALSE };
		blends[i].srcColorBlendFactor = (VkBlendFactor)t[1];
		blends[i].dstColorBlendFactor = (VkBlendFactor)t[2];
		blends[i].colorBlendOp = (VkBlendOp)t[3];
		blends[i].srcAlphaBlendFactor = (VkBlendFactor)t[4];
		blends[i].dstAlphaBlendFactor = (VkBlendFactor)t[5];
		blends[i].alphaBlendOp = (VkBlendOp)t[6];
		blends[i].colorWriteMask = t[7];
	}
	VkPipelineColorBlendStateCreateInfo colorBlend = { .sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO };
	colorBlend.attachmentCount = targetCount;
	colorBlend.pAttachments = targetCount != 0 ? blends : NULL;

	VkDynamicState dynamicStates[] = {
		VK_DYNAMIC_STATE_VIEWPORT,
		VK_DYNAMIC_STATE_SCISSOR,
		VK_DYNAMIC_STATE_BLEND_CONSTANTS,
		VK_DYNAMIC_STATE_STENCIL_REFERENCE,
	};
	VkPipelineDynamicStateCreateInfo dynamic = { .sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO };
	dynamic.dynamicStateCount = sizeof dynamicStates / sizeof dynamicStates[0];
	dynamic.pDynamicStates = dynamicStates;

	VkGraphicsPipelineCreateInfo info = { .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO };
	info.stageCount = stageCount;
	info.pStages = stages;
	info.pVertexInputState = &vertexInput;
	info.pInputAssemblyState = &inputAssembly;
	info.pViewportState = &viewport;
	info.pRasterizationState = &rasterization;
	info.pMultisampleState = &multisample;
	info.pDepthStencilState = &depthStencil;
	info.pColorBlendState = &colorBlend;
	info.pDynamicState = &dynamic;
	info.layout = HANDLE_IN(VkPipelineLayout, layout);
	info.renderPass = HANDLE_IN(VkRenderPass, renderPass);
	info.subpass = 0;
	info.basePipelineIndex = -1;
	VkPipeline fresh = VK_NULL_HANDLE;
	VkResult result = vkd.vkCreateGraphicsPipelines(s_vk.device, VK_NULL_HANDLE, 1, &info, NULL, &fresh);
	if (result != VK_SUCCESS) return failCall("vkCreateGraphicsPipelines", result);
	*pipeline = HANDLE_OUT(fresh);
	return VULKAN_OK;
}

int32_t vulkanComputePipelineCreate(uint64_t layout, uint64_t module, const char *entry, uint64_t *pipeline) {
	*pipeline = 0;
	if (deviceReady("vulkanComputePipelineCreate") != VULKAN_OK) return VULKAN_ERROR_ORDER;
	VkComputePipelineCreateInfo info = { .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO };
	info.stage = shaderStage(VK_SHADER_STAGE_COMPUTE_BIT, module, entry);
	info.layout = HANDLE_IN(VkPipelineLayout, layout);
	info.basePipelineIndex = -1;
	VkPipeline fresh = VK_NULL_HANDLE;
	VkResult result = vkd.vkCreateComputePipelines(s_vk.device, VK_NULL_HANDLE, 1, &info, NULL, &fresh);
	if (result != VK_SUCCESS) return failCall("vkCreateComputePipelines", result);
	*pipeline = HANDLE_OUT(fresh);
	return VULKAN_OK;
}

void vulkanPipelineDestroy(uint64_t pipeline) {
	vkd.vkDestroyPipeline(s_vk.device, HANDLE_IN(VkPipeline, pipeline), NULL);
}

static int32_t inPass(const char *caller) {
	if (!s_passOpen) return fail(VULKAN_ERROR_ORDER, "%s outside a render pass", caller);
	return VULKAN_OK;
}

static int32_t commandsFor(int32_t compute, const char *caller, VkCommandBuffer *commands) {
	if (compute) return recording(caller, commands);
	*commands = s_recording;
	return inPass(caller);
}

int32_t vulkanCmdBindPipeline(int32_t compute, uint64_t pipeline) {
	VkCommandBuffer commands = NULL;
	int32_t status = commandsFor(compute, "vulkanCmdBindPipeline", &commands);
	if (status != VULKAN_OK) return status;
	vkd.vkCmdBindPipeline(commands, compute ? VK_PIPELINE_BIND_POINT_COMPUTE : VK_PIPELINE_BIND_POINT_GRAPHICS,
		HANDLE_IN(VkPipeline, pipeline));
	return VULKAN_OK;
}

int32_t vulkanCmdBindSet(int32_t compute, uint64_t layout, uint32_t index, uint64_t set, const uint32_t *offsets, uint32_t offsetCount) {
	VkCommandBuffer commands = NULL;
	int32_t status = commandsFor(compute, "vulkanCmdBindSet", &commands);
	if (status != VULKAN_OK) return status;
	VkDescriptorSet bound = HANDLE_IN(VkDescriptorSet, set);
	vkd.vkCmdBindDescriptorSets(commands, compute ? VK_PIPELINE_BIND_POINT_COMPUTE : VK_PIPELINE_BIND_POINT_GRAPHICS,
		HANDLE_IN(VkPipelineLayout, layout), index, 1, &bound, offsetCount, offsetCount != 0 ? offsets : NULL);
	return VULKAN_OK;
}

int32_t vulkanCmdBindVertexBuffer(uint32_t slot, uint64_t buffer, uint64_t offset) {
	int32_t status = inPass("vulkanCmdBindVertexBuffer");
	if (status != VULKAN_OK) return status;
	VkBuffer bound = HANDLE_IN(VkBuffer, buffer);
	VkDeviceSize at = offset;
	vkd.vkCmdBindVertexBuffers(s_recording, slot, 1, &bound, &at);
	return VULKAN_OK;
}

int32_t vulkanCmdBindIndexBuffer(uint64_t buffer, uint64_t offset, int32_t indexType) {
	int32_t status = inPass("vulkanCmdBindIndexBuffer");
	if (status != VULKAN_OK) return status;
	vkd.vkCmdBindIndexBuffer(s_recording, HANDLE_IN(VkBuffer, buffer), offset, (VkIndexType)indexType);
	return VULKAN_OK;
}

int32_t vulkanCmdViewport(float x, float y, float width, float height, float minDepth, float maxDepth) {
	int32_t status = inPass("vulkanCmdViewport");
	if (status != VULKAN_OK) return status;
	VkViewport viewport = { .x = x, .y = y + height, .width = width, .height = -height };
	viewport.minDepth = minDepth;
	viewport.maxDepth = maxDepth;
	if (width == 0.0f) {
		viewport.x = 0.0f;
		viewport.width = 1.0f;
		viewport.height = 0.0f;
	}
	vkd.vkCmdSetViewport(s_recording, 0, 1, &viewport);
	return VULKAN_OK;
}

int32_t vulkanCmdScissor(int32_t x, int32_t y, uint32_t width, uint32_t height) {
	int32_t status = inPass("vulkanCmdScissor");
	if (status != VULKAN_OK) return status;
	VkRect2D rect = { .offset = { x, y }, .extent = { width, height } };
	vkd.vkCmdSetScissor(s_recording, 0, 1, &rect);
	return VULKAN_OK;
}

int32_t vulkanCmdBlendConstants(float r, float g, float b, float a) {
	int32_t status = inPass("vulkanCmdBlendConstants");
	if (status != VULKAN_OK) return status;
	vkd.vkCmdSetBlendConstants(s_recording, (const float[4]){ r, g, b, a });
	return VULKAN_OK;
}

int32_t vulkanCmdStencilReference(uint32_t reference) {
	int32_t status = inPass("vulkanCmdStencilReference");
	if (status != VULKAN_OK) return status;
	vkd.vkCmdSetStencilReference(s_recording, VK_STENCIL_FACE_FRONT_AND_BACK, reference);
	return VULKAN_OK;
}

int32_t vulkanCmdDraw(uint32_t vertexCount, uint32_t instanceCount, uint32_t firstVertex, uint32_t firstInstance) {
	int32_t status = inPass("vulkanCmdDraw");
	if (status != VULKAN_OK) return status;
	vkd.vkCmdDraw(s_recording, vertexCount, instanceCount, firstVertex, firstInstance);
	return VULKAN_OK;
}

int32_t vulkanCmdDrawIndexed(uint32_t indexCount, uint32_t instanceCount, uint32_t firstIndex, int32_t baseVertex, uint32_t firstInstance) {
	int32_t status = inPass("vulkanCmdDrawIndexed");
	if (status != VULKAN_OK) return status;
	vkd.vkCmdDrawIndexed(s_recording, indexCount, instanceCount, firstIndex, baseVertex, firstInstance);
	return VULKAN_OK;
}

int32_t vulkanCmdDrawIndirect(uint64_t buffer, uint64_t offset, int32_t indexed) {
	int32_t status = inPass("vulkanCmdDrawIndirect");
	if (status != VULKAN_OK) return status;
	if (indexed) {
		vkd.vkCmdDrawIndexedIndirect(s_recording, HANDLE_IN(VkBuffer, buffer), offset, 1, 0);
	} else {
		vkd.vkCmdDrawIndirect(s_recording, HANDLE_IN(VkBuffer, buffer), offset, 1, 0);
	}
	return VULKAN_OK;
}

int32_t vulkanCmdDispatch(uint32_t x, uint32_t y, uint32_t z) {
	VkCommandBuffer commands = NULL;
	int32_t status = recording("vulkanCmdDispatch", &commands);
	if (status != VULKAN_OK) return status;
	vkd.vkCmdDispatch(commands, x, y, z);
	return VULKAN_OK;
}

int32_t vulkanCmdDispatchIndirect(uint64_t buffer, uint64_t offset) {
	VkCommandBuffer commands = NULL;
	int32_t status = recording("vulkanCmdDispatchIndirect", &commands);
	if (status != VULKAN_OK) return status;
	vkd.vkCmdDispatchIndirect(commands, HANDLE_IN(VkBuffer, buffer), offset);
	return VULKAN_OK;
}

static void retireSubmissions(uint32_t count);

static int32_t waitThrough(uint64_t serial) {
	if (serial <= s_completed) return VULKAN_OK;
	uint32_t count = 0;
	while (count < s_submissionCount && s_submissions[count].serial <= serial) count++;
	if (count == 0) return VULKAN_OK;
	VkFence *fences = malloc(sizeof *fences * count);
	if (fences == NULL) return fail(VULKAN_OUT_OF_MEMORY, "out of memory waiting on %u submissions", count);
	for (uint32_t i = 0; i < count; i++) fences[i] = s_submissions[i].fence;
	VkResult result = vkd.vkWaitForFences(s_vk.device, count, fences, VK_TRUE, UINT64_MAX);
	free(fences);
	if (result != VK_SUCCESS) return failCall("vkWaitForFences", result);
	retireSubmissions(count);
	return VULKAN_OK;
}

static int32_t idle(void) {
	VkResult result = vkd.vkDeviceWaitIdle(s_vk.device);
	if (result != VK_SUCCESS) return failCall("vkDeviceWaitIdle", result);
	return waitThrough(s_submitted);
}

static void swapImagesRelease(void) {
	for (uint32_t i = 0; i < s_swap.imageCount; i++) {
		VulkanSwapImage *image = &s_swap.images[i];
		if (image->view != VK_NULL_HANDLE) vkd.vkDestroyImageView(s_vk.device, image->view, NULL);
		if (image->presentReady != VK_NULL_HANDLE) vkd.vkDestroySemaphore(s_vk.device, image->presentReady, NULL);
	}
	free(s_swap.images);
	s_swap.images = NULL;
	s_swap.imageCount = 0;
	s_swap.acquired = -1;
	s_swap.presentPending = 0;
}

static int32_t swapImageMake(VulkanSwapImage *slot, VkImage image, VkFormat format) {
	slot->image = image;
	int32_t status = viewMake(image, VK_IMAGE_VIEW_TYPE_2D, format, VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1, &slot->view);
	if (status != VULKAN_OK) return status;
	VkSemaphoreCreateInfo semaphore = { .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
	VkResult result = vkd.vkCreateSemaphore(s_vk.device, &semaphore, NULL, &slot->presentReady);
	if (result != VK_SUCCESS) {
		slot->presentReady = VK_NULL_HANDLE;
		return failCall("vkCreateSemaphore", result);
	}
	return VULKAN_OK;
}

static int32_t swapchainImagesTake(VkFormat format) {
	uint32_t count = 0;
	VkResult result = vkd.vkGetSwapchainImagesKHR(s_vk.device, s_swap.swapchain, &count, NULL);
	if (result != VK_SUCCESS) return failCall("vkGetSwapchainImagesKHR", result);
	VkImage *images = malloc(sizeof *images * (count > 0 ? count : 1));
	s_swap.images = calloc(count > 0 ? count : 1, sizeof *s_swap.images);
	if (images == NULL || s_swap.images == NULL) {
		free(images);
		return fail(VULKAN_OUT_OF_MEMORY, "out of memory taking %u swapchain images", count);
	}
	result = vkd.vkGetSwapchainImagesKHR(s_vk.device, s_swap.swapchain, &count, images);
	int32_t status = result == VK_SUCCESS ? VULKAN_OK : failCall("vkGetSwapchainImagesKHR", result);
	for (uint32_t i = 0; i < count && status == VULKAN_OK; i++) {
		s_swap.imageCount = i + 1;
		status = swapImageMake(&s_swap.images[i], images[i], format);
	}
	free(images);
	return status;
}

static void swapchainRelease(void) {
	swapImagesRelease();
	if (s_swap.swapchain != VK_NULL_HANDLE) vkd.vkDestroySwapchainKHR(s_vk.device, s_swap.swapchain, NULL);
	s_swap.swapchain = VK_NULL_HANDLE;
}

int32_t vulkanSwapchainCreate(
	int32_t format,
	uint32_t colorSpace,
	uint32_t width,
	uint32_t height,
	uint32_t minImageCount,
	uint32_t usage,
	uint32_t preTransform,
	uint32_t compositeAlpha,
	uint32_t presentMode) {
	if (deviceReady("vulkanSwapchainCreate") != VULKAN_OK) return VULKAN_ERROR_ORDER;
	if (s_vk.surface == VK_NULL_HANDLE) return fail(VULKAN_ERROR_ORDER, "vulkanSwapchainCreate without a surface");
	if (s_frameAcquired || s_swap.presentPending) {
		return fail(VULKAN_ERROR_ORDER, "vulkanSwapchainCreate while swapchain image %d is acquired", s_swap.acquired);
	}
	int32_t status = idle();
	if (status != VULKAN_OK) return status;
	VkSwapchainKHR old = s_swap.swapchain;
	swapImagesRelease();
	s_swap.swapchain = VK_NULL_HANDLE;

	VkSwapchainCreateInfoKHR info = { .sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR };
	info.surface = s_vk.surface;
	info.minImageCount = minImageCount;
	info.imageFormat = (VkFormat)format;
	info.imageColorSpace = (VkColorSpaceKHR)colorSpace;
	info.imageExtent.width = width;
	info.imageExtent.height = height;
	info.imageArrayLayers = 1;
	info.imageUsage = usage;
	info.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
	info.preTransform = (VkSurfaceTransformFlagBitsKHR)preTransform;
	info.compositeAlpha = (VkCompositeAlphaFlagBitsKHR)compositeAlpha;
	info.presentMode = (VkPresentModeKHR)presentMode;
	info.clipped = VK_FALSE;
	info.oldSwapchain = old;
	VkSwapchainKHR fresh = VK_NULL_HANDLE;
	VkResult result = vkd.vkCreateSwapchainKHR(s_vk.device, &info, NULL, &fresh);
	if (old != VK_NULL_HANDLE) vkd.vkDestroySwapchainKHR(s_vk.device, old, NULL);
	if (result != VK_SUCCESS) return surfaceFailure("vkCreateSwapchainKHR", result);
	s_swap.swapchain = fresh;
	status = swapchainImagesTake((VkFormat)format);
	if (status != VULKAN_OK) swapchainRelease();
	return status;
}

uint32_t vulkanSwapchainImageCount(void) { return s_swap.imageCount; }

uint64_t vulkanSwapchainImage(uint32_t index) {
	if (index >= s_swap.imageCount) {
		fail(VULKAN_ERROR_ORDER, "vulkanSwapchainImage %u is not below the %u swapchain images", index, s_swap.imageCount);
		return 0;
	}
	return HANDLE_OUT(s_swap.images[index].image);
}

uint64_t vulkanSwapchainView(uint32_t index) {
	if (index >= s_swap.imageCount) {
		fail(VULKAN_ERROR_ORDER, "vulkanSwapchainView %u is not below the %u swapchain images", index, s_swap.imageCount);
		return 0;
	}
	return HANDLE_OUT(s_swap.images[index].view);
}

int32_t vulkanSwapchainTarget(void *renderView, uint64_t *image, uint64_t *view) {
	if (sizeof(void *) < sizeof(uint64_t)) {
		return fail(VULKAN_ERROR_ORDER, "NativeSwapchain.renderView cannot carry a VkImageView in a 32-bit build");
	}
	for (uint32_t i = 0; i < s_swap.imageCount; i++) {
		if (HANDLE_OUT(s_swap.images[i].view) == (uint64_t)(uintptr_t)renderView) {
			*image = HANDLE_OUT(s_swap.images[i].image);
			*view = HANDLE_OUT(s_swap.images[i].view);
			return VULKAN_OK;
		}
	}
	return fail(VULKAN_ERROR_ORDER, "NativeSwapchain.renderView %p is not a view of the Vulkan swapchain", renderView);
}

int32_t vulkanSwapchainAcquire(uint32_t *index) {
	if (s_swap.swapchain == VK_NULL_HANDLE) return fail(VULKAN_ERROR_ORDER, "vulkanSwapchainAcquire without a swapchain");
	if (s_frameOpen < 0) return fail(VULKAN_ERROR_ORDER, "vulkanSwapchainAcquire outside a frame");
	if (s_frameAcquired) return fail(VULKAN_ERROR_ORDER, "vulkanSwapchainAcquire twice in one frame");
	if (s_swap.presentPending) {
		return fail(VULKAN_ERROR_ORDER, "vulkanSwapchainAcquire with image %d submitted but not presented", s_swap.acquired);
	}
	uint32_t image = 0;
	VkResult result = vkd.vkAcquireNextImageKHR(
		s_vk.device, s_swap.swapchain, UINT64_MAX, s_frames[s_frameOpen].acquired, VK_NULL_HANDLE, &image);
	switch (result) {
	case VK_SUCCESS:
	case VK_SUBOPTIMAL_KHR:
		s_swap.acquired = (int32_t)image;
		s_frameAcquired = 1;
		*index = image;
		return result == VK_SUCCESS ? VULKAN_OK : VULKAN_SUBOPTIMAL;
	case VK_TIMEOUT:
	case VK_NOT_READY:
	case VK_ERROR_OUT_OF_DATE_KHR:
		return fail(VULKAN_OUT_OF_DATE, "vkAcquireNextImageKHR returned VkResult %d: the swapchain is out of date", (int)result);
	case VK_ERROR_SURFACE_LOST_KHR:
		return fail(VULKAN_SURFACE_LOST, "vkAcquireNextImageKHR: the surface is lost");
	default:
		return failCall("vkAcquireNextImageKHR", result);
	}
}

int32_t vulkanSwapchainPresent(void) {
	if (!s_swap.presentPending) {
		return fail(VULKAN_ERROR_ORDER, "vulkanSwapchainPresent before a frame that acquired an image was submitted");
	}
	uint32_t image = (uint32_t)s_swap.acquired;
	VkSubmitInfo signal = { .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO };
	signal.signalSemaphoreCount = 1;
	signal.pSignalSemaphores = &s_swap.images[image].presentReady;
	VkResult signalled = vkd.vkQueueSubmit(s_vk.queue, 1, &signal, VK_NULL_HANDLE);
	if (signalled != VK_SUCCESS) return failCall("vkQueueSubmit", signalled);
	s_swap.presentPending = 0;
	s_swap.acquired = -1;
	VkPresentInfoKHR info = { .sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR };
	info.waitSemaphoreCount = 1;
	info.pWaitSemaphores = &s_swap.images[image].presentReady;
	info.swapchainCount = 1;
	info.pSwapchains = &s_swap.swapchain;
	info.pImageIndices = &image;
	VkResult result = vkd.vkQueuePresentKHR(s_vk.queue, &info);
	switch (result) {
	case VK_SUCCESS: return VULKAN_OK;
	case VK_SUBOPTIMAL_KHR: return VULKAN_SUBOPTIMAL;
	case VK_ERROR_OUT_OF_DATE_KHR: return fail(VULKAN_OUT_OF_DATE, "vkQueuePresentKHR: the swapchain is out of date");
	case VK_ERROR_SURFACE_LOST_KHR: return fail(VULKAN_SURFACE_LOST, "vkQueuePresentKHR: the surface is lost");
	default: return failCall("vkQueuePresentKHR", result);
	}
}

int32_t vulkanSwapchainDestroy(void) {
	if (s_swap.swapchain == VK_NULL_HANDLE) return fail(VULKAN_ERROR_ORDER, "vulkanSwapchainDestroy without a swapchain");
	if (s_frameAcquired) return fail(VULKAN_ERROR_ORDER, "vulkanSwapchainDestroy inside a frame holding image %d", s_swap.acquired);
	int32_t status = idle();
	swapchainRelease();
	return status;
}

int32_t vulkanSurfaceDestroy(void) {
	if (s_vk.surface == VK_NULL_HANDLE) return fail(VULKAN_ERROR_ORDER, "vulkanSurfaceDestroy without a surface");
	int32_t status = VULKAN_OK;
	if (s_swap.swapchain != VK_NULL_HANDLE) status = vulkanSwapchainDestroy();
	if (status != VULKAN_OK) return status;
	vki.vkDestroySurfaceKHR(s_vk.instance, s_vk.surface, NULL);
	s_vk.surface = VK_NULL_HANDLE;
	s_surfaceInfo.queried = 0;
	return VULKAN_OK;
}

static void framesRelease(void) {
	for (uint32_t i = 0; i < MAX_FRAMES; i++) {
		VulkanFrame *frame = &s_frames[i];
		if (frame->fence != VK_NULL_HANDLE) vkd.vkDestroyFence(s_vk.device, frame->fence, NULL);
		if (frame->acquired != VK_NULL_HANDLE) vkd.vkDestroySemaphore(s_vk.device, frame->acquired, NULL);
		if (frame->pool != VK_NULL_HANDLE) vkd.vkDestroyCommandPool(s_vk.device, frame->pool, NULL);
	}
	memset(s_frames, 0, sizeof s_frames);
	s_frameCount = 0;
	s_frameOpen = -1;
	s_frameAcquired = 0;
}

static int32_t frameMake(VulkanFrame *frame) {
	VkCommandPoolCreateInfo pool = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO };
	pool.queueFamilyIndex = s_vk.queueFamily;
	VkResult result = vkd.vkCreateCommandPool(s_vk.device, &pool, NULL, &frame->pool);
	if (result != VK_SUCCESS) return failCall("vkCreateCommandPool", result);
	VkCommandBufferAllocateInfo commands = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO };
	commands.commandPool = frame->pool;
	commands.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
	commands.commandBufferCount = 1;
	result = vkd.vkAllocateCommandBuffers(s_vk.device, &commands, &frame->commands);
	if (result != VK_SUCCESS) return failCall("vkAllocateCommandBuffers", result);
	VkFenceCreateInfo fence = { .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO };
	result = vkd.vkCreateFence(s_vk.device, &fence, NULL, &frame->fence);
	if (result != VK_SUCCESS) return failCall("vkCreateFence", result);
	VkSemaphoreCreateInfo semaphore = { .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
	result = vkd.vkCreateSemaphore(s_vk.device, &semaphore, NULL, &frame->acquired);
	return result == VK_SUCCESS ? VULKAN_OK : failCall("vkCreateSemaphore", result);
}

int32_t vulkanFramesCreate(uint32_t count) {
	if (deviceReady("vulkanFramesCreate") != VULKAN_OK) return VULKAN_ERROR_ORDER;
	if (s_frameCount != 0) return fail(VULKAN_ERROR_ORDER, "vulkanFramesCreate called twice");
	if (count == 0 || count > MAX_FRAMES) {
		return fail(VULKAN_ERROR_ORDER, "vulkanFramesCreate of %u frames, not between 1 and %u", count, MAX_FRAMES);
	}
	for (uint32_t i = 0; i < count; i++) {
		int32_t status = frameMake(&s_frames[i]);
		if (status != VULKAN_OK) {
			framesRelease();
			return status;
		}
	}
	s_frameCount = count;
	return VULKAN_OK;
}

int32_t vulkanFrameBegin(uint32_t slot, uint64_t waitSerial) {
	if (slot >= s_frameCount) return fail(VULKAN_ERROR_ORDER, "vulkanFrameBegin slot %u is not below the %u frames", slot, s_frameCount);
	if (s_frameOpen >= 0) return fail(VULKAN_ERROR_ORDER, "vulkanFrameBegin while frame %d is open", s_frameOpen);
	if (s_recording != NULL) return fail(VULKAN_ERROR_ORDER, "vulkanFrameBegin with work recorded outside a frame and not submitted");
	VulkanFrame *frame = &s_frames[slot];
	if (frame->serial > waitSerial || waitSerial > s_submitted) {
		return fail(VULKAN_ERROR_ORDER, "vulkanFrameBegin slot %u was last submitted at serial %llu; waiting on %llu of %llu leaves it in flight",
			slot, (unsigned long long)frame->serial, (unsigned long long)waitSerial, (unsigned long long)s_submitted);
	}
	int32_t status = waitThrough(waitSerial);
	if (status != VULKAN_OK) return status;
	VkResult result = vkd.vkResetFences(s_vk.device, 1, &frame->fence);
	if (result != VK_SUCCESS) return failCall("vkResetFences", result);
	result = vkd.vkResetCommandPool(s_vk.device, frame->pool, 0);
	if (result != VK_SUCCESS) return failCall("vkResetCommandPool", result);
	VkCommandBufferBeginInfo begin = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
	begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
	result = vkd.vkBeginCommandBuffer(frame->commands, &begin);
	if (result != VK_SUCCESS) return failCall("vkBeginCommandBuffer", result);
	s_recording = frame->commands;
	s_frameOpen = (int32_t)slot;
	s_frameAcquired = 0;
	return VULKAN_OK;
}

static int32_t submissionRoom(void) {
	if (s_submissionCount < s_submissionCapacity) return VULKAN_OK;
	uint32_t capacity = s_submissionCapacity > 0 ? s_submissionCapacity * 2 : 8;
	VulkanSubmission *grown = realloc(s_submissions, sizeof *grown * capacity);
	if (grown == NULL) return fail(VULKAN_OUT_OF_MEMORY, "out of memory growing the submission list to %u", capacity);
	s_submissions = grown;
	s_submissionCapacity = capacity;
	return VULKAN_OK;
}

static void recordingDrop(VkCommandBuffer commands, VkCommandBuffer transfer, VulkanFrame *frame) {
	if (frame == NULL && commands != NULL) vkd.vkFreeCommandBuffers(s_vk.device, s_vk.commandPool, 1, &commands);
	if (transfer != NULL) vkd.vkFreeCommandBuffers(s_vk.device, s_vk.commandPool, 1, &transfer);
	framebuffersDestroy(s_framebuffers, s_framebufferCount);
	s_framebufferCount = 0;
}

int32_t vulkanSubmit(uint64_t *serial) {
	if (s_passOpen) return fail(VULKAN_ERROR_ORDER, "vulkanSubmit inside a render pass");
	if (s_queueStream) return fail(VULKAN_ERROR_ORDER, "vulkanSubmit while the queue stream records");
	if (s_recording == NULL && s_transfer == NULL) {
		*serial = s_submitted;
		return VULKAN_OK;
	}
	if (s_imageBarrierCount != 0) {
		return fail(VULKAN_ERROR_ORDER, "vulkanSubmit with %u image barriers never flushed", s_imageBarrierCount);
	}
	VkCommandBuffer commands = s_recording;
	VkCommandBuffer transfer = s_transfer;
	VulkanFrame *frame = s_frameOpen >= 0 ? &s_frames[s_frameOpen] : NULL;
	uint32_t acquired = s_frameAcquired;
	s_recording = NULL;
	s_transfer = NULL;
	s_frameOpen = -1;
	s_frameAcquired = 0;
	VkCommandBuffer submitted[2];
	uint32_t count = 0;
	if (transfer != NULL) submitted[count++] = transfer;
	if (commands != NULL) submitted[count++] = commands;
	for (uint32_t i = 0; i < count; i++) {
		VkResult ended = vkd.vkEndCommandBuffer(submitted[i]);
		if (ended != VK_SUCCESS) {
			recordingDrop(commands, transfer, frame);
			return failCall("vkEndCommandBuffer", ended);
		}
	}
	if (submissionRoom() != VULKAN_OK) {
		recordingDrop(commands, transfer, frame);
		return VULKAN_OUT_OF_MEMORY;
	}
	VkFramebuffer *framebuffers = NULL;
	if (s_framebufferCount != 0) {
		framebuffers = malloc(sizeof *framebuffers * s_framebufferCount);
		if (framebuffers == NULL) {
			recordingDrop(commands, transfer, frame);
			return fail(VULKAN_OUT_OF_MEMORY, "out of memory keeping %u framebuffers", s_framebufferCount);
		}
		memcpy(framebuffers, s_framebuffers, sizeof *framebuffers * s_framebufferCount);
	}
	VkFence fence = frame != NULL ? frame->fence : VK_NULL_HANDLE;
	if (frame == NULL) {
		VkFenceCreateInfo fenceInfo = { .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO };
		VkResult created = vkd.vkCreateFence(s_vk.device, &fenceInfo, NULL, &fence);
		if (created != VK_SUCCESS) {
			free(framebuffers);
			recordingDrop(commands, transfer, frame);
			return failCall("vkCreateFence", created);
		}
	}
	VkPipelineStageFlags waitStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
	VkSubmitInfo submit = { .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO };
	submit.commandBufferCount = count;
	submit.pCommandBuffers = submitted;
	if (acquired) {
		submit.waitSemaphoreCount = 1;
		submit.pWaitSemaphores = &frame->acquired;
		submit.pWaitDstStageMask = &waitStage;
	}
	VkResult result = vkd.vkQueueSubmit(s_vk.queue, 1, &submit, fence);
	if (result != VK_SUCCESS) {
		if (frame == NULL) vkd.vkDestroyFence(s_vk.device, fence, NULL);
		free(framebuffers);
		recordingDrop(commands, transfer, frame);
		return failCall("vkQueueSubmit", result);
	}
	s_submitted += 1;
	s_submissions[s_submissionCount++] = (VulkanSubmission){
		.fence = fence,
		.commands = commands,
		.transfer = transfer,
		.serial = s_submitted,
		.owned = frame == NULL,
		.framebuffers = framebuffers,
		.framebufferCount = s_framebufferCount,
	};
	s_framebufferCount = 0;
	if (frame != NULL) frame->serial = s_submitted;
	if (acquired) s_swap.presentPending = 1;
	*serial = s_submitted;
	return VULKAN_OK;
}

uint32_t vulkanRecordingOpen(void) { return s_recording != NULL; }

uint64_t vulkanRecordingSerial(void) { return s_recording != NULL || s_transfer != NULL ? s_submitted + 1 : s_submitted; }

static void submissionRelease(VulkanSubmission *submission) {
	if (submission->owned) {
		vkd.vkDestroyFence(s_vk.device, submission->fence, NULL);
		if (submission->commands != NULL) vkd.vkFreeCommandBuffers(s_vk.device, s_vk.commandPool, 1, &submission->commands);
	}
	if (submission->transfer != NULL) vkd.vkFreeCommandBuffers(s_vk.device, s_vk.commandPool, 1, &submission->transfer);
	framebuffersDestroy(submission->framebuffers, submission->framebufferCount);
	free(submission->framebuffers);
	submission->framebuffers = NULL;
	submission->framebufferCount = 0;
}

static void retireSubmissions(uint32_t count) {
	if (count == 0) return;
	for (uint32_t i = 0; i < count; i++) {
		submissionRelease(&s_submissions[i]);
		s_completed = s_submissions[i].serial;
	}
	memmove(s_submissions, s_submissions + count, sizeof *s_submissions * (s_submissionCount - count));
	s_submissionCount -= count;
}

int32_t vulkanCompletedSerial(uint64_t *serial) {
	uint32_t done = 0;
	while (done < s_submissionCount) {
		VkResult result = vkd.vkGetFenceStatus(s_vk.device, s_submissions[done].fence);
		if (result == VK_NOT_READY) break;
		if (result != VK_SUCCESS) {
			retireSubmissions(done);
			*serial = s_completed;
			return failCall("vkGetFenceStatus", result);
		}
		done++;
	}
	retireSubmissions(done);
	*serial = s_completed;
	return VULKAN_OK;
}

int32_t vulkanWaitSerial(uint64_t serial) {
	if (serial > s_submitted) {
		return fail(VULKAN_ERROR_ORDER, "vulkanWaitSerial %llu is past the last submission %llu",
			(unsigned long long)serial, (unsigned long long)s_submitted);
	}
	return waitThrough(serial);
}

void vulkanShutdown(void) {
	if (s_vk.device != NULL && vkd.vkDestroyDevice != NULL) {
		if (vkd.vkDeviceWaitIdle != NULL) vkd.vkDeviceWaitIdle(s_vk.device);
		for (uint32_t i = 0; i < s_submissionCount; i++) submissionRelease(&s_submissions[i]);
		framebuffersDestroy(s_framebuffers, s_framebufferCount);
		swapchainRelease();
		framesRelease();
		if (s_vk.commandPool != VK_NULL_HANDLE) vkd.vkDestroyCommandPool(s_vk.device, s_vk.commandPool, NULL);
		vkd.vkDestroyDevice(s_vk.device, NULL);
	}
	free(s_submissions);
	free(s_imageBarriers);
	free(s_framebuffers);
	free(s_surfaceInfo.formats);
	free(s_surfaceInfo.presentModes);
	memset(&s_surfaceInfo, 0, sizeof s_surfaceInfo);
	memset(&s_swap, 0, sizeof s_swap);
	s_swap.acquired = -1;
	memset(s_frames, 0, sizeof s_frames);
	s_frameCount = 0;
	s_frameOpen = -1;
	s_frameAcquired = 0;
	s_passOpen = 0;
	s_framebuffers = NULL;
	s_framebufferCount = 0;
	s_framebufferCapacity = 0;
	s_submissions = NULL;
	s_submissionCount = 0;
	s_submissionCapacity = 0;
	s_imageBarriers = NULL;
	s_imageBarrierCount = 0;
	s_imageBarrierCapacity = 0;
	s_recording = NULL;
	s_transfer = NULL;
	s_queueStream = 0;
	s_submitted = 0;
	s_completed = 0;
	if (s_vk.surface != VK_NULL_HANDLE && vki.vkDestroySurfaceKHR != NULL) {
		vki.vkDestroySurfaceKHR(s_vk.instance, s_vk.surface, NULL);
	}
	if (s_vk.messenger != VK_NULL_HANDLE && vki.vkDestroyDebugUtilsMessengerEXT != NULL) {
		vki.vkDestroyDebugUtilsMessengerEXT(s_vk.instance, s_vk.messenger, NULL);
	}
	if (s_vk.instance != NULL && vki.vkDestroyInstance != NULL) vki.vkDestroyInstance(s_vk.instance, NULL);
	if (s_vk.library != NULL) libraryClose(s_vk.library);
	memset(&vkb, 0, sizeof vkb);
	memset(&vki, 0, sizeof vki);
	memset(&vkd, 0, sizeof vkd);
	memset(&s_vk, 0, sizeof s_vk);
}
