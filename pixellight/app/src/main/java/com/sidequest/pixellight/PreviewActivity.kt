package com.sidequest.pixellight

import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.view.SurfaceHolder
import android.view.SurfaceView

class PreviewActivity : Activity() {

    private val thread = HandlerThread("pixellight-preview").apply { start() }
    private val handler = Handler(thread.looper)
    private var egl: EglSurface? = null
    private var renderer: SceneRenderer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val sv = SurfaceView(this)
        setContentView(sv)
        sv.holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) {
                handler.post {
                    egl = EglSurface(holder.surface)
                    renderer = SceneRenderer().also { it.create(); it.burstTo(getExternalFilesDir(null) ?: filesDir) }
                }
            }

            override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
                handler.post {
                    renderer?.resize(width, height)
                    handler.removeCallbacks(frame)
                    handler.post(frame)
                }
            }

            override fun surfaceDestroyed(holder: SurfaceHolder) {
                handler.removeCallbacks(frame)
                handler.post {
                    renderer?.release()
                    renderer = null
                    egl?.release()
                    egl = null
                }
            }
        })
    }

    private val frame = object : Runnable {
        override fun run() {
            val e = egl
            val r = renderer
            if (e != null && r != null) {
                r.draw(SystemClock.elapsedRealtime() / 1000.0f)
                e.swap()
                handler.postDelayed(this, FRAME_MS)
            }
        }
    }

    override fun onDestroy() {
        thread.quitSafely()
        super.onDestroy()
    }

    companion object {
        private const val FRAME_MS = 66L
    }
}
