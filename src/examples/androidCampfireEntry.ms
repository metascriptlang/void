import { initCampfire, frameCampfire } from "./campfireScene";

@include("../host/bridge.h");
extern function voidEmbedRegister(init: () => void, frame: () => void): void;

function registerVoid(): void {
	voidEmbedRegister(initCampfire, frameCampfire);
}

registerVoid();
