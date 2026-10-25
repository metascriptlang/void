#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "gl.h"

#if defined(__EMSCRIPTEN__) || defined(__ANDROID__) || (defined(__linux__) && defined(VOID_GLES3))
#define OGL_GLES 1
#include <GLES3/gl3.h>
#if defined(__EMSCRIPTEN__)
void glGetBufferSubData(GLenum target, GLintptr offset, GLsizeiptr size, void *data);
#elif defined(__ANDROID__) && __ANDROID_API__ >= 24
#include <GLES3/gl32.h>
#define OGL_DEBUG 1
#else
#include <GLES3/gl31.h>
#endif
#elif defined(__linux__)
#define GL_GLEXT_PROTOTYPES
#include <GL/gl.h>
#elif !defined(_WIN32)
#error "the GL backend loads GL through WGL, links libGL or libGLESv2 on Linux or takes GLES3 from emscripten or Android; another platform needs its GL headers and loader here"
#else

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#define GL_APIENTRY APIENTRY
typedef unsigned int GLenum;
typedef unsigned int GLuint;
typedef int GLsizei;
typedef char GLchar;
typedef ptrdiff_t GLintptr;
typedef ptrdiff_t GLsizeiptr;
typedef unsigned char GLboolean;
typedef unsigned char GLubyte;
typedef long long GLint64;
typedef unsigned long long GLuint64;
typedef unsigned int GLbitfield;
typedef float GLfloat;
typedef double GLdouble;
typedef int GLint;

#define GL_NO_ERROR 0
#define GL_TRUE 1
#define GL_FALSE 0
#define GL_NONE 0
#define GL_NEAREST 0x2600
#define GL_COLOR 0x1800
#define GL_DEPTH 0x1801
#define GL_DEPTH_STENCIL 0x84F9
#define GL_DEPTH_COMPONENT 0x1902
#define GL_DEPTH_ATTACHMENT 0x8D00
#define GL_BACK 0x0405
#define GL_COLOR_BUFFER_BIT 0x00004000
#define GL_FRAMEBUFFER 0x8D40
#define GL_READ_FRAMEBUFFER 0x8CA8
#define GL_DRAW_FRAMEBUFFER 0x8CA9
#define GL_RENDERBUFFER 0x8D41
#define GL_TEXTURE_2D 0x0DE1
#define GL_TEXTURE_3D 0x806F
#define GL_TEXTURE_2D_ARRAY 0x8C1A
#define GL_TEXTURE0 0x84C0
#define GL_COLOR_ATTACHMENT0 0x8CE0
#define GL_TEXTURE_BORDER_COLOR 0x1004
#define GL_UNPACK_ROW_LENGTH 0x0CF2
#define GL_UNPACK_IMAGE_HEIGHT 0x806E
#define GL_PACK_ROW_LENGTH 0x0D02
#define GL_PACK_ALIGNMENT 0x0D05
#define GL_PIXEL_PACK_BUFFER 0x88EB
#define GL_PIXEL_UNPACK_BUFFER 0x88EC
#define GL_COPY_READ_BUFFER 0x8F36
#define GL_COPY_WRITE_BUFFER 0x8F37
#define GL_READ_FRAMEBUFFER_BINDING 0x8CAA
#define GL_FRAMEBUFFER_COMPLETE 0x8CD5
#define GL_TEXTURE_CUBE_MAP 0x8513
#define GL_TEXTURE_CUBE_MAP_POSITIVE_X 0x8515
#define GL_COMPILE_STATUS 0x8B81
#define GL_LINK_STATUS 0x8B82
#define GL_INFO_LOG_LENGTH 0x8B84

