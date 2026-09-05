package io.github.fenriliuguang.wasmtime.android.examples.fullscreen

class TextureActivity : GuestSurfaceActivity() {
    override val logTag: String = "ExampleTexture"
    override val exampleName: String = "texture"
    override val showHitchOverlay: Boolean = false
    override val showRunResult: Boolean = true
}
