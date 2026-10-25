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
	X(vkBindBufferMemory) \
	X(vkCreateImage) \
	X(vkDestroyImage) \
	X(vkGetImageMemoryRequirements) \
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
	uint32_t queueFamily;
	VkDevice device;
	VkQueue queue;
	uint32_t features;
	int32_t validation;
} s_vk;

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
	return fail(VULKAN_ERROR_CALL, "%s returned VkResult %d", call, (int)result);
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
		if (hasLayer(VALIDATION_LAYER)) {
			layerCount = 1;
			debugUtils = hasInstanceExtension(NULL, VK_EXT_DEBUG_UTILS_EXTENSION_NAME) ||
				hasInstanceExtension(VALIDATION_LAYER, VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
		} else {
			fprintf(stderr, "vulkan: validation was asked for, but %s is not installed\n", VALIDATION_LAYER);
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
	if (s_vk.physicalDevice != NULL) return fail(VULKAN_ERROR_ORDER, "%s after vulkanAdapterSelect", caller);
	return VULKAN_OK;
}

#if defined(VK_USE_PLATFORM_WIN32_KHR)
int32_t vulkanSurfaceCreateWin32(void *hinstance, void *hwnd) {
	int32_t ready = surfaceReady("vulkanSurfaceCreateWin32");
	if (ready != VULKAN_OK) return ready;
	VkWin32SurfaceCreateInfoKHR info = { .sType = VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR };
	info.hinstance = (HINSTANCE)hinstance;
	info.hwnd = (HWND)hwnd;
	VkResult result = vki.vkCreateWin32SurfaceKHR(s_vk.instance, &info, NULL, &s_vk.surface);
	return result == VK_SUCCESS ? VULKAN_OK : failCall("vkCreateWin32SurfaceKHR", result);
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
	return result == VK_SUCCESS ? VULKAN_OK : failCall("vkCreateXlibSurfaceKHR", result);
}
#endif

#if defined(VK_USE_PLATFORM_ANDROID_KHR)
int32_t vulkanSurfaceCreateAndroid(void *window) {
	int32_t ready = surfaceReady("vulkanSurfaceCreateAndroid");
	if (ready != VULKAN_OK) return ready;
	VkAndroidSurfaceCreateInfoKHR info = { .sType = VK_STRUCTURE_TYPE_ANDROID_SURFACE_CREATE_INFO_KHR };
	info.window = (struct ANativeWindow *)window;
	VkResult result = vki.vkCreateAndroidSurfaceKHR(s_vk.instance, &info, NULL, &s_vk.surface);
	return result == VK_SUCCESS ? VULKAN_OK : failCall("vkCreateAndroidSurfaceKHR", result);
}
#endif

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
	if (status == VULKAN_OK) vki.vkGetPhysicalDeviceFeatures(s_vk.physicalDevice, &s_vk.supported);
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
	return VULKAN_OK;
}

uint32_t vulkanDeviceFeatures(void) { return s_vk.features; }

void vulkanShutdown(void) {
	if (s_vk.device != NULL && vkd.vkDestroyDevice != NULL) {
		if (vkd.vkDeviceWaitIdle != NULL) vkd.vkDeviceWaitIdle(s_vk.device);
		vkd.vkDestroyDevice(s_vk.device, NULL);
	}
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
