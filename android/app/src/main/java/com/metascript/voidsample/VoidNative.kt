package com.metascript.voidsample

import android.view.Surface

object VoidNative {
    init {
        System.loadLibrary("VoidAndroid")
        System.loadLibrary("VoidJni")
    }

    external fun attach(surface: Surface, width: Int, height: Int)
    external fun resize(width: Int, height: Int)
    external fun frame()
    external fun detach()
}
