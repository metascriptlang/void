#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "gl.h"

#if defined(__EMSCRIPTEN__) || defined(__ANDROID__)
#define OGL_GLES 1
#include <GLES3/gl3.h>
#elif defined(__linux__)
#define GL_GLEXT_PROTOTYPES
#include <GL/gl.h>
#elif !defined(_WIN32)
#error "the GL backend loads GL through WGL, links libGL on Linux or takes GLES3 from emscripten or Android; another platform needs its GL headers and loader here"
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
typedef unsigned int GLbitfield;
typedef float GLfloat;
typedef int GLint;

#define GL_NO_ERROR 0
#define GL_TRUE 1
#define GL_FALSE 0
#define GL_NONE 0
#define GL_NEAREST 0x2600
#define GL_COLOR 0x1800
#define GL_DEPTH 0x1801
#define GL_DEPTH_STENCIL 0x84F9
#define GL_COLOR_BUFFER_BIT 0x00004000
#define GL_FRAMEBUFFER 0x8D40
#define GL_READ_FRAMEBUFFER 0x8CA8
#define GL_DRAW_FRAMEBUFFER 0x8CA9
#define GL_RENDERBUFFER 0x8D41
#define GL_TEXTURE_2D 0x0DE1
#define GL_TEXTURE0 0x84C0
#define GL_COLOR_ATTACHMENT0 0x8CE0
#define GL_TEXTURE_BORDER_COLOR 0x1004
#define GL_UNPACK_ROW_LENGTH 0x0CF2
#define GL_COMPILE_STATUS 0x8B81
#define GL_LINK_STATUS 0x8B82
#define GL_INFO_LOG_LENGTH 0x8B84

#define OGL_FUNCS \
	OGL_XMACRO(glGetError,                 GLenum, (void)) \
	OGL_XMACRO(glGetIntegerv,              void, (GLenum pname, GLint *data)) \
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
	OGL_XMACRO(glGenTextures,              void, (GLsizei n, GLuint *textures)) \
	OGL_XMACRO(glActiveTexture,            void, (GLenum texture)) \
	OGL_XMACRO(glBindTexture,              void, (GLenum target, GLuint texture)) \
	OGL_XMACRO(glTexStorage2D,             void, (GLenum target, GLsizei levels, GLenum internalformat, GLsizei width, GLsizei height)) \
	OGL_XMACRO(glTexStorage2DMultisample,  void, (GLenum target, GLsizei samples, GLenum internalformat, GLsizei width, GLsizei height, GLboolean fixedsamplelocations)) \
	OGL_XMACRO(glTexSubImage2D,            void, (GLenum target, GLint level, GLint xoffset, GLint yoffset, GLsizei width, GLsizei height, GLenum format, GLenum type, const void *pixels)) \
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
	OGL_XMACRO(glFramebufferRenderbuffer,  void, (GLenum target, GLenum attachment, GLenum renderbuffertarget, GLuint renderbuffer)) 	OGL_XMACRO(glGenRenderbuffers,         void, (GLsizei n, GLuint *renderbuffers)) 	OGL_XMACRO(glBindRenderbuffer,         void, (GLenum target, GLuint renderbuffer)) 	OGL_XMACRO(glRenderbufferStorageMultisample, void, (GLenum target, GLsizei samples, GLenum internalformat, GLsizei width, GLsizei height)) 	OGL_XMACRO(glDeleteRenderbuffers,      void, (GLsizei n, const GLuint *renderbuffers)) \
	OGL_XMACRO(glCheckFramebufferStatus,   GLenum, (GLenum target)) \
	OGL_XMACRO(glDrawBuffers,              void, (GLsizei n, const GLenum *bufs)) \
	OGL_XMACRO(glReadBuffer,               void, (GLenum src)) \
	OGL_XMACRO(glBlitFramebuffer,          void, (GLint srcX0, GLint srcY0, GLint srcX1, GLint srcY1, GLint dstX0, GLint dstY0, GLint dstX1, GLint dstY1, GLbitfield mask, GLenum filter)) \
	OGL_XMACRO(glClearBufferfv,            void, (GLenum buffer, GLint drawbuffer, const GLfloat *value)) \
	OGL_XMACRO(glClearBufferfi,            void, (GLenum buffer, GLint drawbuffer, GLfloat depth, GLint stencil)) \
	OGL_XMACRO(glVertexAttribPointer,      void, (GLuint index, GLint size, GLenum type, GLboolean normalized, GLsizei stride, const void *pointer)) \
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

uint32_t oglCreateTexture(void) {
	GLuint texture = 0;
	glGenTextures(1, &texture);
	return texture;
}

void oglActiveTexture(int32_t unit) { glActiveTexture((GLenum)(GL_TEXTURE0 + unit)); }
void oglBindTexture(int32_t target, uint32_t texture) { glBindTexture((GLenum)target, texture); }

void oglTexStorage2D(int32_t target, int32_t internalFormat, int32_t width, int32_t height) {
	glTexStorage2D((GLenum)target, 1, (GLenum)internalFormat, width, height);
}

#if !defined(OGL_GLES)
void oglTexStorage2DMultisample(int32_t target, int32_t samples, int32_t internalFormat, int32_t width, int32_t height) {
	glTexStorage2DMultisample((GLenum)target, samples, (GLenum)internalFormat, width, height, GL_TRUE);
}
#endif

uint32_t oglCreateRenderbuffer(int32_t samples, int32_t internalFormat, int32_t width, int32_t height) {
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

void oglTexSubImage2D(
	int32_t target,
	int32_t x,
	int32_t y,
	int32_t width,
	int32_t height,
	int32_t format,
	int32_t type,
	void *data,
	int64_t offset,
	int32_t rowLength) {
	glPixelStorei(GL_UNPACK_ROW_LENGTH, rowLength);
	glTexSubImage2D((GLenum)target, 0, x, y, width, height, (GLenum)format, (GLenum)type, (const uint8_t *)data + offset);
	glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
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

void oglBlendFuncSeparate(int32_t sourceColor, int32_t destinationColor, int32_t sourceAlpha, int32_t destinationAlpha) {
	glBlendFuncSeparate((GLenum)sourceColor, (GLenum)destinationColor, (GLenum)sourceAlpha, (GLenum)destinationAlpha);
}

void oglBlendEquationSeparate(int32_t color, int32_t alpha) { glBlendEquationSeparate((GLenum)color, (GLenum)alpha); }
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

void oglFramebufferTexture2D(int32_t attachment, int32_t textureTarget, uint32_t texture) {
	glFramebufferTexture2D(GL_FRAMEBUFFER, (GLenum)attachment, (GLenum)textureTarget, texture, 0);
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
