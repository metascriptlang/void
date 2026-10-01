// expect: gpu door: a screen layout was resolved before gfxSetup made the device
import "../../src/sokol/gpu";
import { SWAPCHAIN_LAYOUT, TargetLayout } from "../../src/gpu/target";

const resolved: TargetLayout = SWAPCHAIN_LAYOUT.resolved();
console.log(`the screen layout resolved without a device: ${resolved.toString()}`);
