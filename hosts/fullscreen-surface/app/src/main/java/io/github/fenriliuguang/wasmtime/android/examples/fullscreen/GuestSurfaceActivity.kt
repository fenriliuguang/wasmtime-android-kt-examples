package io.github.fenriliuguang.wasmtime.android.examples.fullscreen

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.system.Os
import android.util.Log
import android.view.Choreographer
import android.view.KeyEvent
import android.view.MotionEvent
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
import java.io.ByteArrayOutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Fullscreen [SurfaceView] host. Subclasses pick the guest wasm and the
 * 0.1.2 SPI knobs (product vs fixture linker, auto pointer/key, local HTTP).
 *
 * GpuThread owns NativeGpu, compile/instantiate, and [callRunConcurrent].
 * The UI thread only owns Surface lifecycle + Choreographer vsync + input.
 */
open class GuestSurfaceActivity : Activity(), SurfaceHolder.Callback, Choreographer.FrameCallback {
    protected open val wasmAsset: String = "guest.wasm"
    protected open val logTag: String = "FullscreenSurface"
    protected open val exampleName: String = "cube"
    /** Cube color-ratio capture needs a clean SurfaceView; 2D can keep the clock. */
    protected open val showHitchOverlay: Boolean = true
    protected open val showRunResult: Boolean = false
    /** HTTP GET guest imports `[constructor]request` (P010-HCTOR leftover). */
    protected open val fixtureLinker: Boolean = false
    /** Post one pointer-down + key-down after instantiate (scriptable). */
    protected open val autoInput: Boolean = false
    /** Bind TMPDIR to [cacheDir] so wasi:filesystem preopen is app-private. */
    protected open val pinTmpdir: Boolean = true
    /** Serve HTTP/1.1 200 `HOUT` on 127.0.0.1:[httpPort] for the http-tcp guest. */
    protected open val localHttp: Boolean = false
    protected open val httpPort: Int = 18765

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
    private var httpServer: ServerSocket? = null
    private var httpThread: Thread? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enterFullscreen()
        if (pinTmpdir) {
            runCatching { Os.setenv("TMPDIR", cacheDir.absolutePath, true) }
        }
        if (localHttp) {
            startLocalHttp()
        }
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

    override fun onTouchEvent(event: MotionEvent): Boolean {
        val kind = when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> 1
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP, MotionEvent.ACTION_CANCEL -> 0
            MotionEvent.ACTION_MOVE -> 2
            else -> return super.onTouchEvent(event)
        }
        runCatching { storeRef.get()?.postGfxPointer(kind, event.x.toDouble(), event.y.toDouble()) }
        return true
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN || event.action == KeyEvent.ACTION_UP) {
            runCatching {
                storeRef.get()?.postGfxKey(
                    event.action == KeyEvent.ACTION_DOWN,
                    event.keyCode,
                    event.unicodeChar.takeIf { it != 0 }?.toChar()?.toString(),
                    event.isAltPressed,
                    event.isCtrlPressed,
                    event.isMetaPressed,
                    event.isShiftPressed,
                )
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onDestroy() {
        runCatching { storeRef.get()?.closeGfxOnFrame() }
        Choreographer.getInstance().removeFrameCallback(this)
        stopLocalHttp()
        gpuThread.quitSafely()
        super.onDestroy()
    }

    private fun runGuest(surface: Surface, width: Int, height: Int) {
        try {
            val bytes = assets.open(wasmAsset).use { it.readBytes() }
            val linkerKind = if (fixtureLinker) "fixture-ctors" else "product"
            Log.i(logTag, "GpuThread: $exampleName $wasmAsset $linkerKind NativeGpu ${width}x${height}")
            Engine.create().use { engine ->
                Component.compile(engine, bytes).use { component ->
                    val linker =
                        if (fixtureLinker) {
                            Linker.createWithFixtureConstructors(engine)
                        } else {
                            Linker.create(engine)
                        }
                    linker.use { usedLinker ->
                        Store.create(engine).use { store ->
                            store.setWebGpuBackend(GpuBackends.dawn())
                            store.bindCanvasNativeWindow(
                                NativeBridge.nativeWindowFromSurface(surface),
                                width,
                                height,
                            )
                            usedLinker.instantiate(store, component).use { instance ->
                                startVsyncOnMain(store)
                                if (autoInput) {
                                    store.postGfxPointer(1, 12.5, 34.0)
                                    store.postGfxKey(true, KeyEvent.KEYCODE_A, "a")
                                }
                                val frames = instance.callRunConcurrent(store)
                                Log.i(logTag, "guest run returned $frames")
                                Log.i(logTag, "EXAMPLE_OK example=$exampleName code=$frames")
                                if (showRunResult) {
                                    showStatus("EXAMPLE_OK $exampleName $frames")
                                }
                            }
                        }
                    }
                }
            }
        } catch (t: Throwable) {
            Log.e(logTag, "guest run failed", t)
            Log.e(logTag, "EXAMPLE_FAIL example=$exampleName err=${t.message}")
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

    private fun startLocalHttp() {
        val server = ServerSocket(httpPort, 1, InetAddress.getByName("127.0.0.1"))
        httpServer = server
        httpThread =
            Thread({
                try {
                    server.use { listener ->
                        val sock = listener.accept()
                        sock.soTimeout = 8_000
                        sock.use { peer ->
                            val buf = ByteArrayOutputStream()
                            val tmp = ByteArray(512)
                            while (true) {
                                val n = peer.getInputStream().read(tmp)
                                if (n <= 0) break
                                buf.write(tmp, 0, n)
                                val bytes = buf.toByteArray()
                                if (bytes.size >= 4) {
                                    val s = bytes.size
                                    if (bytes[s - 4] == 0x0d.toByte() &&
                                        bytes[s - 3] == 0x0a.toByte() &&
                                        bytes[s - 2] == 0x0d.toByte() &&
                                        bytes[s - 1] == 0x0a.toByte()
                                    ) {
                                        break
                                    }
                                }
                            }
                            Log.i(
                                logTag,
                                "local HTTP peer saw ${buf.toByteArray().decodeToString()}",
                            )
                            peer.getOutputStream().write(
                                "HTTP/1.1 200 OK\r\nContent-Length: 4\r\nConnection: close\r\n\r\nHOUT"
                                    .toByteArray(),
                            )
                            peer.getOutputStream().flush()
                        }
                    }
                } catch (t: Throwable) {
                    Log.w(logTag, "local HTTP stopped: ${t.message}")
                }
            }, "example-http").apply { isDaemon = true; start() }
        Log.i(logTag, "local HTTP 127.0.0.1:$httpPort")
    }

    private fun stopLocalHttp() {
        runCatching { httpServer?.close() }
        httpServer = null
        httpThread = null
    }
}
