import { Feature, featureOn, featureRefusal, featureSetup, hasFeature, requireFeature } from "../gpu/feature.ms";
import { GPUSupportedFeatures, GPUSupportedLimits, featureBit } from "../webgpu/types.ms";
import "../webgpu/device.ms";

when (voidDummy || windows) {
	import { openTestDevice } from "./testDevice.ms";
}

// What the gl backend reports for a context without compute (gl/backend.ms queryLimits).
function limitsOf(storageBuffers: int32, invocations: int32): GPUSupportedLimits {
	return {
		maxTextureDimension1D: 8192,
		maxTextureDimension2D: 8192,
		maxTextureDimension3D: 256,
		maxTextureArrayLayers: 256,
		maxBindGroups: 2,
		maxSampledTexturesPerShaderStage: 16,
		maxSamplersPerShaderStage: 16,
		maxStorageBuffersPerShaderStage: storageBuffers,
		maxStorageTexturesPerShaderStage: 0,
		maxUniformBuffersPerShaderStage: 12,
		maxUniformBufferBindingSize: 16384,
		maxStorageBufferBindingSize: 0,
		maxVertexBuffers: 8,
		maxVertexAttributes: 16,
		maxColorAttachments: 4,
		maxComputeWorkgroupSizeX: 0,
		maxComputeWorkgroupSizeY: 0,
		maxComputeWorkgroupSizeZ: 0,
		maxComputeInvocationsPerWorkgroup: invocations,
		maxComputeWorkgroupsPerDimension: 0,
		minUniformBufferOffsetAlignment: 256,
		minStorageBufferOffsetAlignment: 256,
	};
}

test "a context without compute answers Compute and StorageBuffers off, whatever its timer says" {
	const none: GPUSupportedFeatures = { bits: 0 };
	const timed: GPUSupportedFeatures = { bits: featureBit("timestamp-query") };
	assert !featureOn(Feature.Compute, limitsOf(0, 0), timed);
	assert !featureOn(Feature.StorageBuffers, limitsOf(0, 0), timed);
	assert featureOn(Feature.TimestampQuery, limitsOf(0, 0), timed);
	assert !featureOn(Feature.TimestampQuery, limitsOf(0, 0), none);
}

test "a context with compute answers both on, and each reads its own limit" {
	const none: GPUSupportedFeatures = { bits: 0 };
	assert featureOn(Feature.Compute, limitsOf(8, 1024), none);
	assert featureOn(Feature.StorageBuffers, limitsOf(8, 1024), none);
	assert !featureOn(Feature.Compute, limitsOf(8, 0), none);
	assert !featureOn(Feature.StorageBuffers, limitsOf(0, 1024), none);
	assert !featureOn(Feature.TimestampQuery, limitsOf(8, 1024), none);
}

test "a refusal names the feature and the call" {
	assert featureRefusal(Feature.Compute, "dispatchWorkgroups")
		== "dispatchWorkgroups needs the Compute feature, which this device does not have";
	assert featureRefusal(Feature.StorageBuffers, "createBindGroup").includes("StorageBuffers");
	assert featureRefusal(Feature.TimestampQuery, "enableGpuTimer").includes("TimestampQuery");
}

when (voidDummy || windows) {
	test "the test device answers every feature on, and requireFeature returns for each" {
		const device = openTestDevice();
		featureSetup(device);
		assert hasFeature(Feature.Compute);
		assert hasFeature(Feature.StorageBuffers);
		assert hasFeature(Feature.TimestampQuery);
		requireFeature(Feature.Compute, "dispatchWorkgroups");
		requireFeature(Feature.StorageBuffers, "createBindGroup");
		requireFeature(Feature.TimestampQuery, "enableGpuTimer");
		device.destroy();
	}
}
