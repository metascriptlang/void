import { glslSegmentIr } from "../shader/emit";
import {
	dissolveDiscard,
	dissolveEdge,
	emissive,
	uvColorKey,
	uvDistanceFade,
	uvFlipbook,
	uvSinus,
} from "./shader3d";

const EFFECTS: string[][] = [
	["CORE", "litTexturedFs", "UV_TRANSFORM", glslSegmentIr(uvSinus)],
	["CORE", "litTexturedFs", "UV_TRANSFORM", glslSegmentIr(uvFlipbook)],
	["CORE", "litTexturedFs", "UV_TRANSFORM", glslSegmentIr(uvColorKey)],
	["CORE", "litTexturedFs", "DISSOLVE", glslSegmentIr(dissolveDiscard)],
	["CORE", "shadowLitTexturedFs", "DISSOLVE", glslSegmentIr(dissolveDiscard)],
	["CORE", "litTexturedFs", "EMISSIVE", glslSegmentIr(emissive)],
	["CORE", "litTexturedFs", "DISSOLVE", glslSegmentIr(dissolveEdge)],
	["CORE", "litTexturedFs", "UV_TRANSFORM", glslSegmentIr(uvDistanceFade)],
];

export function programEffects(source: string, fragment: string, features: string[]): string[] {
	return EFFECTS.filter((effect) => effect[0] == source && effect[1] == fragment &&
		features.includes(effect[2])).map((effect) => effect[3]);
}
