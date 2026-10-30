import { FORMAT_COUNT, GPUTextureFormat, nativeAt, textureFormatFacts } from "../types.ms";

const DXGI_UNKNOWN = 0;
const DXGI_R32G32B32A32_FLOAT = 2;
const DXGI_R32G32B32A32_UINT = 3;
const DXGI_R16G16B16A16_FLOAT = 10;
const DXGI_R16G16B16A16_UINT = 12;
const DXGI_R32G32_FLOAT = 16;
const DXGI_R32G8X24_TYPELESS = 19;
const DXGI_D32_FLOAT_S8X24_UINT = 20;
const DXGI_R32_FLOAT_X8X24_TYPELESS = 21;
const DXGI_R10G10B10A2_UNORM = 24;
const DXGI_R11G11B10_FLOAT = 26;
const DXGI_R8G8B8A8_TYPELESS = 27;
const DXGI_R8G8B8A8_UNORM = 28;
const DXGI_R8G8B8A8_UNORM_SRGB = 29;
const DXGI_R8G8B8A8_UINT = 30;
const DXGI_R8G8B8A8_SINT = 32;
const DXGI_R16G16_FLOAT = 34;
const DXGI_R32_TYPELESS = 39;
const DXGI_D32_FLOAT = 40;
const DXGI_R32_FLOAT = 41;
const DXGI_R32_UINT = 42;
const DXGI_R8G8_UNORM = 49;
const DXGI_R16_TYPELESS = 53;
const DXGI_R16_FLOAT = 54;
const DXGI_D16_UNORM = 55;
const DXGI_R16_UNORM = 56;
const DXGI_R8_UNORM = 61;
const DXGI_B8G8R8A8_UNORM = 87;
const DXGI_B8G8R8A8_TYPELESS = 90;
const DXGI_B8G8R8A8_UNORM_SRGB = 91;

export struct FormatInfo {
	texture: int32;
	shaderResource: int32;
	renderTarget: int32;
	depthStencil: int32;
	bytesPerPixel: int32;
	depth: boolean;
	stencil: boolean;
}

struct DxgiFormats {
	texture: int32;
	shaderResource: int32;
	renderTarget: int32;
	depthStencil: int32;
}

function dxgiColor(format: int32): DxgiFormats {
	return { texture: format, shaderResource: format, renderTarget: format, depthStencil: DXGI_UNKNOWN };
}

function dxgiSrgb(typeless: int32, format: int32): DxgiFormats {
	return { texture: typeless, shaderResource: format, renderTarget: format, depthStencil: DXGI_UNKNOWN };
}

const DXGI_FORMATS: DxgiFormats[] = [
	dxgiColor(DXGI_R8_UNORM),
	dxgiColor(DXGI_R8G8_UNORM),
	dxgiColor(DXGI_R8G8B8A8_UNORM),
	dxgiSrgb(DXGI_R8G8B8A8_TYPELESS, DXGI_R8G8B8A8_UNORM_SRGB),
	dxgiColor(DXGI_B8G8R8A8_UNORM),
	dxgiSrgb(DXGI_B8G8R8A8_TYPELESS, DXGI_B8G8R8A8_UNORM_SRGB),
	dxgiColor(DXGI_R8G8B8A8_UINT),
	dxgiColor(DXGI_R8G8B8A8_SINT),
	dxgiColor(DXGI_R16_FLOAT),
	dxgiColor(DXGI_R16G16_FLOAT),
	dxgiColor(DXGI_R16G16B16A16_FLOAT),
	dxgiColor(DXGI_R16G16B16A16_UINT),
	dxgiColor(DXGI_R32_FLOAT),
	dxgiColor(DXGI_R32G32_FLOAT),
	dxgiColor(DXGI_R32G32B32A32_FLOAT),
	dxgiColor(DXGI_R32G32B32A32_UINT),
	dxgiColor(DXGI_R32_UINT),
	dxgiColor(DXGI_R10G10B10A2_UNORM),
	dxgiColor(DXGI_R11G11B10_FLOAT),
	{ texture: DXGI_R16_TYPELESS, shaderResource: DXGI_R16_UNORM, renderTarget: DXGI_R16_UNORM, depthStencil: DXGI_D16_UNORM },
	{ texture: DXGI_R32_TYPELESS, shaderResource: DXGI_R32_FLOAT, renderTarget: DXGI_R32_FLOAT, depthStencil: DXGI_D32_FLOAT },
	{
		texture: DXGI_R32G8X24_TYPELESS,
		shaderResource: DXGI_R32_FLOAT_X8X24_TYPELESS,
		renderTarget: DXGI_R32_FLOAT_X8X24_TYPELESS,
		depthStencil: DXGI_D32_FLOAT_S8X24_UINT,
	},
];

export function formatInfo(format: GPUTextureFormat, member: string): FormatInfo {
	const facts = textureFormatFacts(format, member, "d3d12");
	const dxgi = nativeAt(DXGI_FORMATS, FORMAT_COUNT, facts.index, "d3d12", "DXGI format");
	return {
		texture: dxgi.texture,
		shaderResource: dxgi.shaderResource,
		renderTarget: dxgi.renderTarget,
		depthStencil: dxgi.depthStencil,
		bytesPerPixel: facts.bytesPerPixel,
		depth: facts.depth,
		stencil: facts.stencil,
	};
}

export function copyableFormat(info: FormatInfo): int32 {
	return info.depth ? info.depthStencil : info.shaderResource;
}
