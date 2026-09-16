package com.metascript.voidsample

import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Choreographer
import android.view.Surface
import java.util.concurrent.CountDownLatch

object VoidRenderer : Choreographer.FrameCallback {
    private const val MIN_FRAME_NANOS = 30_000_000L
    private const val TAG = "VoidRender"

    private class Target(val surface: Surface, val width: Int, val height: Int)

    private val thread = HandlerThread(TAG).apply { start() }
    private val handler = Handler(thread.looper)
    private val targets = LinkedHashMap<Any, Target>()
    private var activeOwner: Any? = null
    private var activeTarget: Target? = null
    private var ticking = false
    private var lastFrameNanos = 0L
    private var framesSinceLog = 0
    private var lastLogNanos = 0L

    fun show(owner: Any, surface: Surface, width: Int, height: Int) {
        handler.post {
            targets.remove(owner)
            targets[owner] = Target(surface, width, height)
            bindLatest()
        }
    }

    fun hide(owner: Any) {
        val done = CountDownLatch(1)
        handler.post {
            targets.remove(owner)
            bindLatest()
            done.countDown()
        }
        done.await()
    }

    private fun bindLatest() {
        val owner = targets.keys.lastOrNull()
        val target = owner?.let { targets[it] }
        if (target == null) {
            if (activeTarget != null) {
                VoidNative.detach()
                Log.i(TAG, "detach")
            }
            activeOwner = null
            activeTarget = null
            return
        }
        val current = activeTarget
        if (owner === activeOwner && current != null && current.surface == target.surface) {
            if (current.width != target.width || current.height != target.height) {
                VoidNative.resize(target.width, target.height)
            }
        } else {
            VoidNative.attach(target.surface, target.width, target.height)
            Log.i(TAG, "attach ${owner.javaClass.simpleName} ${target.width}x${target.height}")
        }
        activeOwner = owner
        activeTarget = target
        if (!ticking) {
            ticking = true
            Choreographer.getInstance().postFrameCallback(this)
        }
    }

    override fun doFrame(frameTimeNanos: Long) {
        if (activeTarget == null) {
            ticking = false
            return
        }
        if (frameTimeNanos - lastFrameNanos >= MIN_FRAME_NANOS) {
            lastFrameNanos = frameTimeNanos
            VoidNative.frame()
            framesSinceLog++
        }
        if (frameTimeNanos - lastLogNanos >= 1_000_000_000L) {
            Log.i(TAG, "fps=$framesSinceLog")
            framesSinceLog = 0
            lastLogNanos = frameTimeNanos
        }
        Choreographer.getInstance().postFrameCallback(this)
    }
}
