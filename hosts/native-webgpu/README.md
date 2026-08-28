# native-webgpu

Minimal pure-`androidx.webgpu` repro of the `GPUQueue.onSubmittedWorkDone` JNI
global-reference leak. **No Wasmtime, no `host-dawn`** — only
`androidx.webgpu:webgpu:1.0.0-alpha05` (the AAR ships `libwebgpu_c_bundled.so`).

Each frame records a trivial clear pass, `submit`s it, then calls
`onSubmittedWorkDone(sharedExecutor, freshCallback)`. The native implementation
`NewGlobalRef`s both the executor and the callback on every call and never
`DeleteGlobalRef`s them → 2 refs/frame → ART global reference table overflow
(`max=51200`) → `SIGABRT` on `GpuThread` at ~25,300 frames.

This exists to file an upstream issue. See
[`docs/native-webgpu-issue-report.md`](../../docs/native-webgpu-issue-report.md)
for a ready-to-paste write-up, and
[`docs/native-webgpu-leak-plan.md`](../../docs/native-webgpu-leak-plan.md) for the
investigation plan + results.

## Environment

| Item | Value |
|------|-------|
| Device | V2458A (PD2415M), Android 14 (SDK 36), Mali `mt6991`, 120 Hz |
| Dependency | `androidx.webgpu:webgpu:1.0.0-alpha05` |
| Build | AGP 9.3.1, Gradle 9.6.1, JDK 17+, `compileSdk 36.1` |

Repro is not device-specific: any 120 Hz Vulkan-capable device shows it; lower
refresh rates just take proportionally longer (60 Hz → ~7 min).

## Build & run

```powershell
cd hosts/native-webgpu
# local.properties: sdk.dir=C:/path/to/Android/Sdk
.\gradlew.bat :app:installDebug
```

```powershell
adb logcat -c
adb shell am start -n io.github.fenriliuguang.wasmtime.android.examples.nativewebgpu/.MainActivity
adb logcat -b crash -v time   # watch for the overflow dump
```

Expected: after ~3.5 min @ 120 Hz the process aborts with

```
Fatal signal 6 (SIGABRT), code -1 (SI_QUEUE) in tid ... (GpuThread)
Abort message: 'JNI ERROR (app bug): global reference table overflow (max=51200)global reference table dump:
  25313 of ...MainActivity$$ExternalSyntheticLambda2 (1 unique instances)   # shared executor
  25312 of ...MainActivity$renderFrame$1 (25312 unique instances)            # per-frame callback
  ...'
```

Frame progress is logged every 120 beats under the `NativeWebGpuLeak` tag.

## Threads

- **GpuThread:** surface setup + per-frame render/submit/fence/present.
- **Main:** Surface callbacks + Choreographer vsync (1-slot gate; drops
  unconsumed beats).

`GPUInstance.processEvents()` is pumped inline on GpuThread **only** during async
adapter/device setup. Do not call it from a separate thread while `submit` runs:
on Mali that races and SIGSEGVs in `Java_androidx_webgpu_GPUQueue_submit` (the
same race `host-dawn` serializes with `gpuLock`).