#define OGL_FUNCS \
	OGL_XMACRO(glGetError,                 GLenum, (void)) \
	OGL_XMACRO(glGetIntegerv,              void, (GLenum pname, GLint *data)) \
	OGL_XMACRO(glGetInteger64v,            void, (GLenum pname, GLint64 *data)) \
	OGL_XMACRO(glGetIntegeri_v,            void, (GLenum target, GLuint index, GLint *data)) \
	OGL_XMACRO(glGetStringi,               const GLubyte *, (GLenum name, GLuint index)) \
	OGL_XMACRO(glGenQueries,               void, (GLsizei n, GLuint *ids)) \
	OGL_XMACRO(glDeleteQueries,            void, (GLsizei n, const GLuint *ids)) \
	OGL_XMACRO(glBeginQuery,               void, (GLenum target, GLuint id)) \
	OGL_XMACRO(glEndQuery,                 void, (GLenum target)) \
	OGL_XMACRO(glQueryCounter,             void, (GLuint id, GLenum target)) \
	OGL_XMACRO(glGetQueryiv,               void, (GLenum target, GLenum pname, GLint *params)) \
	OGL_XMACRO(glGetQueryObjectuiv,        void, (GLuint id, GLenum pname, GLuint *params)) \
	OGL_XMACRO(glGetQueryObjectui64v,      void, (GLuint id, GLenum pname, GLuint64 *params)) \
	OGL_XMACRO(glDispatchCompute,          void, (GLuint x, GLuint y, GLuint z)) \
	OGL_XMACRO(glDispatchComputeIndirect,  void, (GLintptr indirect)) \
	OGL_XMACRO(glMemoryBarrier,            void, (GLbitfield barriers)) \
	OGL_XMACRO(glBindBufferRange,          void, (GLenum target, GLuint index, GLuint buffer, GLintptr offset, GLsizeiptr size)) \
	OGL_XMACRO(glBindImageTexture,         void, (GLuint unit, GLuint texture, GLint level, GLboolean layered, GLint layer, GLenum access, GLenum format)) \
	OGL_XMACRO(glPushDebugGroup,           void, (GLenum source, GLuint id, GLsizei length, const GLchar *message)) \
	OGL_XMACRO(glPopDebugGroup,            void, (void)) \
	OGL_XMACRO(glDebugMessageInsert,       void, (GLenum source, GLenum type, GLuint id, GLenum severity, GLsizei length, const GLchar *buf)) \
	OGL_XMACRO(glObjectLabel,              void, (GLenum identifier, GLuint name, GLsizei length, const GLchar *label)) \
	OGL_XMACRO(glEnable,                   void, (GLenum cap)) \
	OGL_XMACRO(glDisable,                  void, (GLenum cap)) \
	OGL_XMACRO(glPixelStorei,              void, (GLenum pname, GLint param)) \
	OGL_XMACRO(glGenVertexArrays,          void, (GLsizei n, GLuint *arrays)) \
	OGL_XMACRO(glBindVertexArray,          void, (GLuint array)) \
	OGL_XMACRO(glDeleteVertexArrays,       void, (GLsizei n, const GLuint *arrays)) \
	OGL_XMACRO(glGenBuffers,               void, (GLsizei n, GLuint *buffers)) \
	OGL_XMACRO(glBindBuffer,               void, (GLenum target, GLuint buffer)) \
	OGL_XMACRO(glBufferData,               void, (GLenum target, GLsizeiptr size, const void *data, GLenum usage)) \
	OGL_XMACRO(glBufferSubData,            void, (GLenum target, GLintptr offset, GLsizeiptr size, const void *data)) \
	OGL_XMACRO(glDeleteBuffers,            void, (GLsizei n, const GLuint *buffers)) \
	OGL_XMACRO(glCopyBufferSubData,        void, (GLenum readTarget, GLenum writeTarget, GLintptr readOffset, GLintptr writeOffset, GLsizeiptr size)) \
	OGL_XMACRO(glGetBufferSubData,         void, (GLenum target, GLintptr offset, GLsizeiptr size, void *data)) \
	OGL_XMACRO(glReadPixels,               void, (GLint x, GLint y, GLsizei width, GLsizei height, GLenum format, GLenum type, void *pixels)) \
	OGL_XMACRO(glCopyTexSubImage2D,        void, (GLenum target, GLint level, GLint xoffset, GLint yoffset, GLint x, GLint y, GLsizei width, GLsizei height)) \
	OGL_XMACRO(glCopyTexSubImage3D,        void, (GLenum target, GLint level, GLint xoffset, GLint yoffset, GLint zoffset, GLint x, GLint y, GLsizei width, GLsizei height)) \
	OGL_XMACRO(glGenTextures,              void, (GLsizei n, GLuint *textures)) \
	OGL_XMACRO(glActiveTexture,            void, (GLenum texture)) \
	OGL_XMACRO(glBindTexture,              void, (GLenum target, GLuint texture)) \
	OGL_XMACRO(glTexStorage2D,             void, (GLenum target, GLsizei levels, GLenum internalformat, GLsizei width, GLsizei height)) \
	OGL_XMACRO(glTexStorage2DMultisample,  void, (GLenum target, GLsizei samples, GLenum internalformat, GLsizei width, GLsizei height, GLboolean fixedsamplelocations)) \
	OGL_XMACRO(glTexStorage3D,             void, (GLenum target, GLsizei levels, GLenum internalformat, GLsizei width, GLsizei height, GLsizei depth)) \
	OGL_XMACRO(glTexSubImage2D,            void, (GLenum target, GLint level, GLint xoffset, GLint yoffset, GLsizei width, GLsizei height, GLenum format, GLenum type, const void *pixels)) \
	OGL_XMACRO(glTexSubImage3D,            void, (GLenum target, GLint level, GLint xoffset, GLint yoffset, GLint zoffset, GLsizei width, GLsizei height, GLsizei depth, GLenum format, GLenum type, const void *pixels)) \
	OGL_XMACRO(glTexParameteri,            void, (GLenum target, GLenum pname, GLint param)) \
	OGL_XMACRO(glDeleteTextures,           void, (GLsizei n, const GLuint *textures)) \
	OGL_XMACRO(glGenSamplers,              void, (GLsizei n, GLuint *samplers)) \
	OGL_XMACRO(glSamplerParameteri,        void, (GLuint sampler, GLenum pname, GLint param)) \
	OGL_XMACRO(glSamplerParameterf,        void, (GLuint sampler, GLenum pname, GLfloat param)) \
	OGL_XMACRO(glSamplerParameterfv,       void, (GLuint sampler, GLenum pname, const GLfloat *params)) \
	OGL_XMACRO(glBindSampler,              void, (GLuint unit, GLuint sampler)) \
	OGL_XMACRO(glDeleteSamplers,           void, (GLsizei n, const GLuint *samplers)) \
	OGL_XMACRO(glCreateShader,             GLuint, (GLenum type)) \
	OGL_XMACRO(glShaderSource,             void, (GLuint shader, GLsizei count, const GLchar *const *string, const GLint *length)) \
	OGL_XMACRO(glCompileShader,            void, (GLuint shader)) \
	OGL_XMACRO(glGetShaderiv,              void, (GLuint shader, GLenum pname, GLint *params)) \
	OGL_XMACRO(glGetShaderInfoLog,         void, (GLuint shader, GLsizei bufSize, GLsizei *length, GLchar *infoLog)) \
	OGL_XMACRO(glDeleteShader,             void, (GLuint shader)) \
	OGL_XMACRO(glCreateProgram,            GLuint, (void)) \
	OGL_XMACRO(glAttachShader,             void, (GLuint program, GLuint shader)) \
	OGL_XMACRO(glLinkProgram,              void, (GLuint program)) \
	OGL_XMACRO(glGetProgramiv,             void, (GLuint program, GLenum pname, GLint *params)) \
	OGL_XMACRO(glGetProgramInfoLog,        void, (GLuint program, GLsizei bufSize, GLsizei *length, GLchar *infoLog)) \
	OGL_XMACRO(glDeleteProgram,            void, (GLuint program)) \
	OGL_XMACRO(glUseProgram,               void, (GLuint program)) \
	OGL_XMACRO(glGetUniformLocation,       GLint, (GLuint program, const GLchar *name)) \
	OGL_XMACRO(glGetAttribLocation,        GLint, (GLuint program, const GLchar *name)) \
	OGL_XMACRO(glUniform1i,                void, (GLint location, GLint v0)) \
	OGL_XMACRO(glUniform4fv,               void, (GLint location, GLsizei count, const GLfloat *value)) \
	OGL_XMACRO(glDepthFunc,                void, (GLenum func)) \
	OGL_XMACRO(glDepthMask,                void, (GLboolean flag)) \
	OGL_XMACRO(glStencilMask,              void, (GLuint mask)) \
	OGL_XMACRO(glStencilFunc,              void, (GLenum func, GLint ref, GLuint mask)) \
	OGL_XMACRO(glStencilOp,                void, (GLenum fail, GLenum zfail, GLenum zpass)) \
	OGL_XMACRO(glStencilFuncSeparate,      void, (GLenum face, GLenum func, GLint ref, GLuint mask)) \
	OGL_XMACRO(glStencilOpSeparate,        void, (GLenum face, GLenum sfail, GLenum dpfail, GLenum dppass)) \
	OGL_XMACRO(glDepthRange,               void, (GLdouble n, GLdouble f)) \
	OGL_XMACRO(glEnablei,                  void, (GLenum target, GLuint index)) \
	OGL_XMACRO(glDisablei,                 void, (GLenum target, GLuint index)) \
	OGL_XMACRO(glBlendFuncSeparatei,       void, (GLuint buf, GLenum srcRGB, GLenum dstRGB, GLenum srcAlpha, GLenum dstAlpha)) \
	OGL_XMACRO(glBlendEquationSeparatei,   void, (GLuint buf, GLenum modeRGB, GLenum modeAlpha)) \
	OGL_XMACRO(glBlendFuncSeparate,        void, (GLenum sfactorRGB, GLenum dfactorRGB, GLenum sfactorAlpha, GLenum dfactorAlpha)) \
	OGL_XMACRO(glBlendEquationSeparate,    void, (GLenum modeRGB, GLenum modeAlpha)) \
	OGL_XMACRO(glBlendColor,               void, (GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha)) \
	OGL_XMACRO(glColorMask,                void, (GLboolean red, GLboolean green, GLboolean blue, GLboolean alpha)) \
	OGL_XMACRO(glColorMaski,               void, (GLuint buf, GLboolean red, GLboolean green, GLboolean blue, GLboolean alpha)) \
	OGL_XMACRO(glPolygonOffset,            void, (GLfloat factor, GLfloat units)) \
	OGL_XMACRO(glCullFace,                 void, (GLenum mode)) \
	OGL_XMACRO(glFrontFace,                void, (GLenum mode)) \
	OGL_XMACRO(glViewport,                 void, (GLint x, GLint y, GLsizei width, GLsizei height)) \
	OGL_XMACRO(glScissor,                  void, (GLint x, GLint y, GLsizei width, GLsizei height)) \
	OGL_XMACRO(glGenFramebuffers,          void, (GLsizei n, GLuint *framebuffers)) \
	OGL_XMACRO(glBindFramebuffer,          void, (GLenum target, GLuint framebuffer)) \
	OGL_XMACRO(glDeleteFramebuffers,       void, (GLsizei n, const GLuint *framebuffers)) \
	OGL_XMACRO(glFramebufferTexture2D,     void, (GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level)) \
	OGL_XMACRO(glFramebufferRenderbuffer,  void, (GLenum target, GLenum attachment, GLenum renderbuffertarget, GLuint renderbuffer)) \
	OGL_XMACRO(glGenRenderbuffers,         void, (GLsizei n, GLuint *renderbuffers)) \
	OGL_XMACRO(glBindRenderbuffer,         void, (GLenum target, GLuint renderbuffer)) \
	OGL_XMACRO(glRenderbufferStorageMultisample, void, (GLenum target, GLsizei samples, GLenum internalformat, GLsizei width, GLsizei height)) \
	OGL_XMACRO(glDeleteRenderbuffers,      void, (GLsizei n, const GLuint *renderbuffers)) \
	OGL_XMACRO(glFramebufferTextureLayer,  void, (GLenum target, GLenum attachment, GLuint texture, GLint level, GLint layer)) \
	OGL_XMACRO(glCheckFramebufferStatus,   GLenum, (GLenum target)) \
	OGL_XMACRO(glDrawBuffers,              void, (GLsizei n, const GLenum *bufs)) \
	OGL_XMACRO(glReadBuffer,               void, (GLenum src)) \
	OGL_XMACRO(glBlitFramebuffer,          void, (GLint srcX0, GLint srcY0, GLint srcX1, GLint srcY1, GLint dstX0, GLint dstY0, GLint dstX1, GLint dstY1, GLbitfield mask, GLenum filter)) \
	OGL_XMACRO(glClearBufferfv,            void, (GLenum buffer, GLint drawbuffer, const GLfloat *value)) \
	OGL_XMACRO(glClearBufferfi,            void, (GLenum buffer, GLint drawbuffer, GLfloat depth, GLint stencil)) \
	OGL_XMACRO(glVertexAttribPointer,      void, (GLuint index, GLint size, GLenum type, GLboolean normalized, GLsizei stride, const void *pointer)) \
	OGL_XMACRO(glVertexAttribIPointer,     void, (GLuint index, GLint size, GLenum type, GLsizei stride, const void *pointer)) \
	OGL_XMACRO(glVertexAttribDivisor,      void, (GLuint index, GLuint divisor)) \
	OGL_XMACRO(glEnableVertexAttribArray,  void, (GLuint index)) \
	OGL_XMACRO(glDisableVertexAttribArray, void, (GLuint index)) \
	OGL_XMACRO(glDrawArrays,               void, (GLenum mode, GLint first, GLsizei count)) \
	OGL_XMACRO(glDrawArraysInstanced,      void, (GLenum mode, GLint first, GLsizei count, GLsizei instancecount)) \
	OGL_XMACRO(glDrawArraysInstancedBaseInstance, void, (GLenum mode, GLint first, GLsizei count, GLsizei instancecount, GLuint baseinstance)) \
	OGL_XMACRO(glDrawElements,             void, (GLenum mode, GLsizei count, GLenum type, const void *indices)) \
	OGL_XMACRO(glDrawElementsBaseVertex,   void, (GLenum mode, GLsizei count, GLenum type, const void *indices, GLint basevertex)) \
	OGL_XMACRO(glDrawElementsInstanced,    void, (GLenum mode, GLsizei count, GLenum type, const void *indices, GLsizei instancecount)) \
	OGL_XMACRO(glDrawElementsInstancedBaseVertex, void, (GLenum mode, GLsizei count, GLenum type, const void *indices, GLsizei instancecount, GLint basevertex)) \
	OGL_XMACRO(glDrawElementsInstancedBaseVertexBaseInstance, void, (GLenum mode, GLsizei count, GLenum type, const void *indices, GLsizei instancecount, GLint basevertex, GLuint baseinstance))

