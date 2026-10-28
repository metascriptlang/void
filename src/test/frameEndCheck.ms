import { setCommitHook, setPresentHook, frameEndAround } from "../gpu/frameCommit";

let trace: int32[] = [];

function onCommit(): void { trace.push(10); }
function onPresentEdge(begin: int32): void { trace.push(begin); }
function onPresent(): void { trace.push(20); }

test "a frame end runs the commit hook, the present begin edge, the present, the present end edge" {
	setCommitHook(onCommit);
	setPresentHook(onPresentEdge);
	frameEndAround(onPresent);
	assert trace.length == 4;
	assert trace[0] == 10 && trace[1] == 1 && trace[2] == 20 && trace[3] == 0;
}
