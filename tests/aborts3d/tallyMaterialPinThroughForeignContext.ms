// expect: void3d: tallyMaterialPin through a context that did not issue the material
import { Program } from "../../src/void3d/gpu3d";
import { RenderState } from "../../src/gpu/state";
import { Material, Phase } from "../../src/void3d/material";
import {
	DrawContext,
	MaterialId,
	MaterialError,
	addMaterial,
	tallyMaterialPin,
} from "../../src/void3d/draw";

let made: DrawContext = DrawContext.withUniformCapacity(0);
let other: DrawContext = DrawContext.withUniformCapacity(0);
const material: Result<MaterialId, MaterialError> =
	addMaterial(made, Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque));
if (!material.ok) { unreachable; }
const _covered: boolean = tallyMaterialPin(other, material.value);
console.log("the call returned");