#define OGL_XMACRO(name, ret, args) typedef ret (GL_APIENTRY *PFN_ogl_##name) args;
OGL_FUNCS
#undef OGL_XMACRO

#define OGL_XMACRO(name, ret, args) static PFN_ogl_##name name;
OGL_FUNCS
#undef OGL_XMACRO

typedef PROC (WINAPI *WglGetProcAddressFn)(LPCSTR);

static HMODULE s_opengl32;
static WglGetProcAddressFn s_wglGetProcAddress;
static char s_missing[128];
static char s_log[4096];

static void *procAddress(const char *name) {
	void *address = (void *)s_wglGetProcAddress(name);
	if (address == NULL) address = (void *)GetProcAddress(s_opengl32, name);
	if (address == NULL && s_missing[0] == 0) {
		strncpy(s_missing, name, sizeof s_missing - 1);
	}
	return address;
}

int32_t oglLoad(void) {
	s_missing[0] = 0;
	if (s_opengl32 == NULL) s_opengl32 = LoadLibraryA("opengl32.dll");
	if (s_opengl32 == NULL) {
		strcpy(s_missing, "opengl32.dll");
		return 0;
	}
	s_wglGetProcAddress = (WglGetProcAddressFn)(void *)GetProcAddress(s_opengl32, "wglGetProcAddress");
	if (s_wglGetProcAddress == NULL) {
		strcpy(s_missing, "wglGetProcAddress");
		return 0;
	}
#define OGL_XMACRO(name, ret, args) name = (PFN_ogl_##name)procAddress(#name);
	OGL_FUNCS
#undef OGL_XMACRO
	return s_missing[0] == 0 ? 1 : 0;
}

const char *oglLoadMissing(void) { return s_missing; }

void oglUnload(void) {
	if (s_opengl32) FreeLibrary(s_opengl32);
	s_opengl32 = NULL;
}

#endif

#if !defined(__EMSCRIPTEN__)
#define OGL_COMPUTE 1
#endif
#if !defined(OGL_GLES)
#define OGL_DEBUG 1
#define OGL_TIMER 1
#endif

