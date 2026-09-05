package io.github.fenriliuguang.wasmtime.android.examples.fullscreen

class ComputeActivity : GuestSurfaceActivity() {
    override val logTag: String = "ExampleCompute"
    override val exampleName: String = "compute"
    override val showHitchOverlay: Boolean = false
    override val showRunResult: Boolean = true
}
