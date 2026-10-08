import { void2dBidiClass, void2dBidiBracket, void2dBidiMirror } from "./bidiClass.h";

export enum BidiClass {
	L,
	R,
	AL,
	EN,
	ES,
	ET,
	AN,
	CS,
	NSM,
	BN,
	B,
	S,
	WS,
	ON,
	LRE,
	LRO,
	RLE,
	RLO,
	PDF,
	LRI,
	RLI,
	FSI,
	PDI,
}

export function bidiClassOf(codepoint: int32): BidiClass {
	return void2dBidiClass(codepoint) as BidiClass;
}

export function bracketCode(codepoint: int32): int32 {
	return void2dBidiBracket(codepoint);
}

export function mirrorOf(codepoint: int32): int32 {
	return void2dBidiMirror(codepoint);
}
