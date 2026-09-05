package io.github.fenriliuguang.wasmtime.android.examples.fullscreen

/** Rotating cube guest (`assets/guest.wasm`). No VRI overlay: color-ratio capture. */
class MainActivity : GuestSurfaceActivity() {
    override val showHitchOverlay: Boolean = false
    override val exampleName: String = "cube"
}
