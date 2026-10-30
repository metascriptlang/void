// gate3d's judge for a frame another backend than D3D11 captured: the frame against the
// committed D3D11 image of its baseline, under golden 2D's policy (tests/golden/judge.ms), with
// `golden3d:<baseline>_<frame>@<backend>` budget rows in tests/PENDING.md.

import { readLines } from "std/fs";
import { env } from "std/process";
import { PENDING_PATH, Verdict, readPendingBudgets, judgeLoaded } from "../golden/judge";
import { voidPngLoad } from "../golden/pngio.h";

function run(): int32 {
	const listPath: string = env.get("VOID_COMPARE3D_LIST");
	const backend: string = env.get("VOID_COMPARE3D_BACKEND");
	if (listPath.length == 0 || backend.length == 0) {
		console.log("FAIL compare3d needs VOID_COMPARE3D_LIST and VOID_COMPARE3D_BACKEND");
		return 1;
	}
	const lines = readLines(listPath);
	if (!lines.ok) {
		console.log(`FAIL compare3d cannot read ${listPath}`);
		return 1;
	}
	const read = readPendingBudgets("golden3d:");
	let passed: int32 = 0;
	let pending: int32 = 0;
	let failed: int32 = 0;
	for (const line of lines.value) {
		if (line.length == 0) { continue; }
		const fields = line.split(" ");
		if ((fields.length as int32) != 3) {
			console.log(`FAIL compare3d: '${line}' is not '<key> <captured ppm> <golden png>'`);
			failed = failed + 1;
			continue;
		}
		const key: string = fields[0];
		if (voidPngLoad(1, fields[1]) == 0) {
			console.log(`FAIL ${key} was not captured (${fields[1]} is missing)`);
			failed = failed + 1;
			continue;
		}
		if (voidPngLoad(0, fields[2]) == 0) {
			console.log(`FAIL ${key} has no D3D11 image (${fields[2]})`);
			failed = failed + 1;
			continue;
		}
		const verdict = judgeLoaded(key, `${key}@${backend}`, true, read.rows, `${fields[1]}.diff.png`);
		if (verdict === Verdict.Pass) { passed = passed + 1; }
		else if (verdict === Verdict.PassPending) { pending = pending + 1; }
		else { failed = failed + 1; }
	}
	if (read.malformed > 0) {
		console.log(`golden3d ${backend}: ${read.malformed} unreadable ${PENDING_PATH} budget row(s)`);
	}
	console.log(`golden3d ${backend}: ${passed} pass, ${pending} pending, ${failed} fail`);
	return failed == 0 && read.malformed == 0 ? 0 : 1;
}

process.exit(run());
