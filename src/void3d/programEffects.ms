import { glslSegmentIr } from "../shader/emit";
import { emissive } from "./shader3d";

const EFFECTS: string[][] = [["CORE", "EMISSIVE", glslSegmentIr(emissive)]];

export function programEffects(source: string, features: string[]): string[] {
	return EFFECTS.filter((effect) => effect[0] == source && features.includes(effect[1]))
		.map((effect) => effect[2]);
}
