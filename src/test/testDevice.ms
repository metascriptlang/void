import { GPUDevice } from "../webgpu/types.ms";
import { requestDevice } from "../webgpu/device.ms";

when (voidVulkan && !voidDummy) {
	import {
		vulkanAdapterSelect,
		vulkanDeviceCreate,
		vulkanError,
		vulkanInstanceCreate,
		vulkanLoaderOpen,
	} from "../webgpu/vulkan/vulkan.h";
}

const VULKAN_POWER_HIGH: int32 = 2;

when (windows && !voidDummy && !voidVulkan) {
	import { warpDevice, warpContext } from "./d3d11Warp.h";
	@passL("-ld3d11");
}
when (macos && !voidDummy) {
	import { metalSystemDevice } from "./metalDevice.h";
	@compile("./metalDevice.m");
}

export function openTestDevice(): GPUDevice {
	when (voidDummy) {
		return requestDevice({
			device: null,
			context: null,
			colorFormat: "rgba8unorm",
			depthFormat: "depth32float",
			sampleCount: 1,
		});
	} else when (voidVulkan) {
		if (vulkanLoaderOpen() != 0 || vulkanInstanceCreate() != 0 || vulkanAdapterSelect(VULKAN_POWER_HIGH) != 0 || vulkanDeviceCreate() != 0) {
			console.log(`openTestDevice: ${vulkanError()}`);
			unreachable;
		}
		return requestDevice({
			device: null,
			context: null,
			colorFormat: "rgba8unorm",
			depthFormat: "depth32float",
			sampleCount: 1,
		});
	} else when (windows) {
		return requestDevice({
			device: warpDevice(),
			context: warpContext(),
			colorFormat: "rgba8unorm",
			depthFormat: "depth32float",
			sampleCount: 1,
		});
	} else {
		when (macos) {
			return requestDevice({
				device: metalSystemDevice(),
				context: null,
				colorFormat: "rgba8unorm",
				depthFormat: "depth32float",
				sampleCount: 1,
			});
		} else {
			console.log("openTestDevice: this platform has no test device");
			unreachable;
		}
	}
}
