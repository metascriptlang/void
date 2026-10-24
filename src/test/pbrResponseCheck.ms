import { Vec3, vec3 } from "../math/math3d";
import { float32At } from "../void3d/gltfDecode";
import {
	PbrProperties,
	PbrSurface,
	PbrDirectInput,
	PbrResponseError,
	gltfLinearAlbedo,
} from "../void3d/pbrResponse";

function close(actual: float32, expected: float64): boolean {
	return Math.abs((actual as float64) - expected) < 0.0000003;
}

function input(view: Vec3): PbrDirectInput {
	return {
		normal: vec3(0.0, 0.0, 1.0),
		view: view,
		light: vec3(0.6, 0.0, 0.8),
		radiance: vec3(2.0, 0.5, 1.5),
		shadow: 0.7,
		directOcclusionFactor: 0.0,
	};
}

function surface(metalness: float32, roughness: float32): PbrSurface {
	return {
		linearAlbedo: vec3(0.8, 0.2, 0.05),
		properties: { metalness: metalness, roughness: roughness, occlusion: 1.0 },
	};
}

function independentChannel(
	albedo: float64,
	metalness: float64,
	roughness: float64,
	normalView: float64,
	normalLight: float64,
	normalHalf: float64,
	viewHalf: float64,
	radiance: float64,
	shadow: float64,
	mutation: int32 = 0,
): float64 {
	const fourthPower: float64 = Math.pow(roughness, mutation == 2 ? 2.0 : 4.0);
	const distribution: float64 = fourthPower /
		(Math.PI * Math.pow(normalHalf * normalHalf * (fourthPower - 1.0) + 1.0, 2.0));
	const remapping: float64 = Math.pow(roughness + 1.0, 2.0) / 8.0;
	const visibility: float64 = 0.25 /
		((normalView * (1.0 - remapping) + remapping) *
		(normalLight * (1.0 - remapping) + remapping));
	const weight: float64 = mutation == 3 ? Math.pow(1.0 - viewHalf, 5.0) :
		Math.pow(2.0, (-5.55473 * viewHalf - 6.98316) * viewHalf);
	const normalReflectance: float64 = 0.04 * (1.0 - metalness) + albedo * metalness;
	const fresnel: float64 = normalReflectance + (1.0 - normalReflectance) * weight;
	const diffuse: float64 = albedo / (mutation == 1 ? 1.0 : Math.PI) *
		(1.0 - metalness) * (1.0 - fresnel);
	return (diffuse + distribution * visibility * fresnel) * radiance * shadow *
		normalLight * (mutation == 4 ? normalLight : 1.0);
}

test "Heaps direct dielectric and metal response match independent unequal RGB radiance" {
	const dielectric = surface(0.0, 0.25).direct(input(vec3(0.0, 0.0, 1.0)));
	assert dielectric.ok;
	if (dielectric.ok) {
		assert close(dielectric.value.x, 0.2752713605739462);
		assert close(dielectric.value.y, 0.01749708612155253);
		assert close(dielectric.value.z, 0.014000692848207088);
	}
	const metal = surface(1.0, 0.75).direct(input(vec3(0.8, 0.0, 0.6)));
	assert metal.ok;
	if (metal.ok) {
		assert close(metal.value.x, 0.07888493453610831);
		assert close(metal.value.y, 0.004933833529802909);
		assert close(metal.value.z, 0.003710950511240601);
	}
}

test "Heaps fractional metalness uses mixed F0 and moves with view, not glTF Appendix B mix" {
	const material: PbrSurface = surface(0.35, 0.5);
	const angled = material.direct(input(vec3(0.8, 0.0, 0.6)));
	const moved = material.direct(input(vec3(0.0, 0.0, 1.0)));
	assert angled.ok && moved.ok;
	if (!angled.ok || !moved.ok) { return; }
	assert close(angled.value.x, 0.13853581853245742);
	assert close(angled.value.y, 0.011250029395056718);
	assert close(angled.value.z, 0.009370184417475476);
	assert close(moved.value.x, 0.21021377382819478);
	assert close(moved.value.y, 0.016885207241767914);
	assert close(moved.value.z, 0.01706334795838027);
	const lengthHalf: float64 = Math.sqrt(3.92);
	const normalHalf: float64 = 1.4 / lengthHalf;
	const viewHalf: float64 = 1.96 / lengthHalf;
	const expected: float64 = independentChannel(
		0.8, 0.35, 0.5, 0.6, 0.8, normalHalf, viewHalf, 2.0, 0.7,
	);
	assert close(angled.value.x, expected);
	const appendixBMaterialMixUsingHeapsKernels: float64 = 0.18783847432154285;
	assert !close(angled.value.x, appendixBMaterialMixUsingHeapsKernels);
	for (let mutation = 1; mutation <= 4; mutation++) {
		const wrong: float64 = independentChannel(
			0.8, 0.35, 0.5, 0.6, 0.8, normalHalf, viewHalf, 2.0, 0.7, mutation,
		);
		assert !close(angled.value.x, wrong);
	}
}

