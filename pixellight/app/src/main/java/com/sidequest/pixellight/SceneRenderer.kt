package com.sidequest.pixellight

import android.opengl.GLES30
import java.nio.ByteBuffer
import java.nio.ByteOrder

class SceneRenderer {

    private var sceneProg = 0
    private var lightProg = 0
    private var blitProg = 0
    private var fbo = 0
    private var fboTex = 0
    private var paramTex = 0
    private var vao = 0
    private var lowW = 0
    private var lowH = 0
    private var vbo = 0
    private var burst = 100
    private var burstDir: java.io.File? = null
    private var surfW = 0
    private var surfH = 0
    private val paramBufs = Array(2) { ByteBuffer.allocateDirect(8 * 4).order(ByteOrder.nativeOrder()).asFloatBuffer() }
    private var ping = 0

    companion object {
        private const val PIXEL_SCALE = 3.5f
        private const val WIGGLE_HZ = 8.0f

        private fun compile(type: Int, src: String): Int {
            val sh = GLES30.glCreateShader(type)
            GLES30.glShaderSource(sh, src)
            GLES30.glCompileShader(sh)
            val ok = IntArray(1)
            GLES30.glGetShaderiv(sh, GLES30.GL_COMPILE_STATUS, ok, 0)
            check(ok[0] != 0) { GLES30.glGetShaderInfoLog(sh) }
            return sh
        }

        private fun link(vsrc: String, fsrc: String): Int {
            val p = GLES30.glCreateProgram()
            GLES30.glAttachShader(p, compile(GLES30.GL_VERTEX_SHADER, vsrc))
            GLES30.glAttachShader(p, compile(GLES30.GL_FRAGMENT_SHADER, fsrc))
            GLES30.glLinkProgram(p)
            val ok = IntArray(1)
            GLES30.glGetProgramiv(p, GLES30.GL_LINK_STATUS, ok, 0)
            check(ok[0] != 0) { GLES30.glGetProgramInfoLog(p) }
            return p
        }

        private fun hash(x: Float): Float {
            val s = Math.sin((x * 91.7).toDouble()).toFloat()
            return ((s * 47453.1453f) % 1.0f + 1.0f) % 1.0f
        }
    }

