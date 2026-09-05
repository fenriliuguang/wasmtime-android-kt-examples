package io.github.fenriliuguang.wasmtime.android.examples.fullscreen

class CliActivity : GuestSurfaceActivity() {
    override val logTag: String = "ExampleCli"
    override val exampleName: String = "cli"
    override val showHitchOverlay: Boolean = false
    override val showRunResult: Boolean = true
}
