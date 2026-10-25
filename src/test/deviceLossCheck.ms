import { removalAction, REMOVAL_NONE, REMOVAL_RECOVER, REMOVAL_FATAL } from "../webgpu/d3d11/removal";
import { lostAction, LOST_IGNORE, LOST_RECOVER, LOST_FATAL } from "../webgpu/wgpu/lost";

test "the three recoverable DXGI removal codes recover" {
	assert removalAction(0x887A0005 as int32) == REMOVAL_RECOVER;
	assert removalAction(0x887A0006 as int32) == REMOVAL_RECOVER;
	assert removalAction(0x887A0007 as int32) == REMOVAL_RECOVER;
}

test "a driver internal error is fatal and any other code is no removal" {
	assert removalAction(0x887A0020 as int32) == REMOVAL_FATAL;
	assert removalAction(0) == REMOVAL_NONE;
	assert removalAction(0x887A0001 as int32) == REMOVAL_NONE;
	assert removalAction(0x887A000A as int32) == REMOVAL_NONE;
	assert removalAction(0x8007000E as int32) == REMOVAL_NONE;
}

test "a WebGPU lost reason of unknown or destroyed recovers" {
	assert lostAction(1) == LOST_RECOVER;
	assert lostAction(2) == LOST_RECOVER;
}

test "a cancelled callback is ignored and failed creation or a new reason is fatal" {
	assert lostAction(3) == LOST_IGNORE;
	assert lostAction(4) == LOST_FATAL;
	assert lostAction(0) == LOST_FATAL;
	assert lostAction(99) == LOST_FATAL;
}