    fun create() {
        sceneProg = link(VERT, SCENE_FRAG)
        lightProg = link(VERT, LIGHT_FRAG)
        blitProg = link(VERT, BLIT_FRAG)

        for (p in intArrayOf(sceneProg, lightProg)) {
            GLES30.glUseProgram(p)
            GLES30.glUniform1i(GLES30.glGetUniformLocation(p, "uParams"), 0)
        }
        GLES30.glUseProgram(blitProg)
        GLES30.glUniform1i(GLES30.glGetUniformLocation(blitProg, "uTex"), 0)

        val one = IntArray(1)
        GLES30.glGenFramebuffers(1, one, 0)
        fbo = one[0]
        GLES30.glGenTextures(1, one, 0)
        fboTex = one[0]
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, fboTex)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MIN_FILTER, GLES30.GL_NEAREST)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_NEAREST)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_S, GLES30.GL_CLAMP_TO_EDGE)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_T, GLES30.GL_CLAMP_TO_EDGE)

        GLES30.glGenTextures(1, one, 0)
        paramTex = one[0]
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, paramTex)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MIN_FILTER, GLES30.GL_NEAREST)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_NEAREST)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_S, GLES30.GL_CLAMP_TO_EDGE)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_T, GLES30.GL_CLAMP_TO_EDGE)
        GLES30.glTexImage2D(
            GLES30.GL_TEXTURE_2D, 0, GLES30.GL_RGBA32F, 2, 1, 0,
            GLES30.GL_RGBA, GLES30.GL_FLOAT, paramBufs[0]
        )

        GLES30.glGenVertexArrays(1, one, 0)
        vao = one[0]
        GLES30.glBindVertexArray(vao)
        GLES30.glGenBuffers(1, one, 0)
        vbo = one[0]
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, vbo)
        val tri = floatArrayOf(-1.0f, -1.0f, 3.0f, -1.0f, -1.0f, 3.0f)
        val tb = java.nio.ByteBuffer.allocateDirect(24).order(java.nio.ByteOrder.nativeOrder()).asFloatBuffer()
        tb.put(tri).flip()
        GLES30.glBufferData(GLES30.GL_ARRAY_BUFFER, 24, tb, GLES30.GL_STATIC_DRAW)
        GLES30.glEnableVertexAttribArray(0)
        GLES30.glVertexAttribPointer(0, 2, GLES30.GL_FLOAT, false, 0, 0)
    }

    fun resize(w: Int, h: Int) {
        surfW = w
        surfH = h
        lowW = Math.max(1, Math.round(w / PIXEL_SCALE))
        lowH = Math.max(1, Math.round(h / PIXEL_SCALE))
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, fboTex)
        GLES30.glTexImage2D(
            GLES30.GL_TEXTURE_2D, 0, GLES30.GL_RGBA8, lowW, lowH, 0,
            GLES30.GL_RGBA, GLES30.GL_UNSIGNED_BYTE, null
        )
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, fbo)
        GLES30.glFramebufferTexture2D(
            GLES30.GL_FRAMEBUFFER, GLES30.GL_COLOR_ATTACHMENT0,
            GLES30.GL_TEXTURE_2D, fboTex, 0
        )
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, 0)
    }
    fun burstTo(dir: java.io.File) {
        burstDir = dir
        burst = 0
    }

    fun draw(tSec: Float) {
        val tick = Math.floor(tSec * WIGGLE_HZ.toDouble()).toFloat()
        val h1 = hash(tick)
        val h2 = hash(tick + 101.0f)
        val h3 = hash(tick + 202.0f)
        val h4 = hash(tick + 303.0f)

        val intensity = 0.85f + 0.35f * h1
        val radius = 0.135f + 0.010f * (h2 - 0.5f) * 2.0f
        val baseX = 0.21f * lowW
        val baseY = 0.36f * lowH
        val wigX = Math.round((h3 - 0.5f) * 3.0f)
        val wigY = Math.round((h4 - 0.5f) * 3.0f)
        val starX = (baseX + wigX) / lowW
        val starY = (baseY + wigY) / lowH

        val paramBuf = paramBufs[ping]
        ping = 1 - ping
        paramBuf.clear()
        paramBuf.put(tick).put(starX).put(starY).put(radius)
        paramBuf.put(intensity).put(lowW.toFloat()).put(lowH.toFloat()).put(0f)
        paramBuf.flip()

        GLES30.glBindVertexArray(vao)
        GLES30.glActiveTexture(GLES30.GL_TEXTURE0)
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, paramTex)
        GLES30.glTexSubImage2D(
            GLES30.GL_TEXTURE_2D, 0, 0, 0, 2, 1,
            GLES30.GL_RGBA, GLES30.GL_FLOAT, paramBuf
        )

        // pass A: base scene into the low-res FBO
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, fbo)
        GLES30.glViewport(0, 0, lowW, lowH)
        GLES30.glDisable(GLES30.GL_BLEND)
        GLES30.glUseProgram(sceneProg)
        GLES30.glDrawArrays(GLES30.GL_TRIANGLES, 0, 3)

        // pass B: additive quantized light pass, ignoring the color ramp
        GLES30.glEnable(GLES30.GL_BLEND)
        GLES30.glBlendFunc(GLES30.GL_ONE, GLES30.GL_ONE)
        GLES30.glUseProgram(lightProg)
        GLES30.glDrawArrays(GLES30.GL_TRIANGLES, 0, 3)

        if (burst < 24) {
            GLES30.glReadBuffer(GLES30.GL_COLOR_ATTACHMENT0)
            val fb = java.nio.ByteBuffer.allocateDirect(lowW * lowH * 4).order(java.nio.ByteOrder.nativeOrder())
            GLES30.glReadPixels(0, 0, lowW, lowH, GLES30.GL_RGBA, GLES30.GL_UNSIGNED_BYTE, fb)
            val arr = ByteArray(lowW * lowH * 4)
            fb.get(arr)
            burstDir?.let { java.io.File(it, "burst_$burst.raw").writeBytes(arr) }
            burst++
        }

        // pass C: nearest upscale to the window surface
        GLES30.glDisable(GLES30.GL_BLEND)
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, 0)
        GLES30.glViewport(0, 0, surfW, surfH)
        GLES30.glUseProgram(blitProg)
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, fboTex)
        GLES30.glUniform2f(GLES30.glGetUniformLocation(blitProg, "uRes"), surfW.toFloat(), surfH.toFloat())
        GLES30.glDrawArrays(GLES30.GL_TRIANGLES, 0, 3)
    }
    fun release() {
        val one = IntArray(1)
        GLES30.glDeleteProgram(sceneProg); sceneProg = 0
        GLES30.glDeleteProgram(lightProg); lightProg = 0
        GLES30.glDeleteProgram(blitProg); blitProg = 0
        one[0] = fbo; GLES30.glDeleteFramebuffers(1, one, 0); fbo = 0
        one[0] = fboTex; GLES30.glDeleteTextures(1, one, 0); fboTex = 0
        one[0] = paramTex; GLES30.glDeleteTextures(1, one, 0); paramTex = 0
        one[0] = vao; GLES30.glDeleteVertexArrays(1, one, 0); vao = 0
        GLES30.glDeleteBuffers(1, one, 0); vbo = 0
    }
}