#ifndef GL_NUM_EXTENSIONS
#define GL_NUM_EXTENSIONS 0x821D
#endif
#ifndef GL_EXTENSIONS
#define GL_EXTENSIONS 0x1F03
#endif
#ifndef GL_QUERY_RESULT
#define GL_QUERY_RESULT 0x8866
#endif
#ifndef GL_QUERY_RESULT_AVAILABLE
#define GL_QUERY_RESULT_AVAILABLE 0x8867
#endif
#ifndef GL_TIMESTAMP
#define GL_TIMESTAMP 0x8E28
#endif
#ifndef GL_QUERY_COUNTER_BITS
#define GL_QUERY_COUNTER_BITS 0x8864
#endif
#ifndef GL_DISPATCH_INDIRECT_BUFFER
#define GL_DISPATCH_INDIRECT_BUFFER 0x90EE
#endif
#ifndef GL_DEBUG_SOURCE_APPLICATION
#define GL_DEBUG_SOURCE_APPLICATION 0x824A
#endif
#ifndef GL_DEBUG_TYPE_MARKER
#define GL_DEBUG_TYPE_MARKER 0x8268
#endif
#ifndef GL_DEBUG_SEVERITY_NOTIFICATION
#define GL_DEBUG_SEVERITY_NOTIFICATION 0x826B
#endif

#if !defined(_WIN32)
static char s_log[4096];

int32_t oglLoad(void) { return 1; }
const char *oglLoadMissing(void) { return ""; }
void oglUnload(void) {}
#endif

int32_t oglGetInteger(int32_t name) {
	GLint value = 0;
	glGetIntegerv((GLenum)name, &value);
	return value;
}

int32_t oglGetError(void) { return (int32_t)glGetError(); }
void oglEnable(int32_t capability) { glEnable((GLenum)capability); }
void oglDisable(int32_t capability) { glDisable((GLenum)capability); }
void oglPixelStore(int32_t name, int32_t value) { glPixelStorei((GLenum)name, value); }
void *oglTextureNative(uint32_t texture) { return (void *)(uintptr_t)texture; }

void oglCopyBytes(void *destination, int64_t destinationOffset, void *source, int64_t bytes) {
	memcpy((uint8_t *)destination + destinationOffset, source, (size_t)bytes);
}

uint32_t oglCreateVertexArray(void) {
	GLuint vertexArray = 0;
	glGenVertexArrays(1, &vertexArray);
	return vertexArray;
}

void oglBindVertexArray(uint32_t vertexArray) { glBindVertexArray(vertexArray); }
void oglDeleteVertexArray(uint32_t vertexArray) { if (vertexArray) glDeleteVertexArrays(1, &vertexArray); }

uint32_t oglCreateBuffer(void) {
	GLuint buffer = 0;
	glGenBuffers(1, &buffer);
	return buffer;
}

void oglBindBuffer(int32_t target, uint32_t buffer) { glBindBuffer((GLenum)target, buffer); }
void oglBufferData(int32_t target, int64_t bytes, int32_t usage) { glBufferData((GLenum)target, (GLsizeiptr)bytes, NULL, (GLenum)usage); }

void oglBufferSubData(int32_t target, int64_t offset, void *data, int64_t bytes) {
	glBufferSubData((GLenum)target, (GLintptr)offset, (GLsizeiptr)bytes, data);
}

void oglDeleteBuffer(uint32_t buffer) { if (buffer) glDeleteBuffers(1, &buffer); }

void oglCopyBufferDataUncached(uint32_t source, int64_t sourceOffset, uint32_t destination, int64_t destinationOffset, int64_t bytes) {
	glBindBuffer(GL_COPY_READ_BUFFER, source);
	glBindBuffer(GL_COPY_WRITE_BUFFER, destination);
	glCopyBufferSubData(GL_COPY_READ_BUFFER, GL_COPY_WRITE_BUFFER, (GLintptr)sourceOffset, (GLintptr)destinationOffset, (GLsizeiptr)bytes);
	glBindBuffer(GL_COPY_READ_BUFFER, 0);
	glBindBuffer(GL_COPY_WRITE_BUFFER, 0);
}

int32_t oglGetBufferDataUncached(uint32_t buffer, int64_t offset, void *destination, int64_t bytes) {
	int32_t read = 1;
	glBindBuffer(GL_COPY_READ_BUFFER, buffer);
#if defined(OGL_GLES) && !defined(__EMSCRIPTEN__)
	const void *mapped = glMapBufferRange(GL_COPY_READ_BUFFER, (GLintptr)offset, (GLsizeiptr)bytes, GL_MAP_READ_BIT);
	if (mapped == NULL) {
		read = 0;
	} else {
		memcpy(destination, mapped, (size_t)bytes);
		glUnmapBuffer(GL_COPY_READ_BUFFER);
	}
#else
	glGetBufferSubData(GL_COPY_READ_BUFFER, (GLintptr)offset, (GLsizeiptr)bytes, destination);
#endif
	glBindBuffer(GL_COPY_READ_BUFFER, 0);
	return read;
}

uint32_t oglCreateTexture(void) {
	GLuint texture = 0;
	glGenTextures(1, &texture);
	return texture;
}

void oglActiveTexture(int32_t unit) { glActiveTexture((GLenum)(GL_TEXTURE0 + unit)); }
void oglBindTexture(int32_t target, uint32_t texture) { glBindTexture((GLenum)target, texture); }

void oglTexStorage(int32_t target, int32_t levels, int32_t internalFormat, int32_t width, int32_t height, int32_t depth) {
	if (target == GL_TEXTURE_3D || target == GL_TEXTURE_2D_ARRAY) {
		glTexStorage3D((GLenum)target, levels, (GLenum)internalFormat, width, height, depth);
	} else {
		glTexStorage2D((GLenum)target, levels, (GLenum)internalFormat, width, height);
	}
}

void oglTexParameteri(int32_t target, int32_t name, int32_t value) { glTexParameteri((GLenum)target, (GLenum)name, value); }

#if !defined(OGL_GLES)
void oglTexStorage2DMultisample(int32_t target, int32_t samples, int32_t internalFormat, int32_t width, int32_t height) {
	glTexStorage2DMultisample((GLenum)target, samples, (GLenum)internalFormat, width, height, GL_TRUE);
}
#endif

uint32_t oglCreateRenderbufferUncached(int32_t samples, int32_t internalFormat, int32_t width, int32_t height) {
	GLuint renderbuffer = 0;
	glGenRenderbuffers(1, &renderbuffer);
	glBindRenderbuffer(GL_RENDERBUFFER, renderbuffer);
	glRenderbufferStorageMultisample(GL_RENDERBUFFER, samples, (GLenum)internalFormat, width, height);
	glBindRenderbuffer(GL_RENDERBUFFER, 0);
	return renderbuffer;
}

void oglDeleteRenderbuffer(uint32_t renderbuffer) { if (renderbuffer) glDeleteRenderbuffers(1, &renderbuffer); }

void oglFramebufferRenderbuffer(int32_t attachment, uint32_t renderbuffer) {
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, (GLenum)attachment, GL_RENDERBUFFER, renderbuffer);
}

static void texSubImage(
	int32_t target,
	int32_t level,
	int32_t x,
	int32_t y,
	int32_t z,
	int32_t width,
	int32_t height,
	int32_t depth,
	int32_t format,
	int32_t type,
	const void *pixels) {
	if (target == GL_TEXTURE_3D || target == GL_TEXTURE_2D_ARRAY) {
		glTexSubImage3D((GLenum)target, level, x, y, z, width, height, depth, (GLenum)format, (GLenum)type, pixels);
	} else {
		glTexSubImage2D((GLenum)target, level, x, y, width, height, (GLenum)format, (GLenum)type, pixels);
	}
}

