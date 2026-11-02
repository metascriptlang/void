@block pbrProperties
struct PbrProperties {
	float metalness;
	float roughness;
	float occlusion;
};

bool pbrFinite(float value) {
	return !isnan(value) && !isinf(value);
}

bool pbrFiniteVector(vec3 value) {
	return !any(isnan(value)) && !any(isinf(value));
}

bool pbrUnitInterval(float value) {
	return pbrFinite(value) && value >= 0.0 && value <= 1.0;
}

bool pbrUnitColor(vec3 value) {
	return pbrFiniteVector(value) && all(greaterThanEqual(value, vec3(0.0))) &&
		all(lessThanEqual(value, vec3(1.0)));
}

PbrProperties pbrHeapsDefaults() {
	return PbrProperties(0.0, 1.0, 1.0);
}

bool pbrHeapsValues(
	float metalness,
	float roughness,
	float occlusion,
	out PbrProperties properties
) {
	properties = PbrProperties(0.0, 0.0, 0.0);
	if (!pbrUnitInterval(metalness) || !pbrUnitInterval(roughness) ||
		!pbrUnitInterval(occlusion)) { return false; }
	properties = PbrProperties(metalness, roughness, occlusion);
	return true;
}

bool pbrHeapsMap(vec3 sampleValue, out PbrProperties properties) {
	properties = PbrProperties(0.0, 0.0, 0.0);
	if (!pbrUnitColor(sampleValue)) { return false; }
	properties = PbrProperties(sampleValue.r, 1.0 - sampleValue.g * sampleValue.g, sampleValue.b);
	return true;
}

bool pbrGltfMap(
	float metallicFactor,
	float roughnessFactor,
	vec3 metallicRoughnessSample,
	float occlusionStrength,
	float occlusionRed,
	out PbrProperties properties
) {
	properties = PbrProperties(0.0, 0.0, 0.0);
	if (!pbrUnitInterval(metallicFactor) || !pbrUnitInterval(roughnessFactor) ||
		!pbrUnitInterval(metallicRoughnessSample.g) ||
		!pbrUnitInterval(metallicRoughnessSample.b) ||
		!pbrUnitInterval(occlusionStrength) || !pbrUnitInterval(occlusionRed)) {
		return false;
	}
	properties = PbrProperties(
		metallicFactor * metallicRoughnessSample.b,
		roughnessFactor * metallicRoughnessSample.g,
		1.0 + occlusionStrength * (occlusionRed - 1.0)
	);
	return true;
}

PbrProperties pbrGltfDefaults() {
	return PbrProperties(1.0, 1.0, 1.0);
}

bool pbrGltfMap(float metallicFactor, float roughnessFactor, out PbrProperties properties) {
	return pbrGltfMap(metallicFactor, roughnessFactor, vec3(1.0), 1.0, 1.0, properties);
}

float pbrDecodeSrgb(float channel) {
	return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4);
}

bool pbrGltfLinearAlbedo(
	vec3 encodedTexture,
	vec3 linearFactor,
	vec3 linearVertexColor,
	out vec3 linearAlbedo
) {
	linearAlbedo = vec3(0.0);
	if (!pbrUnitColor(encodedTexture) || !pbrUnitColor(linearFactor) ||
		!pbrUnitColor(linearVertexColor)) { return false; }
	vec3 decoded = vec3(pbrDecodeSrgb(encodedTexture.r), pbrDecodeSrgb(encodedTexture.g),
		pbrDecodeSrgb(encodedTexture.b));
	linearAlbedo = decoded * linearFactor * linearVertexColor;
	return true;
}

bool pbrGltfLinearAlbedo(vec3 linearFactor, out vec3 linearAlbedo) {
	return pbrGltfLinearAlbedo(vec3(1.0), linearFactor, vec3(1.0), linearAlbedo);
}
@end

@block pbrDirectResponse
@include_block pbrProperties
bool pbrDirection(vec3 value, out vec3 unitDirection) {
	unitDirection = vec3(0.0);
	float squared = dot(value, value);
	if (!pbrFiniteVector(value) || !pbrFinite(squared) || squared <= 0.0) { return false; }
	unitDirection = value / sqrt(squared);
	return pbrFiniteVector(unitDirection);
}

