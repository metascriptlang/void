export const BACKEND: string = @comptime {
	throw new Error("webgpu: --target=js with -d:webgl2 needs the JS WebGL2 backend, which arc void-js step B2 writes; build without -d:webgl2 until then");
};
