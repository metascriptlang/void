import { DeviceLoss } from "../webgpu/types";
import { removalAction } from "../webgpu/d3d11/removal";
import { lostAction } from "../webgpu/wgpu/lost";

test "the three recoverable DXGI removal codes recover" {
	assert removalAction(0x887A0005 as int32) == (DeviceLoss.Recover as int32);
	assert removalAction(0x887A0006 as int32) == (DeviceLoss.Recover as int32);
	assert removalAction(0x887A0007 as int32) == (DeviceLoss.Recover as int32);
}

test "a driver internal error is fatal and any other code is no removal" {
	assert removalAction(0x887A0020 as int32) == (DeviceLoss.Fatal as int32);
	assert removalAction(0) == (DeviceLoss.None as int32);
	assert removalAction(0x887A0001 as int32) == (DeviceLoss.None as int32);
	assert removalAction(0x887A000A as int32) == (DeviceLoss.None as int32);
	assert removalAction(0x8007000E as int32) == (DeviceLoss.None as int32);
}

test "a WebGPU lost reason of unknown or destroyed recovers" {
	assert lostAction(1) == (DeviceLoss.Recover as int32);
	assert lostAction(2) == (DeviceLoss.Recover as int32);
}

test "a cancelled callback is ignored and failed creation or a new reason is fatal" {
	assert lostAction(3) == (DeviceLoss.None as int32);
	assert lostAction(4) == (DeviceLoss.Fatal as int32);
	assert lostAction(0) == (DeviceLoss.Fatal as int32);
	assert lostAction(99) == (DeviceLoss.Fatal as int32);
}
