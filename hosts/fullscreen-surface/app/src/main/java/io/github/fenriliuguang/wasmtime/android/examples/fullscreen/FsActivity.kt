package io.github.fenriliuguang.wasmtime.android.examples.fullscreen

class FsActivity : GuestSurfaceActivity() {
    override val logTag: String = "ExampleFs"
    override val exampleName: String = "fs"
    override val showHitchOverlay: Boolean = false
    override val showRunResult: Boolean = true
}