// Heaps BRDF.hx:40-63 has no isotropic endpoint guard. False means unsupported evaluation,
// not black shading: caller must handle failure before accepting output, never invent a floor.
bool pbrDirectResponse(
	vec3 linearAlbedo,
	PbrProperties properties,
	vec3 normalDirection,
	vec3 viewDirection,
	vec3 lightDirection,
	vec3 radianceWithoutFacing,
	float shadow,
	float directOcclusionFactor,
	out vec3 response
) {
	response = vec3(0.0);
	if (!pbrUnitColor(linearAlbedo) || !pbrUnitInterval(properties.metalness) ||
		!pbrUnitInterval(properties.roughness) || !pbrUnitInterval(properties.occlusion) ||
		!pbrUnitInterval(shadow) || !pbrUnitInterval(directOcclusionFactor) ||
		!pbrFiniteVector(radianceWithoutFacing) ||
		any(lessThan(radianceWithoutFacing, vec3(0.0))) || properties.roughness == 0.0) {
		return false;
	}
	vec3 normal;
	vec3 view;
	vec3 light;
	if (!pbrDirection(normalDirection, normal) || !pbrDirection(viewDirection, view) ||
		!pbrDirection(lightDirection, light)) { return false; }
	float normalLight = clamp(dot(normal, light), 0.0, 1.0);
	float energySquared = dot(radianceWithoutFacing, radianceWithoutFacing);
	if (!pbrFinite(energySquared)) { return false; }
	if (normalLight <= 0.0 || energySquared <= 0.0001) { return true; }
	vec3 halfDirection;
	if (!pbrDirection(light + view, halfDirection)) { return false; }
	float normalHalf = clamp(dot(normal, halfDirection), 0.0, 1.0);
	float viewHalf = clamp(dot(view, halfDirection), 0.0, 1.0);
	float normalView = clamp(dot(normal, view), 0.0, 1.0);
	float alpha = properties.roughness * properties.roughness;
	float alphaSquared = alpha * alpha;
	float denominator = normalHalf * normalHalf * (alphaSquared - 1.0) + 1.0;
	float distributionDenominator = 3.141592653589793 * denominator * denominator;
	if (alphaSquared <= 0.0 || denominator <= 0.0 || distributionDenominator <= 0.0) {
		return false;
	}
	float distribution = alphaSquared / distributionDenominator;
	float remapping = properties.roughness + 1.0;
	float k = remapping * remapping * 0.125;
	float visibility = (1.0 / (normalView * (1.0 - k) + k)) *
		(1.0 / (normalLight * (1.0 - k) + k)) * 0.25;
	vec3 normalReflectance = mix(vec3(0.04), linearAlbedo, properties.metalness);
	vec3 fresnel = normalReflectance + (1.0 - normalReflectance) *
		exp2((-5.55473 * viewHalf - 6.98316) * viewHalf);
	vec3 specular = max(distribution * fresnel * visibility, vec3(0.0));
	vec3 direct = (linearAlbedo / 3.141592653589793) * (1.0 - properties.metalness) *
		(1.0 - fresnel) + specular;
	float occlusion = mix(1.0, properties.occlusion, directOcclusionFactor);
	vec3 result = direct * radianceWithoutFacing * (normalLight * shadow * occlusion);
	if (!pbrFinite(distribution) || !pbrFinite(visibility) || !pbrFiniteVector(result)) {
		return false;
	}
	response = result;
	return true;
}

bool pbrGltfDirectResponse(
	vec3 linearAlbedo,
	PbrProperties properties,
	vec3 normalDirection,
	vec3 viewDirection,
	vec3 lightDirection,
	vec3 radianceWithoutFacing,
	float shadow,
	out vec3 response
) {
	return pbrDirectResponse(linearAlbedo, properties, normalDirection, viewDirection,
		lightDirection, radianceWithoutFacing, shadow, 0.0, response);
}
@end
