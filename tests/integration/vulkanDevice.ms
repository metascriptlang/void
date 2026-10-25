import { env } from "std/process";
import {
	vulkanAdapterApiVersion,
	vulkanAdapterName,
	vulkanAdapterQueueFamily,
	vulkanAdapterSelect,
	vulkanDeviceCreate,
	vulkanError,
	vulkanInstanceCreate,
	vulkanLoaderOpen,
	vulkanShutdown,
	vulkanValidationEnabled,
	vulkanValidationErrors,
	vulkanValidationWarnings,
} from "../../src/webgpu/vulkan/vulkan.h";

@passC("-I../../deps/vulkan-headers/include");
when (linux) {
	@passL("-ldl");
}

const VULKAN_OK: int32 = 0;
const VULKAN_POWER_HIGH: int32 = 2;

function step(name: string, code: int32): boolean {
	if (code == VULKAN_OK) { return true; }
	console.log(`FAIL vulkan device: ${name} returned ${code}: ${vulkanError()}`);
	vulkanShutdown();
	return false;
}

function main(): int32 {
	if (!step("vulkanLoaderOpen", vulkanLoaderOpen())) { return 1; }
	if (!step("vulkanInstanceCreate", vulkanInstanceCreate())) { return 1; }
	if (!step("vulkanAdapterSelect", vulkanAdapterSelect(VULKAN_POWER_HIGH))) { return 1; }
	if (!step("vulkanDeviceCreate", vulkanDeviceCreate())) { return 1; }
	const api: uint32 = vulkanAdapterApiVersion();
	console.log(`adapter ${vulkanAdapterName()}, Vulkan ${api >> 22}.${(api >> 12) & 1023}.` +
		`${api & 4095}, queue family ${vulkanAdapterQueueFamily()}`);
	const validated: boolean = vulkanValidationEnabled() != 0;
	vulkanShutdown();
	const errors: int32 = vulkanValidationErrors();
	console.log(`validation ${validated ? "on" : "off"}: ${errors} errors, ` +
		`${vulkanValidationWarnings()} warnings`);
	if (env.get("VOID_VULKAN_VALIDATION").equals("1") && !validated) {
		console.log("FAIL vulkan device: VOID_VULKAN_VALIDATION=1 found no validation layer");
		return 1;
	}
	if (errors != 0) {
		console.log(`FAIL vulkan device: ${errors} validation errors from instance to teardown`);
		return 1;
	}
	console.log("PASS vulkan device: loader, instance, adapter and device come up and go down");
	return 0;
}

process.exit(main());
