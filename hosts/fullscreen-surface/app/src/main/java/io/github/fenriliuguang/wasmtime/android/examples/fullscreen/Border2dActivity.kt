package io.github.fenriliuguang.wasmtime.android.examples.fullscreen

/** 2D border-loop guest. Packed as `guest.wasm` when `-Pexample=border2d`. */
class Border2dActivity : GuestSurfaceActivity() {
    override val logTag: String = "FullscreenBorder2d"
    override val exampleName: String = "border2d"
}
