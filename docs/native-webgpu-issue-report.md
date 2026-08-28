# Issue report — androidx.webgpu `GPUQueue.onSubmittedWorkDone` leaks JNI global references

Ready-to-paste upstream report. Target:
<https://issuetracker.google.com/issues/new?component=1960262> (Google Dawn /
androidx.webgpu). The heading below is the issue title.

---

## Title

`GPUQueue.onSubmittedWorkDone` leaks JNI global references (executor + callback) and overflows the global reference table

## Summary

`GPUQueue.onSubmittedWorkDone(Executor, GPURequestCallback<Unit>)` is
`@FastNative external`. Its native implementation calls `NewGlobalRef` on
**both** the `callback` and the `callbackExecutor` on every invocation and never
calls `DeleteGlobalRef` on them. An app that fences once per frame therefore
leaks 2 global references per frame; at 120 Hz the ART global reference table
overflows (`max=51200`) in ~3.5 minutes and the process aborts with `SIGABRT` on
the render thread.

## Version

- `androidx.webgpu:webgpu:1.0.0-alpha05` (AAR ships `libwebgpu_c_bundled.so`)
- Android 14 (SDK 36)

## Repro

Minimal app (no Wasmtime, no custom host; only androidx.webgpu):

1. `GPU.createInstance()` → `requestAdapter(BackendType.Vulkan)` → `requestDevice`.
2. `createSurface` from a `SurfaceView` `ANativeWindow`; `configure(..., PresentMode.Fifo)`.
3. Per frame (Choreographer @ 120 Hz, on a dedicated render thread):
   1. `surface.getCurrentTexture().texture.createView()`
   2. record a clear render pass, `queue.submit([cmd])`
   3. `queue.onSubmittedWorkDone(executor, callback)` — **one shared**
      `Executor(Runnable::run)` plus a **fresh** `GPURequestCallback<Unit>` per frame
   4. `surface.present()`

Full sources: [`hosts/native-webgpu`](https://github.com/fenriliuguang/wasmtime-android-kt-examples/tree/main/hosts/native-webgpu)
in
[fenriliuguang/wasmtime-android-kt-examples](https://github.com/fenriliuguang/wasmtime-android-kt-examples).

## Observed

After ~25,300 frames (~3.5 min @ 120 Hz):

```
Fatal signal 6 (SIGABRT), code -1 (SI_QUEUE) in tid ... (GpuThread)
Abort message: 'JNI ERROR (app bug): global reference table overflow (max=51200)global reference table dump:
  ...
    25313 of io.github...nativewebgpu.MainActivity$$ExternalSyntheticLambda2 (1 unique instances)
    25312 of io.github...nativewebgpu.MainActivity$renderFrame$1 (25312 unique instances)
  ...'
```

- `ExternalSyntheticLambda2` = the single shared `Executor(Runnable::run)`
  (compiler-generated lambda index; varies with source, the key is 1 unique).
- `renderFrame$1` = the fresh per-frame `GPURequestCallback<Unit>`.
- Exactly 2 refs/frame; the table grows monotonically and never shrinks, even
  though each `onSubmittedWorkDone`'s callback has long since fired.

## Expected

Calling `onSubmittedWorkDone` should not grow the global reference table without
bound. The native implementation must `DeleteGlobalRef` the executor and
callback once the work-done callback has been delivered (or otherwise release
them deterministically), matching the other async entry points.

## Impact

Any long-running app that fences every frame (a standard present-sync pattern)
crashes within minutes on high-refresh-rate devices. The only mitigation is to
fence less often (batch frames before fencing), which slows but does not stop
the overflow. Note the `suspend fun onSubmittedWorkDone()` convenience overload
also funnels through the same `external` method, so it leaks identically.

## Device

- Model: V2458A (PD2415M) — MediaTek Dimensity / Mali (`mt6991`), 120 Hz
- Also reproduced in wasmtime-android-kt#297 (tracked there as a runtime-blocking
  upstream issue).