test "Heaps values preserve canonical roughness with dielectric defaults" {
	const defaults = PbrProperties.heapsValues();
	const supplied = PbrProperties.heapsValues(0.35, 0.0, 0.2);
	assert defaults.ok && supplied.ok;
	if (defaults.ok) {
		assert defaults.value.metalness == 0.0;
		assert defaults.value.roughness == 1.0;
		assert defaults.value.occlusion == 1.0;
	}
	if (supplied.ok) {
		assert supplied.value.metalness == 0.35;
		assert supplied.value.roughness == 0.0;
		assert supplied.value.occlusion == 0.2;
	}
	assert !PbrProperties.heapsValues(-0.1, 0.5, 1.0).ok;
}

test "Heaps R inverse squared G B packing differs from glTF linear G B separate R AO" {
	const first: Vec3 = vec3(17.0 / 255.0, 64.0 / 255.0, 192.0 / 255.0);
	const heaps = PbrProperties.heapsMap(first);
	const gltf = PbrProperties.gltfMap(0.6, 0.8, first, 0.25, 128.0 / 255.0);
	assert heaps.ok && gltf.ok;
	if (!heaps.ok || !gltf.ok) { return; }
	assert close(heaps.value.metalness, 0.06666666666666667);
	assert close(heaps.value.roughness, 0.9370088427527874);
	assert close(heaps.value.occlusion, 0.7529411764705882);
	assert close(gltf.value.metalness, 0.4517647058823529);
	assert close(gltf.value.roughness, 0.20078431372549022);
	assert close(gltf.value.occlusion, 0.8754901960784314);
	const second = PbrProperties.gltfMap(0.9, 0.4, vec3(0.8, 0.7, 0.15), 0.8, 0.2);
	const secondHeaps = PbrProperties.heapsMap(vec3(0.8, 0.7, 0.15));
	assert second.ok && secondHeaps.ok;
	if (second.ok && secondHeaps.ok) {
		assert close(second.value.metalness, 0.135);
		assert close(second.value.roughness, 0.28);
		assert close(second.value.occlusion, 0.36);
		assert close(secondHeaps.value.roughness, 0.51);
		assert secondHeaps.value.metalness == 0.8;
		assert secondHeaps.value.occlusion == 0.15;
	}
	const irrelevantRed = PbrProperties.gltfMap(0.6, 0.8, vec3(1.0, first.y, first.z),
		0.25, 128.0 / 255.0);
	assert irrelevantRed.ok;
	if (irrelevantRed.ok) { assert irrelevantRed.value == gltf.value; }
}

test "glTF schema defaults and missing textures remain separate from explicit factors" {
	const defaults = PbrProperties.gltfMap();
	const factors = PbrProperties.gltfMap(0.4, 0.7);
	const explicitWhite = PbrProperties.gltfMap(0.4, 0.7, vec3(0.2, 1.0, 1.0), 0.3, 1.0);
	const whiteBase = gltfLinearAlbedo();
	const baseFactor = gltfLinearAlbedo(vec3(1.0, 1.0, 1.0), vec3(0.2, 0.4, 0.8));
	assert defaults.ok && factors.ok && explicitWhite.ok && whiteBase.ok && baseFactor.ok;
	if (defaults.ok) {
		assert defaults.value.metalness == 1.0;
		assert defaults.value.roughness == 1.0;
		assert defaults.value.occlusion == 1.0;
	}
	if (factors.ok && explicitWhite.ok) {
		assert factors.value.metalness == 0.4;
		assert factors.value.roughness == 0.7;
		assert factors.value.occlusion == 1.0;
		assert factors.value == explicitWhite.value;
	}
	if (whiteBase.ok) { assert whiteBase.value == vec3(1.0, 1.0, 1.0); }
	if (baseFactor.ok) { assert baseFactor.value == vec3(0.2, 0.4, 0.8); }
}

test "glTF linear albedo decodes texture before multiplying linear factor and vertex color" {
	const first = gltfLinearAlbedo(
		vec3(64.0 / 255.0, 124.0 / 255.0, 231.0 / 255.0),
		vec3(0.2, 1.0, 0.7), vec3(0.5, 0.25, 0.75),
	);
	assert first.ok;
	if (first.ok) {
		assert close(first.value.x, 0.005126945837404324);
		assert close(first.value.y, 0.05038906344859927);
		assert close(first.value.z, 0.4195289374575647);
	}
	const second = gltfLinearAlbedo(
		vec3(0.04045, 0.5, 1.0), vec3(1.0, 0.3, 0.8), vec3(0.4, 0.8, 0.2),
	);
	assert second.ok;
	if (second.ok) {
		assert close(second.value.x, 0.0012523219814241486);
		assert close(second.value.y, 0.051369873715735814);
		assert close(second.value.z, 0.16);
	}
}

