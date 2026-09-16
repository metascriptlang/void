import { initCampfire, frameCampfire } from "./campfireScene";

@include("../sokol/bridge.h");
extern function voidEmbedRegister(init: () => void, frame: () => void): void;

function registerVoid(): void {
	voidEmbedRegister(initCampfire, frameCampfire);
}

registerVoid();
