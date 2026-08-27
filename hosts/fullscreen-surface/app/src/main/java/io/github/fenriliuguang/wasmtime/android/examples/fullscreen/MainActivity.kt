package io.github.fenriliuguang.wasmtime.android.examples.fullscreen

import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Choreographer
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.WindowManager
import android.widget.TextView
import androidx.webgpu.helper.Util
import io.github.fenriliuguang.wasi.webgpu.experimental.dawn.DawnWasiWebGpuHost
import io.github.fenriliuguang.wasmtime.android.Component
import io.github.fenriliuguang.wasmtime.android.Engine
import io.github.fenriliuguang.wasmtime.android.Linker
import io.github.fenriliuguang.wasmtime.android.Store
import io.github.fenriliuguang.wasmtime.android.host.dawn.GpuBackends
import io.github.fenriliuguang.wasmtime.android.host.dawn.HostWebGpuBackend
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Fullscreen [SurfaceView] host. Any guest that exports
 * `run: async func() -> u32` can be swapped in via `-Pguest.wasm=`.
 *
 * GpuThread owns Dawn, compile/instantiate, and [callRunConcurrent].
 * The UI thread only owns Surface lifecycle + Choreographer vsync.
 */
class MainActivity : Activity(), SurfaceHolder.Callback, Choreographer.FrameCallback {
    private val gpuThread = HandlerThread("GpuThread").apply { start() }
    private val gpuHandler = Handler(gpuThread.looper)
    private val storeRef = AtomicReference<Store?>(null)
    private val guestStarted = AtomicBoolean(false)
    private var statusView: TextView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enterFullscreen()
        setContentView(R.layout.activity_main)
        statusView = findViewById(R.id.status)
        val surfaceView = findViewById<SurfaceView>(R.id.guest_surface)
        surfaceView.holder.addCallback(this)
    }

    override fun surfaceCreated(holder: SurfaceHolder) = Unit

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        val surface = holder.surface
        if (surface == null || !surface.isValid || width <= 0 || height <= 0) {
            return
        }
        if (!guestStarted.compareAndSet(false, true)) {
            return
        }
        gpuHandler.post { runGuest(surface, width, height) }
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        runCatching { storeRef.get()?.closeGfxOnFrame() }
        Choreographer.getInstance().removeFrameCallback(this)
    }

    override fun doFrame(frameTimeNanos: Long) {
        storeRef.get()?.postGfxVsync(frameTimeNanos)
        if (storeRef.get() != null) {
            Choreographer.getInstance().postFrameCallback(this)
        }
    }

    override fun onDestroy() {
        runCatching { storeRef.get()?.closeGfxOnFrame() }
        Choreographer.getInstance().removeFrameCallback(this)
        gpuThread.quitSafely()
        super.onDestroy()
    }

    private fun runGuest(surface: Surface, width: Int, height: Int) {
        try {
            val bytes = assets.open("guest.wasm").use { it.readBytes() }
            Log.i(TAG, "GpuThread: Dawn bindCanvasNativeWindow ${width}x${height}")
            val host = DawnWasiWebGpuHost.create()
            host.bindCanvasNativeWindow(Util.windowFromSurface(surface), width, height)
            Engine.create().use { engine ->
                Component.compile(engine, bytes).use { component ->
                    Linker.create(engine).use { linker ->
                        Store.create(engine).use { store ->
                            store.setWebGpuBackend(
                                HostWebGpuBackend(host, GpuBackends.DAWN_ID),
                            )
                            linker.instantiate(store, component).use { instance ->
                                startVsyncOnMain(store)
                                val frames = instance.callRunConcurrent(store)
                                Log.i(TAG, "guest run returned $frames")
                            }
                        }
                    }
                }
            }
        } catch (t: Throwable) {
            Log.e(TAG, "guest run failed", t)
            showStatus("guest failed: ${t.message}")
        } finally {
            storeRef.set(null)
            guestStarted.set(false)
            runOnUiThread {
                Choreographer.getInstance().removeFrameCallback(this)
            }
        }
    }

    private fun startVsyncOnMain(store: Store) {
        val started = CountDownLatch(1)
        runOnUiThread {
            storeRef.set(store)
            Choreographer.getInstance().postFrameCallback(this)
            started.countDown()
        }
        if (!started.await(5, TimeUnit.SECONDS)) {
            error("Choreographer vsync not posted")
        }
    }

    private fun showStatus(message: String) {
        runOnUiThread {
            statusView?.let { view ->
                view.text = message
                view.visibility = android.view.View.VISIBLE
            }
        }
    }

    private fun enterFullscreen() {
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        @Suppress("DEPRECATION")
        window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
    }

    companion object {
        private const val TAG = "FullscreenSurface"
    }
}