void oglTexSubImage(
	int32_t target,
	int32_t level,
	int32_t x,
	int32_t y,
	int32_t z,
	int32_t width,
	int32_t height,
	int32_t depth,
	int32_t format,
	int32_t type,
	void *data,
	int64_t offset) {
	texSubImage(target, level, x, y, z, width, height, depth, format, type, (const uint8_t *)data + offset);
}

void oglTexSubImageFromBufferUncached(
	int32_t target,
	int32_t level,
	int32_t x,
	int32_t y,
	int32_t z,
	int32_t width,
	int32_t height,
	int32_t depth,
	int32_t format,
	int32_t type,
	uint32_t buffer,
	int64_t offset) {
	glBindBuffer(GL_PIXEL_UNPACK_BUFFER, buffer);
	texSubImage(target, level, x, y, z, width, height, depth, format, type, (const void *)(intptr_t)offset);
	glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
}

void oglDeleteTexture(uint32_t texture) { if (texture) glDeleteTextures(1, &texture); }

uint32_t oglCreateSampler(void) {
	GLuint sampler = 0;
	glGenSamplers(1, &sampler);
	return sampler;
}

void oglSamplerParameteri(uint32_t sampler, int32_t name, int32_t value) { glSamplerParameteri(sampler, (GLenum)name, value); }
void oglSamplerParameterf(uint32_t sampler, int32_t name, double value) { glSamplerParameterf(sampler, (GLenum)name, (GLfloat)value); }

#if !defined(OGL_GLES)
void oglSamplerBorderColor(uint32_t sampler, double r, double g, double b, double a) {
	const GLfloat border[4] = { (GLfloat)r, (GLfloat)g, (GLfloat)b, (GLfloat)a };
	glSamplerParameterfv(sampler, GL_TEXTURE_BORDER_COLOR, border);
}
#endif

void oglBindSampler(int32_t unit, uint32_t sampler) { glBindSampler((GLuint)unit, sampler); }
void oglDeleteSampler(uint32_t sampler) { if (sampler) glDeleteSamplers(1, &sampler); }

uint32_t oglCompileShader(int32_t stage, const char *source) {
	s_log[0] = 0;
	GLuint shader = glCreateShader((GLenum)stage);
	glShaderSource(shader, 1, &source, NULL);
	glCompileShader(shader);
	GLint status = 0;
	glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
	if (!status) {
		glGetShaderInfoLog(shader, (GLsizei)sizeof s_log, NULL, s_log);
		glDeleteShader(shader);
		return 0;
	}
	return shader;
}

uint32_t oglLinkProgram(uint32_t vertexShader, uint32_t fragmentShader) {
	s_log[0] = 0;
	GLuint program = glCreateProgram();
	glAttachShader(program, vertexShader);
	glAttachShader(program, fragmentShader);
	glLinkProgram(program);
	glDeleteShader(vertexShader);
	glDeleteShader(fragmentShader);
	GLint status = 0;
	glGetProgramiv(program, GL_LINK_STATUS, &status);
	if (!status) {
		glGetProgramInfoLog(program, (GLsizei)sizeof s_log, NULL, s_log);
		glDeleteProgram(program);
		return 0;
	}
	return program;
}

const char *oglLog(void) { return s_log; }
void oglDeleteProgram(uint32_t program) { if (program) glDeleteProgram(program); }
void oglUseProgram(uint32_t program) { glUseProgram(program); }
int32_t oglUniformLocation(uint32_t program, const char *name) { return glGetUniformLocation(program, name); }
int32_t oglAttribLocation(uint32_t program, const char *name) { return glGetAttribLocation(program, name); }
void oglUniform1i(int32_t location, int32_t value) { glUniform1i(location, value); }

void oglUniform4fv(int32_t location, int32_t count, void *data, int64_t offset) {
	glUniform4fv(location, count, (const GLfloat *)((const uint8_t *)data + offset));
}

void oglDepthFunc(int32_t compare) { glDepthFunc((GLenum)compare); }
void oglDepthMask(int32_t write) { glDepthMask(write ? GL_TRUE : GL_FALSE); }
void oglStencilMask(int32_t mask) { glStencilMask((GLuint)mask); }
void oglStencilFunc(int32_t compare, int32_t reference, int32_t mask) { glStencilFunc((GLenum)compare, reference, (GLuint)mask); }
void oglStencilOp(int32_t fail, int32_t depthFail, int32_t pass) { glStencilOp((GLenum)fail, (GLenum)depthFail, (GLenum)pass); }

void oglStencilFuncSeparate(int32_t face, int32_t compare, int32_t reference, int32_t mask) {
	glStencilFuncSeparate((GLenum)face, (GLenum)compare, reference, (GLuint)mask);
}

void oglStencilOpSeparate(int32_t face, int32_t fail, int32_t depthFail, int32_t pass) {
	glStencilOpSeparate((GLenum)face, (GLenum)fail, (GLenum)depthFail, (GLenum)pass);
}

void oglDepthRange(double nearDepth, double farDepth) {
#if defined(OGL_GLES)
	glDepthRangef((GLfloat)nearDepth, (GLfloat)farDepth);
#else
	glDepthRange(nearDepth, farDepth);
#endif
}

void oglBlendFuncSeparate(int32_t sourceColor, int32_t destinationColor, int32_t sourceAlpha, int32_t destinationAlpha) {
	glBlendFuncSeparate((GLenum)sourceColor, (GLenum)destinationColor, (GLenum)sourceAlpha, (GLenum)destinationAlpha);
}

void oglBlendEquationSeparate(int32_t color, int32_t alpha) { glBlendEquationSeparate((GLenum)color, (GLenum)alpha); }

#if !defined(OGL_GLES)
void oglEnablei(int32_t capability, int32_t index) { glEnablei((GLenum)capability, (GLuint)index); }
void oglDisablei(int32_t capability, int32_t index) { glDisablei((GLenum)capability, (GLuint)index); }

void oglBlendFuncSeparatei(int32_t index, int32_t sourceColor, int32_t destinationColor, int32_t sourceAlpha, int32_t destinationAlpha) {
	glBlendFuncSeparatei((GLuint)index, (GLenum)sourceColor, (GLenum)destinationColor, (GLenum)sourceAlpha, (GLenum)destinationAlpha);
}

void oglBlendEquationSeparatei(int32_t index, int32_t color, int32_t alpha) {
	glBlendEquationSeparatei((GLuint)index, (GLenum)color, (GLenum)alpha);
}
#endif
void oglBlendColor(double r, double g, double b, double a) { glBlendColor((GLfloat)r, (GLfloat)g, (GLfloat)b, (GLfloat)a); }

void oglColorMask(int32_t mask) {
	glColorMask((mask & 1) != 0, (mask & 2) != 0, (mask & 4) != 0, (mask & 8) != 0);
}

#if !defined(OGL_GLES)
void oglColorMaski(int32_t index, int32_t mask) {
	glColorMaski((GLuint)index, (mask & 1) != 0, (mask & 2) != 0, (mask & 4) != 0, (mask & 8) != 0);
}
#endif

