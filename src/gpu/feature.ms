import { stop } from "./stop";
import { GPUDevice, GPUSupportedFeatures, GPUSupportedLimits } from "../webgpu/types.ms";
import "../webgpu/device.ms";

// h3d.impl.Driver.Feature, with the members a reader here asks about. Heaps compiles compute out
// of its GL driver, so the device's own limits answer Compute and StorageBuffers.
export enum Feature {
	Compute,
	StorageBuffers,
	TimestampQuery,
}

let current: GPUDevice = { id: 0, queue: { id: 0 } };

// Called with the device each doorSetup makes, so an answer is the current device's and never
// the one a context loss took away; doorShutdown hands it the cleared device.
export function featureSetup(device: GPUDevice): void {
	current = device;
}

export function featureName(feature: Feature): string {
	return match (feature) {
		Feature.Compute => "Compute",
		Feature.StorageBuffers => "StorageBuffers",
		Feature.TimestampQuery => "TimestampQuery",
	};
}

export function featureOn(
	feature: Feature, limits: GPUSupportedLimits, features: GPUSupportedFeatures,
): boolean {
	return match (feature) {
		Feature.Compute => limits.maxComputeInvocationsPerWorkgroup > 0,
		Feature.StorageBuffers => limits.maxStorageBuffersPerShaderStage > 0,
		Feature.TimestampQuery => features.has("timestamp-query"),
	};
}

export function hasFeature(feature: Feature): boolean {
	if (current.id == 0) { stop("hasFeature " + featureName(feature) + " with no device set up"); }
	return featureOn(feature, current.limits(), current.features());
}

export function featureRefusal(feature: Feature, call: string): string {
	return call + " needs the " + featureName(feature) +
		" feature, which this device does not have";
}

export function requireFeature(feature: Feature, call: string): void {
	if (!hasFeature(feature)) { stop(featureRefusal(feature, call)); }
}
