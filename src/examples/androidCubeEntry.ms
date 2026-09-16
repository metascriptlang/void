import { initRenderer, renderFrame } from "./rendererSokol";

@include("../sokol/bridge.h");
extern function voidEmbedRegister(init: () => void, frame: () => void): void;

function registerVoid(): void {
	voidEmbedRegister(initRenderer, renderFrame);
}

registerVoid();
