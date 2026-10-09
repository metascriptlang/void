import {
	Program, ProgramKey, Preset, declares, VertexLayout, vertexLayoutOf,
} from "../void3d/gpu3d";
import { Material, MaterialKind, Phase } from "../void3d/material";
import { DrawContext, addMaterial } from "../void3d/draw";
import { BlendMode, RenderState } from "../gpu/state";

test "particles choose blended alpha or an explicit fixed cutout in either preset" {
	for (const preset of [Preset.Core, Preset.PixelArt]) {
		const plain: ProgramKey = { ...ProgramKey.of(Program.Particle), preset: preset };
		const cut: ProgramKey = plain.withCutout();
		assert declares(plain) && declares(cut);
		assert !plain.cutout && cut.cutout;
		assert vertexLayoutOf(plain) == VertexLayout.Particle;
		assert vertexLayoutOf(cut) == VertexLayout.Particle;
		let context: DrawContext = DrawContext.withUniformCapacity(0);
		const added = addMaterial(context,
			Material.keyed(cut, RenderState.defaults(), Phase.Opaque));
		assert added.ok;
	}
}

test "particle alpha tests depth without writing it; other Alpha materials retain their default" {
	const particle: Material = Material.ofKind(Program.Particle, MaterialKind.Alpha);
	const cut: Material = Material.ofKind(Program.Particle, MaterialKind.AlphaKill);
	const mesh: Material = Material.ofKind(Program.Lit, MaterialKind.Alpha);
	assert particle.phase == Phase.Alpha && !particle.pass.depthWrite;
	assert particle.pass == RenderState.defaults().withBlendMode(BlendMode.Alpha)
		.withDepth(false, particle.pass.depthTest).withCulling(particle.pass.culling);
	assert cut.program.cutout && cut.phase == Phase.Opaque && cut.pass.depthWrite;
	assert mesh.pass.depthWrite;
}
