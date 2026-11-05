import "../../src/platform/frameTimingExports";
import { exit } from "std/process";
import { voidWinWindowSizeCheck } from "./winWindowSize.h";

@compile("../../src/platform/win32/window.c");
@passL("-luser32 -lshell32");

if (voidWinWindowSizeCheck() !== 0) { exit(1); }
