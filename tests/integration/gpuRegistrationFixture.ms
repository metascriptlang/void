import "../../src/gpu/door";
import {
	fixturePreload,
	fixtureProgram,
	fixtureLayout,
	fixtureDraw,
	fixtureInvalidLayoutCount,
	fixtureInvalidProgramCount,
} from "./gpuRegistrationFixture.h";

export let registrationPreload: int32 = fixturePreload();

export function foreignProgram(): int32 { return fixtureProgram(); }
export function foreignLayout(): int32 { return fixtureLayout(); }
export function drawForeign(pipeline: uint32, texture: uint32, sampler: uint32): void {
	fixtureDraw(pipeline, texture, sampler);
}
export function invalidLayoutCount(count: int32): int32 {
	return fixtureInvalidLayoutCount(count);
}
export function invalidProgramCount(count: int32): int32 {
	return fixtureInvalidProgramCount(count);
}
