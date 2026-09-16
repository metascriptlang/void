package com.metascript.voidsample

import android.app.Activity
import android.app.WallpaperManager
import android.content.ComponentName
import android.content.Intent
import android.os.Bundle
import android.view.SurfaceHolder
import android.view.SurfaceView

class MainActivity : Activity(), SurfaceHolder.Callback {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val view = SurfaceView(this)
        view.holder.addCallback(this)
        view.setOnLongClickListener {
            openWallpaperPicker()
            true
        }
        setContentView(view)
    }

    override fun surfaceCreated(holder: SurfaceHolder) {}

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        VoidRenderer.show(this, holder.surface, width, height)
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        VoidRenderer.hide(this)
    }

    private fun openWallpaperPicker() {
        val intent = Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER)
            .putExtra(
                WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT,
                ComponentName(this, VoidWallpaperService::class.java),
            )
        startActivity(intent)
    }
}
