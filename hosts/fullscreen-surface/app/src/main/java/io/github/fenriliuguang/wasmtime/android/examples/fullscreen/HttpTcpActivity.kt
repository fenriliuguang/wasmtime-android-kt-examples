package io.github.fenriliuguang.wasmtime.android.examples.fullscreen

/**
 * TCP loopback echo + outbound HTTP GET to the in-app 127.0.0.1:18765 server.
 * Uses [Linker.createWithFixtureConstructors] because the guest imports
 * `[constructor]request` (product leftover P010-HCTOR).
 */
class HttpTcpActivity : GuestSurfaceActivity() {
    override val logTag: String = "ExampleHttpTcp"
    override val exampleName: String = "http-tcp"
    override val showHitchOverlay: Boolean = false
    override val showRunResult: Boolean = true
    override val fixtureLinker: Boolean = true
    override val localHttp: Boolean = true
}
