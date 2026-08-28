package io.github.fenriliuguang.wasmtime.android.examples.nativewebgpu

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Choreographer
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.WindowManager
import androidx.webgpu.BackendType
import androidx.webgpu.GPU
import androidx.webgpu.GPUColor
import androidx.webgpu.GPUCommandEncoder
import androidx.webgpu.GPUDevice
import androidx.webgpu.GPUDeviceDescriptor
import androidx.webgpu.GPUInstance
import androidx.webgpu.GPUQueue
import androidx.webgpu.GPURenderPassColorAttachment
import androidx.webgpu.GPURenderPassDescriptor
import androidx.webgpu.GPURequestAdapterOptions
import androidx.webgpu.GPURequestCallback
import androidx.webgpu.GPUSurface
import androidx.webgpu.GPUSurfaceConfiguration
import androidx.webgpu.GPUSurfaceDescriptor
import androidx.webgpu.GPUSurfaceSourceAndroidNativeWindow
import androidx.webgpu.LoadOp
import androidx.webgpu.PresentMode
import androidx.webgpu.StoreOp
import androidx.webgpu.TextureUsage
import androidx.webgpu.helper.Util
import androidx.webgpu.helper.initLibrary
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Minimal pure-`androidx.webgpu` repro of the `GPUQueue.onSubmittedWorkDone`
 * JNI global-reference leak.
 *
 * No Wasmtime, no custom host — only `androidx.webgpu:webgpu:1.0.0-alpha05`
 * (whose AAR ships `libwebgpu_c_bundled.so`).
 *
 * One `onSubmittedWorkDone(sharedExecutor, freshCallback)` per frame leaks
 * 2 global refs/frame: the native impl `NewGlobalRef`s both the executor and
 * the callback on every call and never `DeleteGlobalRef`s them. At 120 Hz the
 * ART global reference table overflows (`max=51200`) in ~3.5 min and the
 * process aborts with SIGABRT on GpuThread.
 */
class MainActivity : Activity(), SurfaceHolder.Callback, Choreographer.FrameCallback {
    private val gpuThread = HandlerThread("GpuThread").apply { start() }
    private val gpuHandler = Handler(gpuThread.looper)

    // Single shared executor — NewGlobalRef'd by JNI on every fence call.
    private val callbackExecutor = Executor(Runnable::run)