void oglPolygonOffset(double factor, double units) { glPolygonOffset((GLfloat)factor, (GLfloat)units); }
void oglCullFace(int32_t face) { glCullFace((GLenum)face); }
void oglFrontFace(int32_t winding) { glFrontFace((GLenum)winding); }
void oglViewport(int32_t x, int32_t y, int32_t width, int32_t height) { glViewport(x, y, width, height); }
void oglScissor(int32_t x, int32_t y, int32_t width, int32_t height) { glScissor(x, y, width, height); }

uint32_t oglCreateFramebuffer(void) {
	GLuint framebuffer = 0;
	glGenFramebuffers(1, &framebuffer);
	return framebuffer;
}

void oglBindFramebuffer(int32_t target, uint32_t framebuffer) { glBindFramebuffer((GLenum)target, framebuffer); }
void oglDeleteFramebuffer(uint32_t framebuffer) { if (framebuffer) glDeleteFramebuffers(1, &framebuffer); }

void oglFramebufferTexture2D(int32_t attachment, int32_t textureTarget, uint32_t texture, int32_t level) {
	glFramebufferTexture2D(GL_FRAMEBUFFER, (GLenum)attachment, (GLenum)textureTarget, texture, level);
}

void oglFramebufferTextureLayer(int32_t attachment, uint32_t texture, int32_t level, int32_t layer) {
	glFramebufferTextureLayer(GL_FRAMEBUFFER, (GLenum)attachment, texture, level, layer);
}

void oglFramebufferDetach(int32_t attachment) {
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, (GLenum)attachment, GL_RENDERBUFFER, 0);
	glFramebufferTexture2D(GL_FRAMEBUFFER, (GLenum)attachment, GL_TEXTURE_2D, 0, 0);
}

int32_t oglCheckFramebufferStatus(void) { return (int32_t)glCheckFramebufferStatus(GL_FRAMEBUFFER); }

void oglDrawBuffers(int32_t count, int32_t colorMask) {
	GLenum buffers[8];
	if (count > 8) count = 8;
	for (int32_t i = 0; i < count; i++) {
		buffers[i] = (colorMask & (1 << i)) ? (GLenum)(GL_COLOR_ATTACHMENT0 + i) : GL_NONE;
	}
	glDrawBuffers(count, buffers);
}

static void attachTexel(uint32_t texture, int32_t target, int32_t level, int32_t layer, GLenum attachment) {
	if (target == GL_TEXTURE_2D) {
		glFramebufferTexture2D(GL_READ_FRAMEBUFFER, attachment, GL_TEXTURE_2D, texture, level);
	} else if (target == GL_TEXTURE_CUBE_MAP) {
		glFramebufferTexture2D(GL_READ_FRAMEBUFFER, attachment, (GLenum)(GL_TEXTURE_CUBE_MAP_POSITIVE_X + layer), texture, level);
	} else {
		glFramebufferTextureLayer(GL_READ_FRAMEBUFFER, attachment, texture, level, layer);
	}
}

static void beginTexelRead(uint32_t readFramebuffer, uint32_t texture, int32_t target, int32_t level, int32_t layer, GLenum attachment, GLint *previous) {
	glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, previous);
	glBindFramebuffer(GL_READ_FRAMEBUFFER, readFramebuffer);
	attachTexel(texture, target, level, layer, attachment);
	glReadBuffer(attachment == GL_COLOR_ATTACHMENT0 ? GL_COLOR_ATTACHMENT0 : GL_NONE);
}

static void endTexelRead(GLenum attachment, GLint previous) {
	glFramebufferTexture2D(GL_READ_FRAMEBUFFER, attachment, GL_TEXTURE_2D, 0, 0);
	glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)previous);
}

int32_t oglReadTexelsToBufferUncached(
	uint32_t readFramebuffer,
	uint32_t texture,
	int32_t target,
	int32_t level,
	int32_t layer,
	int32_t x,
	int32_t y,
	int32_t width,
	int32_t height,
	int32_t format,
	int32_t type,
	int32_t rowLength,
	uint32_t buffer,
	int64_t offset) {
	GLint previous = 0;
	GLenum attachment = format == GL_DEPTH_COMPONENT ? GL_DEPTH_ATTACHMENT : GL_COLOR_ATTACHMENT0;
	beginTexelRead(readFramebuffer, texture, target, level, layer, attachment, &previous);
	int32_t result = 1;
	if (glCheckFramebufferStatus(GL_READ_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
		result = 0;
	} else {
		glPixelStorei(GL_PACK_ALIGNMENT, 1);
		glPixelStorei(GL_PACK_ROW_LENGTH, rowLength);
		glBindBuffer(GL_PIXEL_PACK_BUFFER, buffer);
		while (glGetError() != GL_NO_ERROR) {}
		glReadPixels(x, y, width, height, (GLenum)format, (GLenum)type, (void *)(intptr_t)offset);
		if (glGetError() != GL_NO_ERROR) result = -1;
		glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
		glPixelStorei(GL_PACK_ROW_LENGTH, 0);
		glPixelStorei(GL_PACK_ALIGNMENT, 4);
	}
	endTexelRead(attachment, previous);
	return result;
}

int32_t oglReadScreenRectUncached(int32_t x, int32_t y, int32_t width, int32_t height, int32_t format, int32_t type, int32_t rowLength, uint32_t buffer, int64_t offset) {
	GLint previous = 0;
	glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &previous);
	glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);
	glReadBuffer(GL_BACK);
	glPixelStorei(GL_PACK_ALIGNMENT, 1);
	glPixelStorei(GL_PACK_ROW_LENGTH, rowLength);
	glBindBuffer(GL_PIXEL_PACK_BUFFER, buffer);
	while (glGetError() != GL_NO_ERROR) {}
	glReadPixels(x, y, width, height, (GLenum)format, (GLenum)type, (void *)(intptr_t)offset);
	int32_t result = glGetError() == GL_NO_ERROR ? 1 : 0;
	glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
	glPixelStorei(GL_PACK_ROW_LENGTH, 0);
	glPixelStorei(GL_PACK_ALIGNMENT, 4);
	glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)previous);
	return result;
}

