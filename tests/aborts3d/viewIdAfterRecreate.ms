// expect: void: voidViewResize: view 33 was destroyed; a view id names one view only
import { viewCreate, viewResize, viewDestroy, ViewId } from "../../src/sokol/gpu";

const first: ViewId = viewCreate(0 as int64, 64 as int32, 64 as int32, 1.0);
viewDestroy(first);
const second: ViewId = viewCreate(0 as int64, 64 as int32, 64 as int32, 1.0);
viewResize(first, 32 as int32, 32 as int32, 1.0);
console.log(`the destroyed view ${first} resized view ${second}`);