    private val started = AtomicBoolean(false)
    private val frameInFlight = AtomicBoolean(false)
    private var device: GPUDevice? = null
    private var queue: GPUQueue? = null
    private var surface: GPUSurface? = null
    private var frames = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setContentView(R.layout.activity_main)
        val surfaceView = findViewById<SurfaceView>(R.id.surface)
        if (Build.VERSION.SDK_INT >= 30) {
            val peak = display?.supportedModes?.maxOfOrNull { it.refreshRate } ?: 120f
            surfaceView.setRequestedFrameRate(peak)
        }
        surfaceView.holder.addCallback(this)
    }

    override fun surfaceCreated(holder: SurfaceHolder) = Unit

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, w: Int, h: Int) {
        val surface = holder.surface ?: return
        if (!started.compareAndSet(false, true)) {
            return
        }
        pinRefreshRate(surface)
        gpuHandler.post { setup(surface, w, h) }
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        Choreographer.getInstance().removeFrameCallback(this)
    }

    override fun doFrame(frameTimeNanos: Long) {
        // 1-slot gate: drop the beat if GpuThread is still in a frame.
        if (frameInFlight.compareAndSet(false, true)) {
            gpuHandler.post { renderFrame() }
        }
        Choreographer.getInstance().postFrameCallback(this)
    }

    private fun setup(surface: Surface, w: Int, h: Int) {
        initLibrary()
        val instance = GPU.createInstance()
        val adapter = await(instance) {
            instance.requestAdapter(
                callbackExecutor,
                GPURequestAdapterOptions(backendType = BackendType.Vulkan),
                it,
            )
        }
        val gpuDevice = await(instance) {
            adapter.requestDevice(
                callbackExecutor,
                GPUDeviceDescriptor(
                    deviceLostCallbackExecutor = callbackExecutor,
                    uncapturedErrorCallbackExecutor = callbackExecutor,
                    deviceLostCallback = null,
                    uncapturedErrorCallback = null,
                ),
                it,
            )
        }
        device = gpuDevice
        queue = gpuDevice.queue
        val gpuSurface = instance.createSurface(
            GPUSurfaceDescriptor(
                surfaceSourceAndroidNativeWindow =
                    GPUSurfaceSourceAndroidNativeWindow(Util.windowFromSurface(surface)),
            ),
        )
        val caps = gpuSurface.getCapabilities(adapter)
        gpuSurface.configure(
            GPUSurfaceConfiguration(
                device = gpuDevice,
                width = w,
                height = h,
                format = caps.formats[0],
                usage = TextureUsage.RenderAttachment,
                viewFormats = intArrayOf(),
                alphaMode = caps.alphaModes[0],
                presentMode = PresentMode.Fifo,
            ),
        )
        this.surface = gpuSurface
        runOnUiThread { Choreographer.getInstance().postFrameCallback(this) }
    }

    private fun renderFrame() {
        try {
            val gpuSurface = surface ?: return
            val gpuQueue = queue ?: return
            val gpuDevice = device ?: return

            val view = gpuSurface.getCurrentTexture().texture.createView()
            val encoder: GPUCommandEncoder = gpuDevice.createCommandEncoder()
            encoder.beginRenderPass(
                GPURenderPassDescriptor(
                    colorAttachments = arrayOf(
                        GPURenderPassColorAttachment(
                            clearValue = GPUColor(0.0, 0.0, 0.0, 1.0),
                            view = view,
                            loadOp = LoadOp.Clear,
                            storeOp = StoreOp.Store,
                        ),
                    ),
                ),
            ).end()
            val commandBuffer = encoder.finish()
            gpuQueue.submit(arrayOf(commandBuffer))

            // LEAK SOURCE: the native impl NewGlobalRef's the executor AND the
            // callback on every call and never DeleteGlobalRef's them.
            gpuQueue.onSubmittedWorkDone(
                callbackExecutor,
                object : GPURequestCallback<Unit> {
                    override fun onResult(result: Unit) = Unit
                    override fun onError(exception: Exception) = Unit
                },
            )

            gpuSurface.present()
            frames++
            if (frames % 120 == 0L) {
                Log.i(TAG, "frames=$frames")
            }
        } catch (t: Throwable) {
            Log.e(TAG, "frame failed at frames=$frames", t)
        } finally {
            frameInFlight.set(false)
        }
    }

    // Pumps processEvents inline on GpuThread only during async setup. The frame
    // loop must NOT call processEvents concurrently with submit (Mali SIGSEGV).
    private fun <T> await(instance: GPUInstance, block: (GPURequestCallback<T>) -> Unit): T {
        val resultRef = AtomicReference<T?>()
        val error = AtomicReference<Exception?>()
        val latch = CountDownLatch(1)
        block(
            object : GPURequestCallback<T> {
                override fun onResult(result: T) {
                    resultRef.set(result)
                    latch.countDown()
                }

                override fun onError(exception: Exception) {
                    error.set(exception)
                    latch.countDown()
                }
            },
        )
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(30)
        while (latch.count > 0) {
            instance.processEvents()
            if (System.nanoTime() > deadline) {
                error("async GPU request timed out")
            }
            Thread.sleep(2)
        }
        error.get()?.let { throw RuntimeException(it.message, it) }
        @Suppress("UNCHECKED_CAST")
        return resultRef.get() as T
    }

    private fun pinRefreshRate(surface: Surface) {
        if (Build.VERSION.SDK_INT < 30) {
            return
        }
        val peak = display?.supportedModes?.maxOfOrNull { it.refreshRate } ?: return
        if (Build.VERSION.SDK_INT >= 31) {
            surface.setFrameRate(
                peak,
                Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE,
                Surface.CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS,
            )
        } else {
            surface.setFrameRate(peak, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
        }
    }

    companion object {
        private const val TAG = "NativeWebGpuLeak"
    }
}
