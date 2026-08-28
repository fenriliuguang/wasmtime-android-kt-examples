# Plan — native Android WebGPU repro of the androidx.webgpu `onSubmittedWorkDone` leak

## Goal

Determine whether the JNI global-reference leak behind
[wasmtime-android-kt#297](https://github.com/fenriliuguang/wasmtime-android-kt/issues/297)
reproduces with a **pure `androidx.webgpu`** Android app (no Wasmtime, no
`host-dawn`). If it does, the leak is upstream; if not, the `host-dawn` usage
pattern is the extra factor.

## Background (from wasmtime-android-kt)

- `androidx.webgpu:webgpu:1.0.0-alpha05`.
- `GPUQueue.onSubmittedWorkDone(Executor, GPURequestCallback)` is
  `@FastNative external`. Its native implementation `NewGlobalRef`s **both**
  the `callback` and the `executor` on every call and never `DeleteGlobalRef`s
  them.
- 2 refs/frame @ 120 Hz → `global reference table overflow (max=51200)` →
  `SIGABRT` on GpuThread at ~3.5 min (25,320 frames). Dump:
  - 25,312 × `ExternalSyntheticLambda4` (1 unique = the shared executor)
  - 25,308 × `queueSubmit$2` (the per-frame callback)
- `libwebgpu_c_bundled.so` exports only `Java_androidx_webgpu_*`, so there is
  no native `dlsym` fence workaround.
- `host-dawn` batches 2 frames per fence (`FENCE_BATCH = 2`), halving the leak
  to ~50,640 frames / 7.0 min. That is a mitigation, not a fix.

## Hypothesis

The leak is in the androidx.webgpu JNI layer, independent of Wasmtime /
`host-dawn`. A minimal native app that fences once per frame should overflow
at the same ~25k-frame scale.

## Design — new host `hosts/native-webgpu`

Out-of-tree, non-product host that **does not** `includeBuild`
wasmtime-android-kt. It depends only on `androidx.webgpu:webgpu:1.0.0-alpha05`
(the AAR ships `libwebgpu_c_bundled.so`).

Per-frame loop (Choreographer @ 120 Hz, GpuThread):

1. `GPU.createInstance()` → `requestAdapter(Vulkan)` → `requestDevice`.
2. `createSurface` / bind `SurfaceView` → configure (Fifo).
3. On each frame:
   a. `surface.getCurrentTexture()`.
   b. record a minimal render pass (clear to a solid color) via a command
      encoder, then `queue.submit([cmd])`.
   c. `queue.onSubmittedWorkDone(executor, callback)` — **once per frame**,
      mirroring `host-dawn` (this is the leak source).
   d. `surface.present()`.
4. Log frame count every 120 beats (same `FullscreenSurface` style).

The `executor` must be a single shared `Executor(Runnable::run)` (exactly
`host-dawn`'s `callbackExecutor`) and the `callback` a fresh object per frame,
so the dump signature matches (`ExternalSyntheticLambda*` + the per-frame
anonymous class).

### Success criteria

| Outcome | Conclusion |
|---------|------------|
| Overflow at ~25k frames with the same 2-object dump | Leak is upstream; `host-dawn` is not the cause |
| No overflow within 60k frames | `host-dawn` usage is the extra factor; shrink further (executor identity / callback capture / batch interplay) |
| Overflow but a different object in the dump | New leak surface; re-examine |

### Non-goals

- Not fixing the leak here (that is the runtime repo's upstream / self-hosted
  FFI track).
- Not measuring the 5 s hitch (separate D24 track).

## Steps

1. Add `hosts/native-webgpu` (own Gradle project; `androidx.webgpu` only).
2. `adb install` + run on V2458A @ 120 Hz.
3. Capture `logcat -b crash` global-ref dump on overflow.
4. Record the result in §Results here and update wasmtime-android-kt checklist
   C7 / issue #297.

## Results

Reproduced on **V2458A** (PD2415M, Android 14 / SDK 36, Mali mt6991) at 120 Hz
with `hosts/native-webgpu` (pure `androidx.webgpu:webgpu:1.0.0-alpha05`, no
Wasmtime, no `host-dawn`).

- Overflow at **~25,312 frames** (~3.5 min @ 120 Hz): `Fatal signal 6
  (SIGABRT)` on `GpuThread`, abort message
  `JNI ERROR (app bug): global reference table overflow (max=51200)`.
- Global-ref dump summary (exactly the predicted 2-object signature):

```
  25313 of ...MainActivity$$ExternalSyntheticLambda2 (1 unique instances)
  25312 of ...MainActivity$renderFrame$1 (25312 unique instances)
```

  `ExternalSyntheticLambda2` is the single shared `Executor(Runnable::run)`
  (compiler-generated lambda index; varies with source); `renderFrame$1` is the
  fresh per-frame `GPURequestCallback<Unit>`. 2 refs/frame.

### Conclusion

| Criterion | Result |
|-----------|--------|
| Overflow at ~25k frames with the same 2-object dump | **Leak is upstream; `host-dawn` is not the cause** |

The `onSubmittedWorkDone` JNI `NewGlobalRef` leak is in the androidx.webgpu
layer, independent of Wasmtime / `host-dawn`.

### Implementation note

`GPUInstance.processEvents()` must not run concurrently with GpuThread GPU
calls: a separate poller thread racing `submit` SIGSEGV'd on Mali
(`fault addr 0x8` in `Java_androidx_webgpu_GPUQueue_submit`) — the same race
`host-dawn` serializes with `gpuLock`. The repro pumps `processEvents()` inline
on GpuThread only during adapter/device setup, and never during the frame loop
(the leak is a `NewGlobalRef` at registration time, not at callback delivery).

## Status

Done — leak confirmed upstream (androidx.webgpu). See §Results.
