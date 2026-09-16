package com.metascript.voidsample

import android.service.wallpaper.WallpaperService
import android.view.SurfaceHolder

class VoidWallpaperService : WallpaperService() {
    override fun onCreateEngine(): Engine = VoidEngine()

    private inner class VoidEngine : Engine() {
        private var width = 0
        private var height = 0

        override fun onSurfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            super.onSurfaceChanged(holder, format, width, height)
            this.width = width
            this.height = height
            if (isVisible) VoidRenderer.show(this, holder.surface, width, height)
        }

        override fun onVisibilityChanged(visible: Boolean) {
            if (visible && width > 0) {
                VoidRenderer.show(this, surfaceHolder.surface, width, height)
            } else {
                VoidRenderer.hide(this)
            }
        }

        override fun onSurfaceDestroyed(holder: SurfaceHolder) {
            VoidRenderer.hide(this)
            width = 0
            height = 0
            super.onSurfaceDestroyed(holder)
        }

        override fun onDestroy() {
            VoidRenderer.hide(this)
            super.onDestroy()
        }
    }
}
