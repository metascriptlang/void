when (voidD3d12NoDebugLayer) {
	export const D3D12_DEBUG_LAYER: boolean = false;
} else {
	export const D3D12_DEBUG_LAYER: boolean = true;
}

when (windows && !voidDummy && !voidVulkan && !voidGlCore) {
	import { drainDebugMessages } from "../webgpu/d3d12/backend.ms";

	export function debugLayerMessages(): uint64 {
		return D3D12_DEBUG_LAYER ? drainDebugMessages() : 0;
	}
}
