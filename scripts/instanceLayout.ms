import { writeFile } from "std/fs";
import { env } from "std/process";

enum LaneKind { Float4, Color }

struct Lane {
	field: string;
	attribute: string;
	kind: LaneKind;
	constant: string;
}

function lane(field: string, attribute: string, kind: LaneKind, constant: string): Lane {
	return { field: field, attribute: attribute, kind: kind, constant: constant };
}

const uiLanes: Lane[] = [
	lane("affine", "iAffine", LaneKind.Float4, "AFFINE"),
	lane("originSize", "iOriginSize", LaneKind.Float4, "ORIGIN_SIZE"),
	lane("uvRadii", "iUvRadii", LaneKind.Float4, "UV_RADII"),
	lane("borders", "iBorders", LaneKind.Float4, "BORDERS"),
	lane("params0", "iParams0", LaneKind.Float4, "PARAMS0"),
	lane("params1", "iParams1", LaneKind.Float4, "PARAMS1"),
	lane("colorFill", "iColorFill", LaneKind.Color, "COLOR_FILL"),
	lane("colorBorder", "iColorBorder", LaneKind.Color, "COLOR_BORDER"),
	lane("colorExtra", "iColorExtra", LaneKind.Color, "COLOR_EXTRA"),
];

const spriteLanes: Lane[] = [
	lane("affine", "iAffine", LaneKind.Float4, "AFFINE"),
	lane("originSize", "iOriginSize", LaneKind.Float4, "ORIGIN_SIZE"),
	lane("uv", "iUv", LaneKind.Float4, "UV"),
	lane("color", "iColor", LaneKind.Float4, "COLOR"),
];

function gpuBytes(kind: LaneKind): int32 {
	match (kind) {
		LaneKind.Float4 => { return 16; },
		LaneKind.Color => { return 4; },
	}
}

function vertexFormat(kind: LaneKind): string {
	match (kind) {
		LaneKind.Float4 => { return "float32x4"; },
		LaneKind.Color => { return "unorm8x4"; },
	}
}

function cField(l: Lane): string {
	match (l.kind) {
		LaneKind.Float4 => { return `\tfloat ${l.field}[4];\n`; },
		LaneKind.Color => { return `\tuint32_t ${l.field};\n`; },
	}
}

// The per-vertex corner owns location 0 in every instanced program; lanes follow it.
const cornerLocation: int32 = 0;

function msConstants(prefix: string, lanes: Lane[]): string {
	let out: string = "";
	let bytes: int32 = 0;
	let floats: int32 = 0;
	for (const l of lanes) {
		out += `export const ${prefix}_${l.constant}: int32 = ${bytes};\n`;
		bytes += gpuBytes(l.kind);
	}
	out += `export const ${prefix}_STRIDE: int32 = ${bytes};\n`;
	out += `export const ${prefix}_ATTRIBUTES: int32 = ${lanes.length};\n`;
	for (const l of lanes) {
		out += `export const REC_${prefix}_${l.constant}: int32 = ${floats};\n`;
		floats += 4;
	}
	out += `export const REC_${prefix}_FLOATS: int32 = ${floats};\n`;
	out += `export const ${prefix}_FORMATS: GPUVertexFormat[${lanes.length}] = [`;
	for (const l of lanes) { out += `"${vertexFormat(l.kind)}", `; }
	out += "];\n";
	out += `export const ${prefix}_LOCATIONS: int32[${lanes.length}] = [`;
	for (let i = 0; i < lanes.length; i++) { out += `${cornerLocation + 1 + i}, `; }
	out += "];\n";
	out += `export const ${prefix}_NAMES: string[${lanes.length}] = [`;
	for (const l of lanes) { out += `"${l.attribute}", `; }
	out += "];\n";
	return out;
}

function cStruct(name: string, lanes: Lane[]): string {
	let out: string = "typedef struct {\n";
	for (const l of lanes) { out += cField(l); }
	return out + `} ${name};\n`;
}

function cPack(name: string, instance: string, lanes: Lane[]): string {
	let out: string = `static inline void ${name}(\n`;
	out += `\t${instance} *dst, const float *rec, uint32_t (*packColor)(const float *)) {\n`;
	let floats: int32 = 0;
	for (const l of lanes) {
		match (l.kind) {
			LaneKind.Float4 => {
				out += `\tmemcpy(dst->${l.field}, rec + ${floats}, 4 * sizeof(float));\n`;
			},
			LaneKind.Color => {
				out += `\tdst->${l.field} = packColor(rec + ${floats});\n`;
			},
		}
		floats += 4;
	}
	return out + "}\n";
}

function recFloats(lanes: Lane[]): int32 { return (lanes.length as int32) * 4; }

const dirSetting: string = env.get("INSTANCE_LAYOUT_DIR");
const dir: string = dirSetting.length > 0 ? dirSetting : "src/void2d";

let ms: string = "import { GPUVertexFormat } from \"../webgpu/types.ms\";\n\n";
ms += `export const INSTANCE_CORNER_LOCATION: int32 = ${cornerLocation};
`;
ms += msConstants("UI", uiLanes);
ms += msConstants("SPRITE", spriteLanes);
writeFile(`${dir}/instanceLayout.ms`, ms);

let h: string = "#pragma once\n#include <stdint.h>\n#include <string.h>\n\n";
h += cStruct("void2dUiInstance", uiLanes) + "\n";
h += cStruct("void2dSpriteInstance", spriteLanes) + "\n";
h += `#define VOID2D_UI_REC_FLOATS ${recFloats(uiLanes)}\n`;
h += `#define VOID2D_SPRITE_REC_FLOATS ${recFloats(spriteLanes)}\n\n`;
h += cPack("void2dPackUiInstance", "void2dUiInstance", uiLanes);
writeFile(`${dir}/instanceLayout.h`, h);
