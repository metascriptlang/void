// expect: void: voidViewCreate: all 16 views are in use or retired
@passC("-DVOID_VIEW_LAST_GENERATION=1");
import { viewCreate, viewDestroy, ViewId } from "../../src/sokol/gpu";

for (let i = 0; i < 16; i++) {
	viewDestroy(viewCreate(0 as int64, 16 as int32, 16 as int32, 1.0));
}
const again: ViewId = viewCreate(0 as int64, 16 as int32, 16 as int32, 1.0);
console.log(`view ${again} was made after every slot reached its last generation`);
