package io.github.fenriliuguang.wasmtime.android.examples.fullscreen

/** 2D border-loop guest (`assets/border2d.wasm`). */
class Border2dActivity : GuestSurfaceActivity() {
    override val wasmAsset: String = "border2d.wasm"
    override val logTag: String = "FullscreenBorder2d"
}
