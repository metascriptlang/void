package com.sidequest.pixellight

import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.service.wallpaper.WallpaperService
import android.view.SurfaceHolder
import java.util.concurrent.CountDownLatch

class NightWallpaperService : WallpaperService() {

    override fun onCreateEngine(): Engine = NightEngine()

    private inner class NightEngine : Engine() {

        private val thread = HandlerThread("pixellight-render").apply { start() }
        private val handler = Handler(thread.looper)
        private var egl: EglSurface? = null
        private var renderer: SceneRenderer? = null

        @Volatile
        private var visible = true

        private val frame = object : Runnable {
            override fun run() {
                val e = egl
                val r = renderer
                if (e != null && r != null) {
                    r.draw(SystemClock.elapsedRealtime() / 1000.0f)
                    e.swap()
                }
                if (visible) handler.postDelayed(this, FRAME_MS)
            }
        }

        override fun onSurfaceCreated(holder: SurfaceHolder) {
            handler.post {
                egl = EglSurface(holder.surface)
                renderer = SceneRenderer().also { it.create() }
                handler.removeCallbacks(frame)
                handler.post(frame)
            }
        }

        override fun onSurfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            handler.post { renderer?.resize(width, height) }
        }

        override fun onVisibilityChanged(v: Boolean) {
            visible = v
            if (v) {
                handler.removeCallbacks(frame)
                handler.post(frame)
            } else {
                handler.removeCallbacks(frame)
            }
        }

        override fun onSurfaceDestroyed(holder: SurfaceHolder) {
            visible = false
            handler.removeCallbacks(frame)
            val done = CountDownLatch(1)
            handler.post {
                renderer?.release()
                renderer = null
                egl?.release()
                egl = null
                done.countDown()
            }
            done.await()
        }

        override fun onDestroy() {
            thread.quitSafely()
        }
    }

    companion object {
        private const val FRAME_MS = 66L
    }
}
