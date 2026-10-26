#ifndef VOID_BACKEND_H
#define VOID_BACKEND_H

#if defined(VOID_METAL) + defined(VOID_D3D11) + defined(VOID_GLES3) + defined(VOID_WGPU) + \
	defined(VOID_GLCORE) + defined(VOID_VULKAN) + defined(VOID_DUMMY) > 1
#error "void: more than one VOID_<backend> is defined"
#endif

#if !defined(VOID_METAL) && !defined(VOID_D3D11) && !defined(VOID_GLES3) && \
	!defined(VOID_WGPU) && !defined(VOID_GLCORE) && !defined(VOID_VULKAN) && !defined(VOID_DUMMY)
#if defined(_WIN32)
#define VOID_D3D11
#elif defined(__APPLE__)
#define VOID_METAL
#elif defined(__ANDROID__)
#define VOID_GLES3
#elif defined(__linux__)
#define VOID_GLCORE
#elif defined(__EMSCRIPTEN__)
#error "void: a browser build names its API; pass -d:webgpu or -d:webgl2 to msc"
#else
#error "void: no VOID_<backend> for this platform; define one with -D"
#endif
#endif

#endif
