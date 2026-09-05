package io.github.fenriliuguang.wasmtime.android.examples.fullscreen

class PointerActivity : GuestSurfaceActivity() {
    override val logTag: String = "ExamplePointer"
    override val exampleName: String = "pointer"
    override val showHitchOverlay: Boolean = false
    override val showRunResult: Boolean = true
    override val autoInput: Boolean = true
}
