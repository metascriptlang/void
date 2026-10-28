import { glslSegmentIr } from "../shader/emit";
import { dissolveDiscard, dissolveEdge, emissive } from "./shader3d";

const EFFECTS: string[][] = [
	["CORE", "litTexturedFs", "DISSOLVE", glslSegmentIr(dissolveDiscard)],
	["CORE", "shadowLitTexturedFs", "DISSOLVE", glslSegmentIr(dissolveDiscard)],
	["CORE", "litTexturedFs", "EMISSIVE", glslSegmentIr(emissive)],
	["CORE", "litTexturedFs", "DISSOLVE", glslSegmentIr(dissolveEdge)],
];

export function programEffects(source: string, fragment: string, features: string[]): string[] {
	return EFFECTS.filter((effect) => effect[0] == source && effect[1] == fragment &&
		features.includes(effect[2])).map((effect) => effect[3]);
}
