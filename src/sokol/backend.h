#ifndef VOID_SOKOL_BACKEND_H
#define VOID_SOKOL_BACKEND_H

#if defined(SOKOL_METAL) + defined(SOKOL_D3D11) + defined(SOKOL_GLES3) + defined(SOKOL_WGPU) + \
	defined(SOKOL_GLCORE) > 1
#error "void: more than one SOKOL_<backend> is defined"
#endif

#if !defined(SOKOL_METAL) && !defined(SOKOL_D3D11) && !defined(SOKOL_GLES3) && \
	!defined(SOKOL_WGPU) && !defined(SOKOL_GLCORE)
#if defined(_WIN32)
#define SOKOL_D3D11
#elif defined(__APPLE__)
#define SOKOL_METAL
#elif defined(__ANDROID__)
#define SOKOL_GLES3
#elif defined(__EMSCRIPTEN__)
#error "void: a browser build names its API; pass -d:webgpu or -d:webgl2 to msc"
#else
#error "void: no SOKOL_<backend> for this platform; define one with -D"
#endif
#endif

#endif