int32_t oglCopyTexels(
	uint32_t readFramebuffer,
	uint32_t source,
	int32_t sourceTarget,
	int32_t sourceLevel,
	int32_t sourceLayer,
	int32_t sourceX,
	int32_t sourceY,
	int32_t destinationTarget,
	int32_t destinationLevel,
	int32_t destinationX,
	int32_t destinationY,
	int32_t destinationLayer,
	int32_t width,
	int32_t height,
	int32_t count) {
	GLint previous = 0;
	beginTexelRead(readFramebuffer, source, sourceTarget, sourceLevel, sourceLayer, GL_COLOR_ATTACHMENT0, &previous);
	int32_t result = 1;
	if (glCheckFramebufferStatus(GL_READ_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
		result = 0;
	} else {
		while (glGetError() != GL_NO_ERROR) {}
		for (int32_t i = 0; i < count && result == 1; i++) {
			if (i > 0) attachTexel(source, sourceTarget, sourceLevel, sourceLayer + i, GL_COLOR_ATTACHMENT0);
			if (destinationTarget == GL_TEXTURE_2D) {
				glCopyTexSubImage2D(GL_TEXTURE_2D, destinationLevel, destinationX, destinationY, sourceX, sourceY, width, height);
			} else if (destinationTarget == GL_TEXTURE_CUBE_MAP) {
				glCopyTexSubImage2D((GLenum)(GL_TEXTURE_CUBE_MAP_POSITIVE_X + destinationLayer + i), destinationLevel, destinationX, destinationY, sourceX, sourceY, width, height);
			} else {
				glCopyTexSubImage3D((GLenum)destinationTarget, destinationLevel, destinationX, destinationY, destinationLayer + i, sourceX, sourceY, width, height);
			}
			if (glGetError() != GL_NO_ERROR) result = -1;
		}
	}
	endTexelRead(GL_COLOR_ATTACHMENT0, previous);
	return result;
}

void oglReadBuffer(int32_t attachment) { glReadBuffer((GLenum)attachment); }

void oglBlitColor(int32_t width, int32_t height) {
	glBlitFramebuffer(0, 0, width, height, 0, 0, width, height, GL_COLOR_BUFFER_BIT, GL_NEAREST);
}

void oglClearColor(int32_t attachment, double r, double g, double b, double a) {
	const GLfloat color[4] = { (GLfloat)r, (GLfloat)g, (GLfloat)b, (GLfloat)a };
	glClearBufferfv(GL_COLOR, attachment, color);
}

void oglClearDepth(double depth) {
	const GLfloat value = (GLfloat)depth;
	glClearBufferfv(GL_DEPTH, 0, &value);
}

void oglClearDepthStencil(double depth, int32_t stencil) { glClearBufferfi(GL_DEPTH_STENCIL, 0, (GLfloat)depth, stencil); }

void oglVertexAttribPointer(int32_t index, int32_t size, int32_t type, int32_t normalized, int32_t stride, int64_t offset) {
	glVertexAttribPointer((GLuint)index, size, (GLenum)type, normalized ? GL_TRUE : GL_FALSE, stride, (const void *)(intptr_t)offset);
}

void oglVertexAttribIPointer(int32_t index, int32_t size, int32_t type, int32_t stride, int64_t offset) {
	glVertexAttribIPointer((GLuint)index, size, (GLenum)type, stride, (const void *)(intptr_t)offset);
}

void oglVertexAttribDivisor(int32_t index, int32_t divisor) { glVertexAttribDivisor((GLuint)index, (GLuint)divisor); }
void oglEnableVertexAttribArray(int32_t index) { glEnableVertexAttribArray((GLuint)index); }
void oglDisableVertexAttribArray(int32_t index) { glDisableVertexAttribArray((GLuint)index); }

void oglDrawArrays(int32_t mode, int32_t first, int32_t count) { glDrawArrays((GLenum)mode, first, count); }

void oglDrawArraysInstanced(int32_t mode, int32_t first, int32_t count, int32_t instances) {
	glDrawArraysInstanced((GLenum)mode, first, count, instances);
}

#if !defined(OGL_GLES)
void oglDrawArraysInstancedBaseInstance(int32_t mode, int32_t first, int32_t count, int32_t instances, int32_t baseInstance) {
	glDrawArraysInstancedBaseInstance((GLenum)mode, first, count, instances, (GLuint)baseInstance);
}

#endif

void oglDrawElements(int32_t mode, int32_t count, int32_t type, int64_t offset) {
	glDrawElements((GLenum)mode, count, (GLenum)type, (const void *)(intptr_t)offset);
}

#if !defined(OGL_GLES)
void oglDrawElementsBaseVertex(int32_t mode, int32_t count, int32_t type, int64_t offset, int32_t baseVertex) {
	glDrawElementsBaseVertex((GLenum)mode, count, (GLenum)type, (const void *)(intptr_t)offset, baseVertex);
}

#endif

void oglDrawElementsInstanced(int32_t mode, int32_t count, int32_t type, int64_t offset, int32_t instances) {
	glDrawElementsInstanced((GLenum)mode, count, (GLenum)type, (const void *)(intptr_t)offset, instances);
}

#if !defined(OGL_GLES)
void oglDrawElementsInstancedBaseVertex(int32_t mode, int32_t count, int32_t type, int64_t offset, int32_t instances, int32_t baseVertex) {
	glDrawElementsInstancedBaseVertex((GLenum)mode, count, (GLenum)type, (const void *)(intptr_t)offset, instances, baseVertex);
}

void oglDrawElementsInstancedBaseVertexBaseInstance(
	int32_t mode,
	int32_t count,
	int32_t type,
	int64_t offset,
	int32_t instances,
	int32_t baseVertex,
	int32_t baseInstance) {
	glDrawElementsInstancedBaseVertexBaseInstance((GLenum)mode, count, (GLenum)type, (const void *)(intptr_t)offset,
		instances, baseVertex, (GLuint)baseInstance);
}
#endif


int32_t oglCapabilities(void) {
	int32_t caps = 0;
#if defined(OGL_COMPUTE)
	caps |= OGL_CAPABILITY_COMPUTE;
#endif
#if defined(OGL_DEBUG)
	caps |= OGL_CAPABILITY_DEBUG;
#endif
#if defined(OGL_TIMER)
	caps |= OGL_CAPABILITY_TIMER;
#endif
#if !defined(OGL_GLES)
	caps |= OGL_CAPABILITY_EXACT_SAMPLES;
#endif
	return caps;
}

#if !defined(OGL_COMPUTE) || !defined(OGL_DEBUG) || !defined(OGL_TIMER)
static void unavailable(const char *what) {
	fprintf(stderr, "webgpu gl: %s is not built into this GL target; the backend checks oglCapabilities before it calls\n", what);
	abort();
}
#endif

int64_t oglGetInteger64(int32_t name) {
	GLint64 value = 0;
	glGetInteger64v((GLenum)name, &value);
	return (int64_t)value;
}

int32_t oglHasExtension(const char *name) {
	GLint count = 0;
	glGetIntegerv(GL_NUM_EXTENSIONS, &count);
	for (GLint i = 0; i < count; i++) {
		const char *extension = (const char *)glGetStringi(GL_EXTENSIONS, (GLuint)i);
		if (extension != NULL && strcmp(extension, name) == 0) return 1;
	}
	return 0;
}

#if defined(OGL_COMPUTE)
int32_t oglGetIntegeri(int32_t name, int32_t index) {
	GLint value = 0;
	glGetIntegeri_v((GLenum)name, (GLuint)index, &value);
	return value;
}

uint32_t oglLinkComputeProgram(uint32_t computeShader) {
	s_log[0] = 0;
	GLuint program = glCreateProgram();
	glAttachShader(program, computeShader);
	glLinkProgram(program);
	glDeleteShader(computeShader);
	GLint status = 0;
	glGetProgramiv(program, GL_LINK_STATUS, &status);
	if (!status) {
		glGetProgramInfoLog(program, (GLsizei)sizeof s_log, NULL, s_log);
		glDeleteProgram(program);
		return 0;
	}
	return program;
}

void oglDispatchCompute(int32_t x, int32_t y, int32_t z) { glDispatchCompute((GLuint)x, (GLuint)y, (GLuint)z); }

void oglDispatchComputeIndirectUncached(uint32_t buffer, int64_t offset) {
	glBindBuffer(GL_DISPATCH_INDIRECT_BUFFER, buffer);
	glDispatchComputeIndirect((GLintptr)offset);
	glBindBuffer(GL_DISPATCH_INDIRECT_BUFFER, 0);
}

void oglMemoryBarrier(int32_t barriers) { glMemoryBarrier((GLbitfield)barriers); }

void oglBindBufferRange(int32_t target, uint32_t index, uint32_t buffer, int64_t offset, int64_t bytes) {
	glBindBufferRange((GLenum)target, index, buffer, (GLintptr)offset, (GLsizeiptr)bytes);
}

void oglBindImageTexture(int32_t unit, uint32_t texture, int32_t level, int32_t layered, int32_t layer, int32_t access, int32_t format) {
	glBindImageTexture((GLuint)unit, texture, level, layered ? GL_TRUE : GL_FALSE, layer, (GLenum)access, (GLenum)format);
}
#else
int32_t oglGetIntegeri(int32_t name, int32_t index) { unavailable("glGetIntegeri_v"); return 0; }
uint32_t oglLinkComputeProgram(uint32_t computeShader) { unavailable("compute shaders"); return 0; }
void oglDispatchCompute(int32_t x, int32_t y, int32_t z) { unavailable("glDispatchCompute"); }
void oglDispatchComputeIndirectUncached(uint32_t buffer, int64_t offset) { unavailable("glDispatchComputeIndirect"); }
void oglMemoryBarrier(int32_t barriers) { unavailable("glMemoryBarrier"); }
void oglBindBufferRange(int32_t target, uint32_t index, uint32_t buffer, int64_t offset, int64_t bytes) { unavailable("glBindBufferRange"); }
void oglBindImageTexture(int32_t unit, uint32_t texture, int32_t level, int32_t layered, int32_t layer, int32_t access, int32_t format) {
	unavailable("glBindImageTexture");
}
#endif

uint32_t oglCreateQuery(void) {
	GLuint query = 0;
	glGenQueries(1, &query);
	return query;
}

void oglDeleteQuery(uint32_t query) { if (query) glDeleteQueries(1, &query); }
void oglBeginQuery(int32_t target, uint32_t query) { glBeginQuery((GLenum)target, query); }
void oglEndQuery(int32_t target) { glEndQuery((GLenum)target); }

int32_t oglQueryAvailable(uint32_t query) {
	GLuint available = 0;
	glGetQueryObjectuiv(query, GL_QUERY_RESULT_AVAILABLE, &available);
	return available != 0;
}

uint64_t oglQueryResult(uint32_t query) {
#if defined(OGL_GLES)
	GLuint result = 0;
	glGetQueryObjectuiv(query, GL_QUERY_RESULT, &result);
	return (uint64_t)result;
#else
	GLuint64 result = 0;
	glGetQueryObjectui64v(query, GL_QUERY_RESULT, &result);
	return (uint64_t)result;
#endif
}

#if defined(OGL_TIMER)
void oglQueryCounter(uint32_t query) { glQueryCounter(query, GL_TIMESTAMP); }

int32_t oglQueryCounterBits(void) {
	GLint bits = 0;
	glGetQueryiv(GL_TIMESTAMP, GL_QUERY_COUNTER_BITS, &bits);
	return bits;
}
#else
void oglQueryCounter(uint32_t query) { unavailable("glQueryCounter"); }
int32_t oglQueryCounterBits(void) { unavailable("glGetQueryiv(GL_TIMESTAMP)"); return 0; }
#endif

#if defined(OGL_DEBUG)
void oglPushDebugGroup(const char *label) { glPushDebugGroup(GL_DEBUG_SOURCE_APPLICATION, 0, -1, label); }
void oglPopDebugGroup(void) { glPopDebugGroup(); }

void oglDebugMarker(const char *label) {
	glDebugMessageInsert(GL_DEBUG_SOURCE_APPLICATION, GL_DEBUG_TYPE_MARKER, 0, GL_DEBUG_SEVERITY_NOTIFICATION, -1, label);
}

void oglObjectLabel(int32_t identifier, uint32_t name, const char *label) { glObjectLabel((GLenum)identifier, name, -1, label); }
#else
void oglPushDebugGroup(const char *label) { unavailable("glPushDebugGroup"); }
void oglPopDebugGroup(void) { unavailable("glPopDebugGroup"); }
void oglDebugMarker(const char *label) { unavailable("glDebugMessageInsert"); }
void oglObjectLabel(int32_t identifier, uint32_t name, const char *label) { unavailable("glObjectLabel"); }
#endif

typedef struct { const char *name; int32_t value; } DriverConstant;

#define DRIVER(name) { #name, (int32_t)(name) }

static const DriverConstant driverConstants[] = {
	DRIVER(OGL_CAPABILITY_COMPUTE),
	DRIVER(OGL_CAPABILITY_DEBUG),
	DRIVER(OGL_CAPABILITY_TIMER),
	DRIVER(OGL_CAPABILITY_EXACT_SAMPLES),
	DRIVER(GL_TEXTURE_3D),
	DRIVER(GL_TEXTURE_2D_ARRAY),
	DRIVER(GL_TEXTURE_CUBE_MAP),
	DRIVER(GL_TEXTURE_CUBE_MAP_POSITIVE_X),
	DRIVER(GL_BACK),
	DRIVER(GL_TEXTURE_2D),
	DRIVER(GL_RENDERBUFFER),
	DRIVER(GL_DEPTH_COMPONENT),
	DRIVER(GL_DEPTH_STENCIL),
	DRIVER(GL_UNPACK_ROW_LENGTH),
	DRIVER(GL_UNPACK_IMAGE_HEIGHT),
	DRIVER(GL_NEAREST),
	DRIVER(GL_FRAMEBUFFER),
	DRIVER(GL_READ_FRAMEBUFFER),
	DRIVER(GL_DRAW_FRAMEBUFFER),
	DRIVER(GL_COLOR_ATTACHMENT0),
	DRIVER(GL_DEPTH_ATTACHMENT),
	DRIVER(GL_FRAMEBUFFER_COMPLETE),
};

static char s_constantsDisagreement[256];

const char *oglConstantsDisagreement(const int32_t *values, int32_t count) {
	int32_t known = (int32_t)(sizeof driverConstants / sizeof driverConstants[0]);
	s_constantsDisagreement[0] = 0;
	if (count != known) {
		snprintf(s_constantsDisagreement, sizeof s_constantsDisagreement, "backend.ms lists %d constants and gl.c checks %d", (int)count, (int)known);
		return s_constantsDisagreement;
	}
	for (int32_t i = 0; i < known; i++) {
		if (values[i] == driverConstants[i].value) continue;
		snprintf(s_constantsDisagreement, sizeof s_constantsDisagreement, "entry %d: %s is %d in gl.c and %d in backend.ms",
			(int)i, driverConstants[i].name, (int)driverConstants[i].value, (int)values[i]);
		break;
	}
	return s_constantsDisagreement;
}
