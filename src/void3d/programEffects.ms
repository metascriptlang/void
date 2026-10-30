import { glslSegmentIr } from "../shader/emit";
import {
	dissolveDiscard,
	dissolveEdge,
	emissive,
	flipbookFrames,
	uvColorKey,
	uvDistanceFade,
	uvFlipbook,
	uvSinus,
} from "./shader3d";

struct EffectRow {
	source: string;
	fragment: string;
	feature: string;
	segmentIr: string;
}

const EFFECTS: EffectRow[] = [
	{
		source: "CORE",
		fragment: "litTexturedFs",
		feature: "UV_TRANSFORM",
		segmentIr: glslSegmentIr(uvSinus),
	},
	{
		source: "CORE",
		fragment: "litTexturedFs",
		feature: "UV_TRANSFORM",
		segmentIr: glslSegmentIr(flipbookFrames),
	},
	{
		source: "CORE",
		fragment: "litTexturedFs",
		feature: "UV_TRANSFORM",
		segmentIr: glslSegmentIr(uvFlipbook),
	},
	{
		source: "CORE",
		fragment: "litTexturedFs",
		feature: "UV_TRANSFORM",
		segmentIr: glslSegmentIr(uvColorKey),
	},
	{
		source: "CORE",
		fragment: "litTexturedFs",
		feature: "DISSOLVE",
		segmentIr: glslSegmentIr(dissolveDiscard),
	},
	{
		source: "CORE",
		fragment: "shadowLitTexturedFs",
		feature: "DISSOLVE",
		segmentIr: glslSegmentIr(dissolveDiscard),
	},
	{
		source: "CORE",
		fragment: "litTexturedFs",
		feature: "EMISSIVE",
		segmentIr: glslSegmentIr(emissive),
	},
	{
		source: "CORE",
		fragment: "litTexturedFs",
		feature: "DISSOLVE",
		segmentIr: glslSegmentIr(dissolveEdge),
	},
	{
		source: "CORE",
		fragment: "litTexturedFs",
		feature: "UV_TRANSFORM",
		segmentIr: glslSegmentIr(uvDistanceFade),
	},
];

export function programEffects(source: string, fragment: string, features: string[]): string[] {
	return EFFECTS
		.filter((row) => row.source == source && row.fragment == fragment &&
			features.includes(row.feature))
		.map((row) => row.segmentIr);
}
