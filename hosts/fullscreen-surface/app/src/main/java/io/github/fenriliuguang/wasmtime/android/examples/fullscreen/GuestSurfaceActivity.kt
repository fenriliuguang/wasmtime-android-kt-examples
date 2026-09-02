package io.github.fenriliuguang.wasmtime.android.examples.fullscreen

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import android.view.Choreographer
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.WindowManager
import android.widget.TextView
import io.github.fenriliuguang.wasmtime.android.Component
import io.github.fenriliuguang.wasmtime.android.Engine
import io.github.fenriliuguang.wasmtime.android.Linker
import io.github.fenriliuguang.wasmtime.android.Store
import io.github.fenriliuguang.wasmtime.android.host.dawn.GpuBackends
import io.github.fenriliuguang.wasmtime.android.jni.NativeBridge
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Fullscreen [SurfaceView] host. Subclasses pick the guest wasm asset.
 *
 * GpuThread owns NativeGpu, compile/instantiate, and [callRunConcurrent].
 * The UI thread only owns Surface lifecycle + Choreographer vsync.
 */
open class GuestSurfaceActivity : Activity(), SurfaceHolder.Callback, Choreographer.FrameCallback {
    protected open val wasmAsset: String = "guest.wasm"
    protected open val logTag: String = "FullscreenSurface"
    /** Cube color-ratio capture needs a clean SurfaceView; 2D can keep the clock. */
    protected open val showHitchOverlay: Boolean = true

    private val gpuThread = HandlerThread("GpuThread").apply { start() }
    private val gpuHandler = Handler(gpuThread.looper)
    private val storeRef = AtomicReference<Store?>(null)
    private val guestStarted = AtomicBoolean(false)
    private var statusView: TextView? = null
    private var stopwatchView: TextView? = null
    private var vsyncDtView: TextView? = null
    private var overlayStartNs = 0L
    private var lastDoFrameNs = 0L
    private var vsyncSamples = 0
    private var vsyncLt11 = 0
    private var vsyncMid = 0
    private var vsyncGt20 = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enterFullscreen()
        setContentView(R.layout.activity_main)
        statusView = findViewById(R.id.status)
        stopwatchView = findViewById(R.id.stopwatch)
        vsyncDtView = findViewById(R.id.vsync_dt)
        overlayStartNs = 0L
        if (!showHitchOverlay) {
            findViewById<android.view.View>(R.id.hitch_overlay).visibility =
                android.view.View.GONE
        }
        val surfaceView = findViewById<SurfaceView>(R.id.guest_surface)
        if (Build.VERSION.SDK_INT >= 30) {
            val peakHz = display?.supportedModes
                ?.maxByOrNull { it.refreshRate }
                ?.refreshRate
                ?: 120f
            surfaceView.setRequestedFrameRate(peakHz)
        }
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
        preferDisplayRefresh(surface)
        gpuHandler.post { runGuest(surface, width, height) }
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        runCatching { storeRef.get()?.closeGfxOnFrame() }
        Choreographer.getInstance().removeFrameCallback(this)
    }

    override fun doFrame(frameTimeNanos: Long) {
        val prev = lastDoFrameNs
        lastDoFrameNs = frameTimeNanos
        val dt = if (prev == 0L) 0L else frameTimeNanos - prev
        if (prev != 0L) {
            vsyncSamples++
            when {
                dt < 11_000_000L -> vsyncLt11++
                dt <= 20_000_000L -> vsyncMid++
                else -> vsyncGt20++
            }
            if (vsyncSamples % 120 == 0) {
                val disp = display
                Log.i(
                    logTag,
                    "choreographer n=$vsyncSamples <11ms=$vsyncLt11 " +
                        "11-20ms=$vsyncMid >20ms=$vsyncGt20 lastDtNs=$dt " +
                        "dispHz=${disp?.refreshRate} modeHz=${disp?.mode?.refreshRate} " +
                        "modeId=${disp?.mode?.modeId}",
                )
            }
        }
        updateStopwatch(dt)
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
            val bytes = assets.open(wasmAsset).use { it.readBytes() }
            Log.i(logTag, "GpuThread: $wasmAsset NativeGpu ${width}x${height}")
            Engine.create().use { engine ->
                Component.compile(engine, bytes).use { component ->
                    Linker.create(engine).use { linker ->
                        Store.create(engine).use { store ->
                            store.setWebGpuBackend(GpuBackends.dawn())
                            store.bindCanvasNativeWindow(
                                NativeBridge.nativeWindowFromSurface(surface),
                                width,
                                height,
                            )
                            linker.instantiate(store, component).use { instance ->
                                startVsyncOnMain(store)
                                val frames = instance.callRunConcurrent(store)
                                Log.i(logTag, "guest run returned $frames")
                            }
                        }
                    }
                }
            }
        } catch (t: Throwable) {
            Log.e(logTag, "guest run failed", t)
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

    private fun updateStopwatch(lastDtNs: Long) {
        if (!showHitchOverlay) {
            return
        }
        if (overlayStartNs == 0L) {
            overlayStartNs = SystemClock.elapsedRealtimeNanos()
        }
        val elapsedNs = SystemClock.elapsedRealtimeNanos() - overlayStartNs
        val sec = elapsedNs / 1_000_000_000.0
        stopwatchView?.text = String.format(Locale.US, "%.3f", sec)
        vsyncDtView?.text = if (lastDtNs == 0L) {
            "vsync —"
        } else {
            String.format(Locale.US, "vsync %.2f ms", lastDtNs / 1_000_000.0)
        }
    }

    private fun preferDisplayRefresh(surface: Surface) {
        if (Build.VERSION.SDK_INT < 30) {
            return
        }
        val disp = display ?: return
        val current = disp.mode
        val sameSize = disp.supportedModes.filter { mode ->
            current == null ||
                (mode.physicalWidth == current.physicalWidth &&
                    mode.physicalHeight == current.physicalHeight)
        }
        val mode = sameSize.maxByOrNull { it.refreshRate }
            ?: disp.supportedModes.maxByOrNull { it.refreshRate }
        val hz = mode?.refreshRate ?: disp.refreshRate
        if (hz <= 0f) {
            return
        }
        if (mode != null) {
            val params = window.attributes
            params.preferredDisplayModeId = mode.modeId
            params.preferredRefreshRate = hz
            window.attributes = params
        }
        if (Build.VERSION.SDK_INT >= 31) {
            window.setPreferMinimalPostProcessing(true)
            surface.setFrameRate(
                hz,
                Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE,
                Surface.CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS,
            )
        } else {
            surface.setFrameRate(hz, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
        }
        Log.i(
            logTag,
            "Surface.setFrameRate($hz, ONLY_IF_SEAMLESS) displayPeak=$hz " +
                "current=${disp.refreshRate} modeId=${mode?.modeId} " +
                "modeHz=${mode?.refreshRate} sdk=${Build.VERSION.SDK_INT}",
        )
    }

    private fun enterFullscreen() {
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        @Suppress("DEPRECATION")
        window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
        if (Build.VERSION.SDK_INT >= 31) {
            window.setPreferMinimalPostProcessing(true)
        }
    }
}
