package io.github.fenriliuguang.wasmtime.android.examples.fullscreen

class TcpActivity : GuestSurfaceActivity() {
    override val logTag: String = "ExampleTcp"
    override val exampleName: String = "tcp"
    override val showHitchOverlay: Boolean = false
    override val showRunResult: Boolean = true
}
