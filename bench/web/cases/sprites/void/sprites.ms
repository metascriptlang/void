// The sprites scene as an emscripten wasm build (scripts/build-web.sh).

import { spritesInit, spritesFrame } from "./spritesScene";
import "../../../../../src/host/gpuWindow";

@include("../../../../../src/host/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

voidRun(1280, 720, spritesInit, spritesFrame);
