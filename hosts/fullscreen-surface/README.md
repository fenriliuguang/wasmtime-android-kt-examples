# fullscreen-surface

Fullscreen `SurfaceView` host. Draws whatever the loaded guest presents through `wasi-gfx` + `wasi:webgpu`.

## Run

1. Point `local.properties` at the Android SDK and a **wasmtime-android-kt** checkout (see `local.properties.example`).
2. Ensure that checkout has `android/jniLibs/**/libwasmtime_android_kt.so`.
3. Guests: `guests/rotating-cube/dist/guest.wasm` → `assets/guest.wasm` (launcher **fullscreen-cube**, no VRI overlay); `guests/boundary-2d/dist/guest.wasm` → `assets/border2d.wasm` (launcher **fullscreen-2d**, millisecond stopwatch on View / VRI). Rebuild each guest with its `build.ps1` if you change MoonBit sources.

```powershell
cd hosts/fullscreen-surface
.\gradlew.bat :app:installDebug
```

Another guest:

```powershell
.\gradlew.bat :app:installDebug "-Pguest.wasm=..\..\guests\other\dist\guest.wasm"
```

## Threads

- **GpuThread:** `GpuBackends.dawn()` (NativeGpu) + `Store.bindCanvasNativeWindow`, compile/instantiate, `callRunConcurrent`.
- **Main:** Surface callbacks + Choreographer `postGfxVsync` (1-slot; drops unconsumed beats).

On API 30+ the host pins the **peak** display mode for this resolution and `Surface.setFrameRate` at that Hz (H24/H27). API 31+ also `Window.setPreferMinimalPostProcessing`. Logcat tags: `FullscreenSurface` (Choreographer interval histogram every 120 beats) and runtime `GfxHitch` (acquire ns / 60 vs 120 Hz buckets).