test "glTF direct AO is zero even when Heaps per-light AO would modulate response" {
	const plain: PbrSurface = surface(0.35, 0.5);
	const occluded: PbrSurface = {
		...plain, properties: { metalness: 0.35, roughness: 0.5, occlusion: 0.2 },
	};
	const light: PbrDirectInput = {
		...input(vec3(0.8, 0.0, 0.6)), directOcclusionFactor: 1.0,
	};
	const first = plain.gltfDirect(light);
	const second = occluded.gltfDirect(light);
	const heaps = occluded.direct(light);
	assert first.ok && second.ok && heaps.ok;
	if (first.ok && second.ok && heaps.ok) {
		assert first.value == second.value;
		assert close(heaps.value.x, 0.13853581853245742 * 0.2);
	}
}

test "canonical zero roughness preserved; direct zero and unrepresentable near-mirror refused" {
	const zero = PbrProperties.gltfMap(1.0, 0.0, vec3(1.0, 1.0, 1.0), 1.0, 1.0);
	assert zero.ok;
	if (zero.ok) { assert zero.value.roughness == 0.0; }
	const light: PbrDirectInput = { ...input(vec3(0.0, 0.0, 1.0)), light: vec3(0.0, 0.0, 1.0) };
	const unsupported = surface(1.0, 0.0).direct(light);
	assert !unsupported.ok;
	if (!unsupported.ok) { assert unsupported.error == PbrResponseError.ZeroRoughness; }
	const tiny = surface(1.0, 1e-20).direct(light);
	const cancelled = surface(1.0, 0.0001).direct(light);
	assert !tiny.ok && !cancelled.ok;
	if (!tiny.ok) { assert tiny.error == PbrResponseError.Unrepresentable; }
	if (!cancelled.ok) { assert cancelled.error == PbrResponseError.Unrepresentable; }
	const roughest = surface(0.0, 1.0).direct({
		...light, radiance: vec3(1.0, 1.0, 1.0), shadow: 1.0,
	});
	assert roughest.ok;
	if (roughest.ok) { assert close(roughest.value.x, 0.24761682943892102); }
}

test "directions normalize and shadow attenuates exactly once" {
	const material: PbrSurface = surface(0.35, 0.5);
	const light: PbrDirectInput = input(vec3(0.8, 0.0, 0.6));
	const scaled = material.direct({
		...light, normal: vec3(0.0, 0.0, 2.0), view: vec3(8.0, 0.0, 6.0),
		light: vec3(3.0, 0.0, 4.0), shadow: 0.35,
	});
	assert scaled.ok;
	if (scaled.ok) { assert close(scaled.value.x, 0.13853581853245742 * 0.5); }
}

test "direct finite domain rejects invalid properties, vectors, radiance and attenuation" {
	const material: PbrSurface = surface(0.35, 0.5);
	const light: PbrDirectInput = input(vec3(0.0, 0.0, 1.0));
	const nan: float32 = float32At([0, 0, 192, 127], 0);
	const infinity: float32 = float32At([0, 0, 128, 127], 0);
	assert !PbrProperties.gltfMap(nan, 1.0, vec3(1.0, 1.0, 1.0), 1.0, 1.0).ok;
	assert !PbrProperties.heapsMap(vec3(1.0, infinity, 1.0)).ok;
	assert !PbrProperties.gltfMap(1.1, 1.0, vec3(1.0, 1.0, 1.0), 1.0, 1.0).ok;
	assert !gltfLinearAlbedo(vec3(-0.1, 0.5, 1.0), vec3(1.0, 1.0, 1.0),
		vec3(1.0, 1.0, 1.0)).ok;
	assert !material.direct({ ...light, view: vec3(0.0, 0.0, 0.0) }).ok;
	assert !material.direct({ ...light, normal: vec3(nan, 0.0, 1.0) }).ok;
	assert !material.direct({ ...light, light: vec3(1e30, 0.0, 0.0) }).ok;
	assert !material.direct({ ...light, radiance: vec3(-1.0, 0.0, 0.0) }).ok;
	assert !material.direct({ ...light, radiance: vec3(infinity, 0.0, 0.0) }).ok;
	assert !material.direct({ ...light, shadow: 1.1 }).ok;
	assert !material.direct({ ...light, directOcclusionFactor: -0.1 }).ok;
	const opposite = material.direct({ ...light, light: vec3(0.0, 0.0, -1.0) });
	assert opposite.ok;
	if (opposite.ok) { assert opposite.value == vec3(0.0, 0.0, 0.0); }
	const dim = material.direct({ ...light, radiance: vec3(0.001, 0.0, 0.0) });
	assert dim.ok;
	if (dim.ok) { assert dim.value == vec3(0.0, 0.0, 0.0); }
}
